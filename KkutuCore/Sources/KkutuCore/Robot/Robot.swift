import Foundation

/// 끄투 classic.js readyRobot 이식. hit 데이터가 없어 hit 정렬·HIT_LIMIT 포기는 뺐다(스펙 §5.7).
public enum Robot {
    /// 원작 Server/lib/Web/lang/ko_KR.json의 aiLevel0...4.
    public static let levelNames = ["왕초보", "초보", "적절", "고수", "사기"]
    public static func levelName(_ level: Int) -> String { levelNames[max(0, min(4, level))] }
    public static let startDelay = [1200, 800, 400, 200, 0]
    public static let typeCoef = [1250, 750, 500, 250, 0]
    public static let thinkCoef = [4, 2, 1, 0, 0]
    public static let lengthLimit = [3, 4, 9, 99, 99]
    /// ponytail: 덤프에 hit이 없어 넣는 보정값(끄투 운영 서버의 흔한 단어 hit 수준). 로봇이 느리면 올리고 빠르면 내린다.
    public static var assumedHit = 20.0

    public struct Context {
        public let char: Character
        public let subChar: Character?
        public let turnTimeMs: Int
        public let firstMove: Bool
        public let manner: Bool
        public let chain: [String]
        public let done: Set<String>
        public let options: RoomOptions
        public init(char: Character, subChar: Character?, turnTimeMs: Int, firstMove: Bool, manner: Bool, chain: [String], done: Set<String>, options: RoomOptions) {
            self.char = char; self.subChar = subChar; self.turnTimeMs = turnTimeMs; self.firstMove = firstMove
            self.manner = manner; self.chain = chain; self.done = done; self.options = options
        }
    }

    /// nil이면 포기(턴이 그냥 시간 초과된다).
    public static func choose(level rawLevel: Int, context c: Context, dict: WordIndex, rng: inout any RandomNumberGenerator) -> (text: String, delayMs: Int)? {
        let level = max(0, min(4, rawLevel))
        let excluding = Set(c.chain)
        var list = dict.candidates(first: c.char, sub: c.subChar, options: c.options, excluding: excluding)
        guard !list.isEmpty else { return nil }

        if level >= 3 && c.done.isEmpty {
            if unit(&rng) < 0.5 { list.sort { $0.text.count > $1.text.count } }     // Swift 5+ sort는 안정 정렬
            if list[0].text.count < 8 && c.turnTimeMs >= 2300 {
                var order: [Character] = []
                var groups: [Character: [Word]] = [:]
                for w in list {
                    let last = w.text.last!
                    if groups[last] == nil { order.append(last) }
                    groups[last, default: []].append(w)
                }
                var counted = order.map { last in
                    (char: last, n: dict.countCandidates(first: last, sub: Hangul.subChar(last), options: c.options, excluding: excluding, upTo: 10))
                }
                counted.sort { $0.n < $1.n }
                if c.manner || c.firstMove { counted.removeAll { $0.n == 0 } }
                guard let pick = counted.first else { return nil }
                list = groups[pick.char] ?? []
            }
        }

        guard let w = list.first(where: { $0.text.count <= lengthLimit[level] && !c.done.contains($0.text) }) else { return nil }
        var delay = Double(startDelay[level])
        delay += 500 * Double(thinkCoef[level]) * unit(&rng) / log(1.1 + assumedHit)
        delay += Double(w.text.count * typeCoef[level])
        return (w.text, Int(delay))
    }

    /// [0, 1) 난수. 테스트의 ZeroRNG는 0, 999를 주는 RNG는 0.999.
    private static func unit(_ rng: inout any RandomNumberGenerator) -> Double {
        Double(rng.next() % 1000) / 1000.0
    }
}
