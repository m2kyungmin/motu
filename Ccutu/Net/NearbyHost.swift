import Foundation
import Network
import KkutuCore

@MainActor final class NearbyHost: HostTransport {
    var onMessage: (ClientMessage, PlayerID) -> Void = { _, _ in }
    var onPeerLost: (PlayerID) -> Void = { _ in }
    var shouldAccept: (PlayerID?) -> Bool = { _ in true }
    var onError: (String) -> Void = { _ in }
    let code: String
    private let hostID: PlayerID
    private let listener: NWListener
    private var info: [String: String]
    private var connections: [UUID: NearbyConnection] = [:]
    private var playerByConnection: [UUID: PlayerID] = [:]
    private var connectionByPlayer: [PlayerID: UUID] = [:]
    private var stopped = false
    // 연결 대기가 준비되기 전에 광고(service)를 다시 넣으면 Bonjour 등록이 끊겨
    // 대기가 -65563(ServiceNotRunning)으로 실패한다. 준비 전 변경은 모아 뒀다가 준비되면 한 번에 넣는다.
    private var listening = false
    private var advertised: [String: String] = [:]

    init(displayName: String, roomName: String, roomID: String, hostID: PlayerID,
         mode: MatchMode = .individual, code: String) throws {
        self.code = code
        self.hostID = hostID
        info = ["v": "2", "host": displayName, "room": roomName, "id": roomID, "h": hostID, "mode": mode.rawValue]
        listener = try NWListener(using: NearbySecurity.parameters(code: code))
        advertise()
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                if case .ready = state, !self.listening {
                    self.listening = true
                    if self.info != self.advertised { self.advertise() }
                }
                if case .failed = state { self.onError("근처 방을 열지 못했습니다. 로컬 네트워크 권한과 Wi-Fi를 확인해 주세요.") }
            }
        }
        listener.start(queue: .main)
    }

    func send(_ message: HostMessage, to player: PlayerID) {
        guard let id = connectionByPlayer[player], let data = try? JSONEncoder().encode(message) else { return }
        let transient: Bool
        if case .marbleFrame = message { transient = true } else { transient = false }
        connections[id]?.send(data, transient: transient)
    }

    func updateCount(_ count: Int, max: Int, mode: MatchMode) {
        var updated = info
        updated["count"] = "\(count)"; updated["max"] = "\(max)"; updated["mode"] = mode.rawValue
        guard updated != info else { return }
        info = updated
        if listening { advertise() }
    }

    private func advertise() {
        advertised = info
        let records = info.mapValues { Data($0.utf8) }
        listener.service = NWListener.Service(name: "\(info["id"] ?? "room")-\(hostID.prefix(8))",
            type: NearbySecurity.serviceType, txtRecord: NetService.data(fromTXTRecord: records))
    }

    private func accept(_ raw: NWConnection) {
        guard !stopped, connections.count < 16 else { raw.cancel(); return }
        let id = UUID(), connection = NearbyConnection(raw)
        connections[id] = connection
        connection.onPacket = { [weak self, weak connection] data in
            guard let self, let connection else { return }
            guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data) else { connection.close(); return }
            if self.playerByConnection[id] == nil {
                guard case .join(let player, _, _) = message,
                      !player.isEmpty, player.utf8.count <= 64, player != self.hostID,
                      self.connectionByPlayer[player] == nil, self.shouldAccept(player) else {
                    connection.close(); return
                }
                self.playerByConnection[id] = player
                self.connectionByPlayer[player] = id
            }
            guard let player = self.playerByConnection[id] else { return }
            if case .join(let claimed, _, _) = message, claimed != player { connection.close(); return }
            self.onMessage(message, player)
        }
        connection.onClosed = { [weak self] in
            guard let self else { return }
            self.connections[id] = nil
            if let player = self.playerByConnection.removeValue(forKey: id) {
                self.connectionByPlayer[player] = nil
                self.onPeerLost(player)
            }
        }
        connection.start()
        Task { [weak self, weak connection] in
            try? await Task.sleep(for: .seconds(10))
            if self?.playerByConnection[id] == nil { connection?.close() }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
        for connection in connections.values { connection.close(notify: false) }
        connections.removeAll(); playerByConnection.removeAll(); connectionByPlayer.removeAll()
    }
}
