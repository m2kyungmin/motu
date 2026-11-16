public enum CosmeticSlot: String, Codable, Hashable, CaseIterable, Sendable {
    case head, eyes, mouth
    public var title: String {
        switch self { case .head: return "머리"; case .eyes: return "눈"; case .mouth: return "입" }
    }
    public var directory: String { self == .eyes ? "eye" : rawValue }
}

public struct CosmeticItem: Identifiable, Hashable, Sendable {
    public let sourceName: String
    public let name: String
    public let slot: CosmeticSlot
    public var id: String { "\(slot.rawValue)-\(sourceName)" }
    public var assetName: String { "MoremiItem_\(id)" }
    public var sourcePath: String { "\(slot.directory)/\(sourceName).png" }
}

/// 원작 모레미의 머리·눈·입 원본. 이 순서대로 승리 보상을 하나씩 해금한다.
public enum CosmeticCatalog {
    public static let items: [CosmeticItem] = [
        .init(sourceName: "redbere", name: "빨간 베레모", slot: .head),
        .init(sourceName: "sunglasses", name: "선글라스", slot: .eyes),
        .init(sourceName: "laugh", name: "웃는 입", slot: .mouth),
        .init(sourceName: "blue_headphone", name: "파란 헤드폰", slot: .head),
        .init(sourceName: "bigeye", name: "동그란 눈", slot: .eyes),
        .init(sourceName: "cat_mouth", name: "고양이 입", slot: .mouth),
        .init(sourceName: "nekomimi", name: "고양이 귀", slot: .head),
        .init(sourceName: "close_eye", name: "감은 눈", slot: .eyes),
        .init(sourceName: "merong", name: "메롱", slot: .mouth),
        .init(sourceName: "miljip", name: "밀짚모자", slot: .head),
        .init(sourceName: "brave_eyes", name: "용감한 눈", slot: .eyes),
        .init(sourceName: "oh", name: "놀란 입", slot: .mouth),
        .init(sourceName: "haksamo", name: "학사모", slot: .head),
        .init(sourceName: "scouter", name: "스카우터", slot: .eyes),
        .init(sourceName: "mustache", name: "콧수염", slot: .mouth),
        .init(sourceName: "orange_headphone", name: "주황 헤드폰", slot: .head),
        .init(sourceName: "lazy_eye", name: "졸린 눈", slot: .eyes),
        .init(sourceName: "beardoll", name: "수염", slot: .mouth),
        .init(sourceName: "blackbere", name: "검은 베레모", slot: .head),
        .init(sourceName: "cuspidal", name: "날카로운 눈", slot: .eyes),
        .init(sourceName: "decayed_mouth", name: "익살스러운 입", slot: .mouth),
        .init(sourceName: "brownbere", name: "갈색 베레모", slot: .head),
        .init(sourceName: "double_brows", name: "짙은 눈썹", slot: .eyes),
        .init(sourceName: "black_mask", name: "검은 마스크", slot: .head),
        .init(sourceName: "inverteye", name: "반전 눈", slot: .eyes),
        .init(sourceName: "white_mask", name: "흰 마스크", slot: .head),
        .init(sourceName: "hamster_G", name: "회색 햄스터", slot: .head),
        .init(sourceName: "hamster_O", name: "주황 햄스터", slot: .head),
        .init(sourceName: "twoeight", name: "이팔 가르마", slot: .head),
    ]

    public static func item(_ id: String?) -> CosmeticItem? { items.first { $0.id == id } }
}

public struct CharacterAppearance: Codable, Hashable, Sendable {
    public var head: String?
    public var eyes: String?
    public var mouth: String?
    public init() {}

    public func itemID(for slot: CosmeticSlot) -> String? {
        switch slot { case .head: return head; case .eyes: return eyes; case .mouth: return mouth }
    }

    public mutating func set(_ item: CosmeticItem?, for slot: CosmeticSlot) {
        let id = item?.slot == slot ? item?.id : nil
        switch slot { case .head: head = id; case .eyes: eyes = id; case .mouth: mouth = id }
    }

    /// 받은 값은 목록에 있는 부품만 같은 부위에 표시한다.
    public var sanitized: CharacterAppearance {
        var value = CharacterAppearance()
        for slot in CosmeticSlot.allCases { value.set(CosmeticCatalog.item(itemID(for: slot)), for: slot) }
        return value
    }
}

/// 기기에 저장하는 진행 상황. 같은 대전 결과를 다시 받아도 중복 가산하지 않는다.
public struct CustomizationProgress: Codable, Equatable, Sendable {
    public private(set) var wins = 0
    public private(set) var unlocked: [String] = []
    public private(set) var appearance = CharacterAppearance()
    private var creditedMatches: Set<String> = []
    public init() {}

    public var nextItem: CosmeticItem? { CosmeticCatalog.items.first { !unlocked.contains($0.id) } }

    @discardableResult public mutating func equip(_ id: String) -> Bool {
        guard unlocked.contains(id), let item = CosmeticCatalog.item(id) else { return false }
        appearance.set(item, for: item.slot)
        return true
    }

    public mutating func reset(_ slot: CosmeticSlot) { appearance.set(nil, for: slot) }

    /// 끝까지 진행한 개인전·팀전의 단독 승리. 연습·무승부·중도 종료에는 보상을 주지 않는다.
    @discardableResult public mutating func recordResult(gameID: String, snapshot: GameSnapshot, mode: MatchMode,
                                                       playerID: PlayerID, isPractice: Bool, isMarble: Bool = false) -> CosmeticItem? {
        guard !gameID.isEmpty, !creditedMatches.contains(gameID), !isPractice, !isMarble,
              snapshot.phase == .ended, snapshot.totalRounds > 0, snapshot.round > snapshot.totalRounds,
              snapshot.seats.count >= 2,
              let player = snapshot.seats.first(where: { $0.id == playerID && !$0.isRobot }) else { return nil }
        let won: Bool
        if mode == .team {
            let totals = snapshot.teamScores
            guard let team = player.team, totals.count >= 2, let score = totals[team] else { return nil }
            won = totals.allSatisfy { $0.key == team || score > $0.value }
        } else {
            let score = snapshot.scores[playerID, default: 0]
            won = snapshot.seats.allSatisfy { $0.id == playerID || score > snapshot.scores[$0.id, default: 0] }
        }
        guard won else { return nil }
        creditedMatches.insert(gameID)
        wins += 1
        guard let item = nextItem else { return nil }
        unlocked.append(item.id)
        return item
    }
}
