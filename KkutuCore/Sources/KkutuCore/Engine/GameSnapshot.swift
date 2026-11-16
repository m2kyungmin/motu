public struct GameSnapshot: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Sendable { case idle, starting, roundReady, turn, turnResult, ended }
    public var phase: Phase = .idle
    public var title = ""
    public var round = 0
    public var totalRounds: Int
    public var seats: [Player] = []
    public var turnIndex = 0
    public var char = ""
    public var subChar: String? = nil
    public var mission: String? = nil
    public var chain: [String] = []
    public var scores: [PlayerID: Int] = [:]
    public var roundTimeMs = 0
    public var turnTimeMs = 0
    // 방장 승계용. 빌드 2가 보낸 스냅샷(키 없음)도 읽히도록 선택 값으로 둔다.
    /// 끄투 game.dic: 게임 전체에서 단어별 사용 횟수(반복 감점).
    public var wordUses: [String: Int]? = nil
    /// .turnResult 다음 단계. true면 시간 초과로 라운드가 끝나 다음 라운드, false면 다음 사람 차례.
    public var roundOver: Bool? = nil

    public init(totalRounds: Int) { self.totalRounds = totalRounds }
    public var currentPlayer: Player? { seats.indices.contains(turnIndex) ? seats[turnIndex] : nil }

    public var teamScores: [Int: Int] {
        seats.reduce(into: [:]) { totals, player in
            if let team = player.team { totals[team, default: 0] += scores[player.id, default: 0] }
        }
    }
}
