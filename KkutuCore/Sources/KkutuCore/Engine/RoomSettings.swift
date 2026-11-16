public struct RoomOptions: Codable, Hashable, Sendable {
    public var manner = false       // 매너: 이을 수 없는 단어 금지
    public var injeong = false      // 어인정 허용
    public var mission = false      // 미션 글자
    public var noLoanword = false   // 외래어 금지
    public var strict = false       // 표준어만
    /// 어인정 단어를 받을 주제(끄투 theme_* 코드). nil이면 전부. 빌드 2·3은 이 키를 모르므로 선택 값이어야 한다.
    public var injeongThemes: Set<String>? = nil
    /// 복합어 허용: 사전에 없어도 명사 둘을 이은 단어면 받는다(이 앱의 확장). 빌드 12 이하는 이 키를 모르므로 선택 값이고, 꺼지면 nil로 둬서 옛 패킷과 같게 한다.
    public var compoundWords: Bool? = nil
    public var compound: Bool {
        get { compoundWords ?? false }
        set { compoundWords = newValue ? true : nil }
    }
    public init() {}
}

public enum MatchMode: String, Codable, Hashable, Sendable {
    case individual, team
    public var title: String { self == .team ? "팀전" : "개인전" }
}

public struct RoomSettings: Codable, Hashable, Sendable {
    public static let roundSecondsChoices = [10, 30, 60, 90, 120, 150]
    public var rounds = 5           // 1...10
    public var roundSeconds = 60
    public var maxPlayers = 8       // 2...8
    public var options = RoomOptions()
    /// 없으면 기존 빌드의 개인전 방. 새 방은 선택한 모드를 명시한다.
    public var mode: MatchMode? = nil
    public var matchMode: MatchMode { mode ?? .individual }
    /// 있으면 마블 룰렛 방. 빌드 5 이전은 이 키를 모르므로 선택 값이어야 한다.
    public var marble: MarbleSettings? = nil
    public init() {}
}
