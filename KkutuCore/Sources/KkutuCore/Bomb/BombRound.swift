import Foundation

/// 끝말잇기 폭탄 돌리기: 폰 한 대를 손에서 손으로 넘기며 잇는다. 도화선(시간)은 화면이 쥐고,
/// 여기는 끄투 규칙으로 단어만 판정한다(GameEngine.submit과 같은 거절 순서, 매너·한방 검사는 없음).
public struct BombRound: Sendable {
    public enum Outcome: Equatable, Sendable {
        case accepted
        case rejected(code: Int)     // 409 이미 나옴, 404 사전에 없음, 405·406 옵션 위반
        case notChainable            // 두 글자 미만이거나 첫 글자가 다름: 화면은 흔들기만
    }

    public private(set) var char: String
    public private(set) var subChar: String?
    public private(set) var chain: [String] = []
    private let dict: WordIndex
    private let options: RoomOptions

    public init(start: Character, dictionary: WordIndex, options: RoomOptions = RoomOptions()) {
        char = String(start)
        subChar = Hangul.subChar(start).map(String.init)
        dict = dictionary
        self.options = options
    }

    public mutating func submit(_ raw: String) -> Outcome {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GameEngine.isChainable(text, char: char, subChar: subChar), let last = text.last else { return .notChainable }
        if chain.contains(text) { return .rejected(code: 409) }
        guard let word = dict.word(text, options: options) else { return .rejected(code: 404) }
        if let code = WordFilter.rejectionCode(word, options: options) { return .rejected(code: code) }
        chain.append(text)
        char = String(last)
        subChar = Hangul.subChar(last).map(String.init)
        return .accepted
    }

    /// 첫 글자: 이을 단어가 넉넉한(minCandidates개 이상) 글자. 두 글자 단어의 첫 글자에서 고른다.
    public static func randomStart(dictionary: WordIndex, options: RoomOptions = RoomOptions(), minCandidates: Int = 30,
                                   rng: inout any RandomNumberGenerator) -> Character {
        for _ in 0..<50 {
            guard let c = dictionary.randomWord(length: 2, rng: &rng)?.text.first else { break }
            if dictionary.countCandidates(first: c, sub: Hangul.subChar(c), options: options, excluding: [], upTo: minCandidates) >= minCandidates {
                return c
            }
        }
        return "가"
    }
}
