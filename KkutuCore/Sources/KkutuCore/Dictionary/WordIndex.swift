import Foundation

/// 메모리 사전. 끄투 DB.kkutu.ko findOne/find와 kkutu_manner 캐시를 대신한다.
public final class WordIndex {
    private let byText: [String: Word]
    private let byFirst: [Character: [Word]]        // 파일 순서 유지
    private let byLength: [Int: [Word]]             // KOR_GROUP 단어만, 제목 생성용
    public var count: Int { byText.count }

    public init(words: [Word]) {
        var t: [String: Word] = [:]; t.reserveCapacity(words.count)
        var f: [Character: [Word]] = [:]
        var l: [Int: [Word]] = [:]
        for w in words {
            guard let c = w.text.first else { continue }
            t[w.text] = w
            f[c, default: []].append(w)
            if WordFilter.inKorGroup(w) { l[w.text.count, default: []].append(w) }
        }
        byText = t; byFirst = f; byLength = l
    }

    /// 각 줄 `단어\t품사\t플래그[\t주제]`. 컬럼이 모자라거나 플래그가 정수가 아니면 그 줄은 건너뛴다.
    public static func parse(tsv: String) -> WordIndex {
        var words: [Word] = []
        words.reserveCapacity(450_000)
        for lineBytes in tsv.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            let line = String(decoding: lineBytes, as: UTF8.self)
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3, let flag = Int(cols[2]) else { continue }
            let themes = cols.count >= 4 ? cols[3].split(separator: ",").map(String.init) : []
            words.append(Word(text: String(cols[0]), types: cols[1].split(separator: ",").map(String.init), flag: flag, themes: themes))
        }
        return WordIndex(words: words)
    }

    public static func load(url: URL) throws -> WordIndex {
        parse(tsv: try String(contentsOf: url, encoding: .utf8))
    }

    public func lookup(_ text: String) -> Word? { byText[text] }

    /// 판정용 조회. 사전에 없고 복합어 허용이면, 옵션을 통과하는 명사 둘로 나뉘는 3글자 이상 단어를 명사로 받는다.
    /// 로봇·한방단어 검사는 사전 목록만 보므로 복합어를 모른다.
    public func word(_ text: String, options: RoomOptions) -> Word? {
        if let w = byText[text] { return w }
        guard options.compound, text.count >= 3 else { return nil }
        func noun(_ s: Substring) -> Word? {
            guard let w = byText[String(s)], w.types.contains("1") || w.types.contains("INJEONG"),
                  WordFilter.rejectionCode(w, options: options) == nil else { return nil }
            return w
        }
        for i in text.indices.dropFirst() {
            if let a = noun(text[..<i]), let b = noun(text[i...]) {
                return Word(text: text, types: ["1"], flag: a.flag | b.flag, themes: a.themes + b.themes)
            }
        }
        return nil
    }

    /// 첫 글자가 first 또는 sub이고, 길이 2 이상, 옵션 통과, excluding에 없는 단어. 순서: first 버킷 → sub 버킷, 각각 파일 순서.
    public func candidates(first: Character, sub: Character?, options: RoomOptions, excluding: Set<String> = []) -> [Word] {
        var pool = byFirst[first] ?? []
        if let sub, sub != first { pool += byFirst[sub] ?? [] }
        return pool.filter { $0.text.count > 1 && !excluding.contains($0.text) && WordFilter.rejectionCode($0, options: options) == nil }
    }

    /// candidates와 같은 조건으로 세되 upTo에 닿으면 바로 멈춘다.
    public func countCandidates(first: Character, sub: Character?, options: RoomOptions, excluding: Set<String>, upTo limit: Int) -> Int {
        var n = 0
        var pool = byFirst[first] ?? []
        if let sub, sub != first { pool += byFirst[sub] ?? [] }
        for w in pool where w.text.count > 1 && !excluding.contains(w.text) && WordFilter.rejectionCode(w, options: options) == nil {
            n += 1
            if n >= limit { break }
        }
        return n
    }

    public func hasCandidate(first: Character, sub: Character?, options: RoomOptions, excluding: Set<String> = []) -> Bool {
        countCandidates(first: first, sub: sub, options: options, excluding: excluding, upTo: 1) > 0
    }

    /// 초성 줄이 initials와 같고 옵션을 통과하는 단어를 limit개까지. 첫 초성이 같은 버킷만 훑는다.
    public func words(initials: String, options: RoomOptions, limit: Int) -> [Word] {
        guard let head = initials.first else { return [] }
        var out: [Word] = []
        for (c, bucket) in byFirst where Hangul.choseong(c) == head {
            for w in bucket where w.text.count == initials.count && Hangul.initials(w.text) == initials
                && WordFilter.rejectionCode(w, options: options) == nil {
                out.append(w)
                if out.count >= limit { return out }
            }
        }
        return out
    }

    /// 제목 생성용: 길이가 length인 KOR_GROUP 단어 하나를 무작위로.
    public func randomWord(length: Int, rng: inout any RandomNumberGenerator) -> Word? {
        guard let bucket = byLength[length], !bucket.isEmpty else { return nil }
        return bucket[Int(rng.next() % UInt64(bucket.count))]
    }
}
