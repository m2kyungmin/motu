import Foundation

/// 내기 게임 "공 넣기"의 한 차례: 제한 시간 동안 문제(초성 또는 시작 글자)에 맞는 단어를 많이 친다.
/// 시간은 화면이 쥐고, 여기는 단어만 판정한다. 맞힌 단어 하나가 공 하나를 넣거나 뺄 권리다.
public struct WordDash: Sendable {
    public enum Prompt: Codable, Hashable, Sendable {
        case initials(String)       // "ㅅㄱ": 글자 수가 같고 글자마다 초성이 같아야 한다(ㄲ은 ㄱ이 아니다)
        case starts(String)         // "사"(한 글자): 두 글자 이상, 첫 글자가 같거나 두음법칙으로 바뀐 글자

        /// 화면에 띄울 문제 글.
        public var text: String {
            switch self {
            case .initials(let s), .starts(let s): return s
            }
        }

        /// 시작 글자 문제의 두음법칙 글자("녀" → "여").
        public var subChar: String? {
            guard case .starts(let s) = self, let c = s.first else { return nil }
            return Hangul.subChar(c).map(String.init)
        }
    }

    public enum Outcome: Equatable, Sendable {
        case accepted
        case rejected(code: Int)    // 409 이미 씀, 404 사전에 없음, 405·406 옵션 위반
        case offPrompt              // 문제에 안 맞음: 화면은 흔들기만
    }

    public let prompt: Prompt
    public private(set) var words: [String] = []
    private let dict: WordIndex
    private let options: RoomOptions

    public init(prompt: Prompt, dictionary: WordIndex, options: RoomOptions = RoomOptions()) {
        self.prompt = prompt
        dict = dictionary
        self.options = options
    }

    public static func fits(_ text: String, _ prompt: Prompt) -> Bool {
        switch prompt {
        case .initials(let pattern):
            return Hangul.initials(text) == pattern
        case .starts(let s):
            guard text.count > 1, let first = text.first.map(String.init) else { return false }
            return first == s || first == prompt.subChar
        }
    }

    public mutating func submit(_ raw: String) -> Outcome {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.fits(text, prompt) else { return .offPrompt }
        if words.contains(text) { return .rejected(code: 409) }
        guard let word = dict.word(text, options: options) else { return .rejected(code: 404) }
        if let code = WordFilter.rejectionCode(word, options: options) { return .rejected(code: code) }
        words.append(text)
        return .accepted
    }

    /// 놓친 답 몇 개(끝난 뒤 보여 주기용). 낯선 말이 덜 나오게 표준어에서만 고르고, 이미 쓴 단어는 뺀다.
    public func samples(_ n: Int) -> [String] {
        var strict = options; strict.strict = true
        return Array(Self.answers(prompt, dictionary: dict, options: strict, limit: 300).filter { !words.contains($0) }.shuffled().prefix(n))
    }

    /// 문제의 답을 limit개까지(사전 순서).
    public static func answers(_ prompt: Prompt, dictionary: WordIndex, options: RoomOptions, limit: Int) -> [String] {
        switch prompt {
        case .initials(let p):
            return dictionary.words(initials: p, options: options, limit: limit).map(\.text)
        case .starts(let s):
            guard let c = s.first else { return [] }
            return dictionary.candidates(first: c, sub: Hangul.subChar(c), options: options).prefix(limit).map(\.text)
        }
    }

    public enum Kind: String, CaseIterable, Sendable { case initials, starts }

    /// 답이 minAnswers개 이상인 문제. 두 글자 단어에서 뽑아 초성 두 개 또는 첫 글자로 만든다. used는 피한다.
    public static func randomPrompt(_ kind: Kind, dictionary: WordIndex, options: RoomOptions = RoomOptions(),
                                    minAnswers: Int = 30, avoiding used: Set<String> = [],
                                    rng: inout any RandomNumberGenerator) -> Prompt {
        for _ in 0..<80 {
            guard let w = dictionary.randomWord(length: 2, rng: &rng)?.text, let c = w.first else { break }
            let p: Prompt
            let n: Int
            switch kind {
            case .initials:
                guard let i = Hangul.initials(w) else { continue }
                p = .initials(i)
                guard !used.contains(p.text) else { continue }
                n = dictionary.words(initials: i, options: options, limit: minAnswers).count
            case .starts:
                p = .starts(String(c))
                guard !used.contains(p.text) else { continue }
                n = dictionary.countCandidates(first: c, sub: Hangul.subChar(c), options: options, excluding: [], upTo: minAnswers)
            }
            if n >= minAnswers { return p }
        }
        return kind == .initials ? .initials("ㅅㄱ") : .starts("사")   // 실제 사전에서 답이 넉넉한 기본값
    }
}

/// 공 장부: 사람마다 공 개수. 자기 공은 1개 밑으로 못 빼고(아무도 빠져나가지 못하게), 전체는 cap을 못 넘는다.
public struct BallLedger: Equatable, Sendable {
    public private(set) var counts: [Int]
    public let cap: Int
    public var total: Int { counts.reduce(0, +) }

    public init(players: Int, start: Int, cap: Int = 60) {
        counts = Array(repeating: max(1, start), count: players)
        self.cap = cap
    }

    public func canRemove(_ i: Int) -> Bool { counts[i] > 1 }
    public func canAdd(_ i: Int) -> Bool { total < cap }

    @discardableResult public mutating func remove(_ i: Int) -> Bool {
        guard canRemove(i) else { return false }
        counts[i] -= 1
        return true
    }

    @discardableResult public mutating func add(_ i: Int) -> Bool {
        guard canAdd(i) else { return false }
        counts[i] += 1
        return true
    }

    /// 경주에 넣을 공 주인 목록. 사람별로 몰리지 않게 섞는다(놓는 순서가 결과를 정하지 않도록).
    public func shuffledBalls(rng: inout any RandomNumberGenerator) -> [Int] {
        counts.enumerated().flatMap { i, n in Array(repeating: i, count: n) }.shuffled(using: &rng)
    }
}
