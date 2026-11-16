import KkutuCore

/// 가까운 기기와 Game Center에서 같은 방장 코어를 연결한다.
@MainActor protocol HostTransport: AnyObject {
    var onMessage: (ClientMessage, PlayerID) -> Void { get set }
    var onPeerLost: (PlayerID) -> Void { get set }
    var shouldAccept: (PlayerID?) -> Bool { get set }
    func send(_ message: HostMessage, to player: PlayerID)
    func updateCount(_ count: Int, max: Int, mode: MatchMode)
    func stop()
}
