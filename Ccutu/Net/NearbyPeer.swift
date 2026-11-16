import Foundation
import Network
import KkutuCore

@MainActor @Observable final class NearbyPeer {
    struct FoundRoom: Identifiable, Hashable {
        let endpoint: NWEndpoint
        let hostName: String
        let roomName: String
        let count: String
        let roomID: String
        let hostID: PlayerID
        let mode: MatchMode
        var id: String { roomID + ":" + hostID }
    }
    private(set) var rooms: [FoundRoom] = []
    private(set) var errorMessage: String?
    var onConnected: () -> Void = {}
    var onMessage: (HostMessage) -> Void = { _ in }
    var onDisconnected: () -> Void = {}
    var autoJoin: (roomID: String, hostID: PlayerID, me: PlayerID, code: String)? {
        didSet { findMigrationHost() }
    }
    private let browser: NWBrowser
    private var connection: NearbyConnection?
    private var stopped = false

    init() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: NearbySecurity.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.rooms = results.compactMap { result in
                    guard case .bonjour(let record) = result.metadata else { return nil }
                    func text(_ key: String) -> String? { record[key] }
                    guard text("v") == "2", let roomID = text("id"), let hostID = text("h") else { return nil }
                    let count = text("count").map { "\($0)/\(text("max") ?? "8")" } ?? ""
                    return FoundRoom(endpoint: result.endpoint, hostName: text("host") ?? "플레이어",
                        roomName: text("room") ?? "모투", count: count, roomID: roomID, hostID: hostID,
                        mode: text("mode").flatMap(MatchMode.init(rawValue:)) ?? .individual)
                }.sorted { $0.id < $1.id }
                self.findMigrationHost()
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                switch state {
                case .failed, .waiting: self.errorMessage = "근처 방을 찾지 못했습니다. 설정에서 로컬 네트워크 권한과 Wi-Fi를 확인해 주세요."
                case .ready: self.errorMessage = nil
                default: break
                }
            }
        }
        browser.start(queue: .main)
    }

    func invite(_ room: FoundRoom, code: String) {
        guard !stopped else { return }
        connection?.close(notify: false)
        let link = NearbyConnection(NWConnection(to: room.endpoint, using: NearbySecurity.parameters(code: code)))
        connection = link
        link.onReady = { [weak self] in self?.onConnected() }
        link.onPacket = { [weak self] data in
            guard let message = try? JSONDecoder().decode(HostMessage.self, from: data) else { return }
            self?.onMessage(message)
        }
        link.onClosed = { [weak self] in self?.onDisconnected() }
        link.start()
    }

    func send(_ message: ClientMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        connection?.send(data)
    }

    private func findMigrationHost() {
        guard connection == nil, let target = autoJoin,
              let room = rooms.first(where: { $0.roomID == target.roomID && $0.hostID == target.hostID }) else { return }
        invite(room, code: target.code)
    }

    func stop() {
        stopped = true
        browser.browseResultsChangedHandler = nil; browser.stateUpdateHandler = nil
        browser.cancel()
        connection?.close(notify: false); connection = nil
    }
}
