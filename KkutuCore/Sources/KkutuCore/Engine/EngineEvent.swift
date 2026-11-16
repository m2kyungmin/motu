public enum EngineInput {
    case start(players: [Player])            // 좌석 순서 그대로 사용(호출자가 섞는다)
    case submit(player: PlayerID, text: String)
    case playerLeft(PlayerID)
    case deadline                            // handle이 돌려준 nextDeadlineMs가 됐을 때
}

/// 글자 필드는 한 글자짜리 String (Character는 Codable이 아님).
public enum EngineEvent: Codable, Hashable, Sendable {
    case starting(title: String)
    case roundReady(round: Int, char: String, subChar: String?, mission: String?)
    case turnStart(turn: Int, player: PlayerID, char: String, subChar: String?, speed: Int, roundTimeMs: Int, turnTimeMs: Int, mission: String?)
    case turnEnd(player: PlayerID, ok: Bool, value: String?, score: Int, bonus: Int, hint: String?)
    case turnError(player: PlayerID, code: Int, value: String)
    case gameEnd(ranking: [ScoreEntry])
}
