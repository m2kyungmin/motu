import Foundation
import GameKit
import KkutuCore

/// Game Center의 인증된 상대와 앱의 플레이어 ID를 묶는다. 방장 메시지는 현재 방장에게서만 받는다.
@MainActor final class GameCenterTransport: NSObject, HostTransport, GKMatchDelegate {
    private struct Hello: Codable {
        let version: Int
        let id: PlayerID
        let mode: MatchMode
        /// 이미 방에 있는 사람이 보낼 때 지금 방장. 친구 추가로 늦게 온 사람이 이걸 보고 방장을 따른다.
        var host: PlayerID?
    }
    /// 3: 늦게 합류한 사람의 방장 선출(host) 추가. 2와 섞이면 방장을 따로 뽑으므로 버전 오류로 막는다.
    private static let helloVersion = 3
    private enum Packet: Codable {
        case hello(Hello)
        case client(ClientMessage)
        case host(HostMessage)
        case hostReady(PlayerID)
    }
    var onMessage: (ClientMessage, PlayerID) -> Void = { _, _ in }
    var onPeerLost: (PlayerID) -> Void = { _ in }
    var shouldAccept: (PlayerID?) -> Bool = { _ in true }
    var onHostMessage: (HostMessage) -> Void = { _ in }
    var onHostLost: () -> Void = {}
    var onHostReady: () -> Void = {}
    var onReady: (Bool) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }
    let match: GKMatch
    private let myID: PlayerID
    private let mode: MatchMode
    private let localGameID: String
    private var players: [String: GKPlayer] = [:]
    private var identities: [String: Hello] = [:]
    private var hostGameID: String?
    private var started = false
    private var stopped = false
    private var ready = false
    private var announcedHosts: Set<String> = []
    private var helloSent: Set<String> = []
    var isHost: Bool { hostGameID == localGameID }

    init(match: GKMatch, myID: PlayerID, mode: MatchMode) {
        self.match = match; self.myID = myID; self.mode = mode
        localGameID = GKLocalPlayer.local.gamePlayerID
        super.init()
        players = Dictionary(uniqueKeysWithValues: match.players.map { ($0.gamePlayerID, $0) })
        identities[localGameID] = Hello(version: Self.helloVersion, id: myID, mode: mode)
    }

    func start() {
        guard !started else { return }
        started = true
        match.delegate = self
        for player in players.values { sendHello(to: player) }
        bootstrap()
        // 상대가 아직 GKMatch.delegate를 연결하기 전 도착한 첫 인사를 다시 보낸다.
        Task { [weak self] in
            for _ in 0..<8 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !self.stopped else { return }
                for player in self.players.values where self.identities[player.gamePlayerID] == nil {
                    self.helloSent.remove(player.gamePlayerID)
                    self.sendHello(to: player)
                }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !self.stopped, !self.ready else { return }
            self.onError("친구와 연결하지 못했습니다. 같은 버전인지 확인하고 다시 초대해 주세요.")
        }
    }

    private func bootstrap() {
        guard !ready, match.expectedPlayerCount == 0,
              let host = HostElection.elect(local: localGameID, peers: Array(players.keys),
                  hellos: identities.mapValues { HostElection.Hello(player: $0.id, host: $0.host) }) else { return }
        hostGameID = host
        ready = true
        onReady(isHost)
        if isHost { announceHost() }
    }

    /// 모든 기기가 같은 RoomState의 입장 순서로 새 방장을 고른다. GKMatch는 그대로 유지한다.
    func selectHost(_ playerID: PlayerID) -> Bool {
        guard let id = identities.first(where: { $0.value.id == playerID })?.key else { return false }
        hostGameID = id
        if !isHost, announcedHosts.contains(id) { onHostReady() }
        return true
    }

    func announceHost() {
        guard isHost else { return }
        for player in players.values { sendPacket(.hostReady(myID), to: player) }
    }

    func sendClient(_ message: ClientMessage) {
        guard !isHost, let id = hostGameID, let host = players[id] else { return }
        sendPacket(.client(message), to: host)
    }

    func send(_ message: HostMessage, to playerID: PlayerID) {
        guard isHost, let id = identities.first(where: { $0.value.id == playerID })?.key,
              let player = players[id] else { return }
        let transient: Bool
        if case .marbleFrame = message { transient = true } else { transient = false }
        sendPacket(.host(message), to: player, transient: transient)
    }

    func updateCount(_ count: Int, max: Int, mode: MatchMode) {}

    private func sendHello(to player: GKPlayer) {
        guard !helloSent.contains(player.gamePlayerID) else { return }
        helloSent.insert(player.gamePlayerID)
        let host = ready ? hostGameID.flatMap { identities[$0]?.id } : nil
        sendPacket(.hello(Hello(version: Self.helloVersion, id: myID, mode: mode, host: host)), to: player)
    }

    private func sendPacket(_ packet: Packet, to player: GKPlayer, transient: Bool = false) {
        guard !stopped, let data = try? JSONEncoder().encode(packet), data.count <= NetworkPacketDecoder.maximumSize else { return }
        do { try match.send(data, to: [player], dataMode: transient ? .unreliable : .reliable) }
        catch { if !transient { onError("게임 데이터를 보내지 못했습니다. \(error.localizedDescription)") } }
    }

    private func receive(_ data: Data, from player: GKPlayer) {
        guard !stopped, data.count <= NetworkPacketDecoder.maximumSize,
              players[player.gamePlayerID] != nil,
              let packet = try? JSONDecoder().decode(Packet.self, from: data) else { return }
        let gameID = player.gamePlayerID
        switch packet {
        case .hello(let hello):
            guard hello.version == Self.helloVersion, hello.mode == mode, !hello.id.isEmpty, hello.id.utf8.count <= 64,
                  hello.id != myID,
                  !identities.contains(where: { $0.key != gameID && $0.value.id == hello.id }),
                  identities[gameID] == nil || identities[gameID]?.id == hello.id else {
                onError("친구의 모투 버전 또는 게임 모드가 다릅니다. 다시 초대해 주세요."); return
            }
            let firstHello = identities[gameID] == nil
            identities[gameID] = hello
            if firstHello {
                helloSent.remove(gameID)
                sendHello(to: player)
                // 친구 추가로 새로 온 사람에게만 방장임을 알린다.
                if ready, isHost { sendPacket(.hostReady(myID), to: player) }
            }
            bootstrap()
        case .client(let message):
            guard ready, isHost, let sender = identities[gameID]?.id else { return }
            if case .join(let claimed, _, _) = message {
                guard claimed == sender else { return }
                guard shouldAccept(sender) else { sendPacket(.host(.error(code: 429)), to: player); return }
            }
            onMessage(message, sender)
        case .host(let message):
            guard ready, !isHost, gameID == hostGameID else { return }
            onHostMessage(message)
        case .hostReady(let hostID):
            guard identities[gameID]?.id == hostID else { return }
            announcedHosts.insert(gameID)
            if ready, !isHost, gameID == hostGameID { onHostReady() }
        }
    }

    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        Task { @MainActor in self.receive(data, from: player) }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        Task { @MainActor in
            guard !self.stopped else { return }
            let id = player.gamePlayerID
            switch state {
            case .connected:
                self.players[id] = player
                self.sendHello(to: player)
                self.bootstrap()
            case .disconnected:
                self.players[id] = nil
                self.helloSent.remove(id)
                guard let identity = self.identities[id] else { self.bootstrap(); return }
                if id == self.hostGameID { self.onHostLost() }
                else if self.isHost { self.onPeerLost(identity.id) }
            default: break
            }
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        Task { @MainActor in
            guard !self.stopped else { return }
            self.onError(error?.localizedDescription ?? "Game Center 연결이 끊겼습니다.")
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        match.delegate = nil
        match.disconnect()
    }
}
