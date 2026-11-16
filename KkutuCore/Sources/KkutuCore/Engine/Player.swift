public typealias PlayerID = String

public struct Player: Codable, Hashable, Sendable {
    public let id: PlayerID
    public let name: String
    public let robotLevel: Int?     // nil이면 사람
    public let team: Int?          // 팀전: 1...4. 이전 빌드·개인전은 nil
    public let appearance: CharacterAppearance?
    public var isRobot: Bool { robotLevel != nil }
    public init(id: PlayerID, name: String, robotLevel: Int? = nil, team: Int? = nil, appearance: CharacterAppearance? = nil) {
        self.id = id; self.name = name; self.robotLevel = robotLevel; self.team = team
        self.appearance = appearance
    }
}

/// 원작의 팀 검사·좌석 순서. 두 팀 이상, 같은 인원수로 팀마다 한 명씩 번갈아 앉는다.
public enum TeamPlay {
    public static func isBalanced(_ players: [Player]) -> Bool {
        guard players.allSatisfy({ (1...4).contains($0.team ?? 0) }) else { return false }
        let teams = Dictionary(grouping: players, by: { $0.team! })
        return teams.count >= 2 && Set(teams.values.map(\.count)).count == 1
    }

    public static func turnOrder(_ players: [Player], teams: [Int]) -> [Player] {
        let groups = Dictionary(grouping: players, by: { $0.team ?? 0 })
        let count = groups.values.map(\.count).max() ?? 0
        return (0..<count).flatMap { index in teams.compactMap { team in
            let members = groups[team] ?? []
            return members.indices.contains(index) ? members[index] : nil
        } }
    }
}

public struct ScoreEntry: Codable, Hashable, Sendable {
    public let player: PlayerID
    public let score: Int
    public let rank: Int            // 1부터, 동점은 같은 순위
}
