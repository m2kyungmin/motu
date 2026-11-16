import Foundation
import KkutuCore

/// 화면이 보는 유일한 모델. 호스트·참가자 모두 같은 HostMessage를 받아 상태를 만든다.
@MainActor @Observable
final class RoomClient {
    let myID: PlayerID
    private(set) var isHost: Bool
    /// 방장이 나가 새 방장을 기다리는 중이면 나간 방장의 ID. 새 방장의 방 상태가 오면 지운다.
    var migratingFrom: PlayerID?
    private(set) var room: RoomState?
    private(set) var snapshot: GameSnapshot?
    private(set) var lastEvent: EngineEvent?
    private(set) var eventSeq = 0
    private(set) var turnReceivedAt = Date()      // 타이머 바의 기준 시각
    private(set) var ranking: [ScoreEntry]?
    var unlockedReward: CosmeticItem?
    var earnedWin = false
    @ObservationIgnored var onGameEnd: (GameSnapshot) -> Void = { _ in }
    struct ChatLine: Equatable { let seq: Int; let player: PlayerID; let text: String }
    private(set) var lastChat: ChatLine?
    // 마블 룰렛
    private(set) var marble: MarbleSnapshot?
    private(set) var marbleDeadline = Date()
    struct MarbleReject: Equatable { let seq: Int; let code: Int; let word: String }
    private(set) var marbleReject: MarbleReject?
    /// 경주 프레임은 초당 십수 번 오므로 관찰 상태로 두지 않고 장면에 바로 넘긴다.
    @ObservationIgnored var onFrame: (MarbleFrame) -> Void = { _ in }
    /// 방장 기기만: 장면이 만든 프레임을 참가자들에게 보낸다.
    @ObservationIgnored var sendFrame: (MarbleFrame) -> Void = { _ in }
    var errorCode: Int?
    var disconnected = false
    var connectFailed = false
    var connectionError: String?
    var send: (ClientMessage) -> Void = { _ in }
    var onLeave: () -> Void = {}

    init(myID: PlayerID, isHost: Bool) { self.myID = myID; self.isHost = isHost }

    func apply(_ m: HostMessage) {
        switch m {
        case .roomState(let s):
            room = s
            if let old = migratingFrom, s.hostID != old { migratingFrom = nil }
            if !s.gaming { snapshot = nil; lastEvent = nil; ranking = nil; marble = nil; unlockedReward = nil; earnedWin = false }
        case .gameEvent(let e, let snap):
            snapshot = snap
            lastEvent = e
            eventSeq += 1
            if case .turnStart = e { turnReceivedAt = Date() }
            if case .gameEnd(let r) = e { ranking = r; onGameEnd(snap) }
        case .error(let code):
            errorCode = code
        case .chat(let from, let text):
            // 방장이 보낸 값도 그대로 믿지 않고 길이를 다시 자른다.
            lastChat = ChatLine(seq: (lastChat?.seq ?? 0) + 1, player: from, text: String(text.prefix(HostCore.chatLimit)))
        case .marble(let s):
            marble = s
            marbleDeadline = Date().addingTimeInterval(Double(s.remainingMs) / 1000)
        case .marbleFrame(let f):
            onFrame(f)
        case .marbleReject(let code, let word):
            marbleReject = MarbleReject(seq: (marbleReject?.seq ?? 0) + 1, code: code, word: word)
        }
    }

    var isMyTurn: Bool { snapshot?.phase == .turn && snapshot?.currentPlayer?.id == myID }
    var me: RoomPlayer? { room?.players.first { $0.id == myID } }

    /// iOS 27 인터넷 방: 나가면 앱을 다시 켜야 인터넷 대전을 다시 열 수 있어 한 번 묻는다.
    var confirmsLeave = false
    var askingLeave = false

    func leave() {
        if confirmsLeave, room != nil { askingLeave = true } else { leaveNow() }
    }

    func leaveNow() { send(.leave); onLeave() }

    /// 방장 승계로 이 기기가 방장이 됐다.
    func promoteToHost() { isHost = true }
}
