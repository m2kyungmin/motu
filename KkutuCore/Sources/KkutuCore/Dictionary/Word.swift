public struct Word: Hashable, Sendable {
    public let text: String
    public let types: [String]   // 끄투 type 컬럼, 쉼표 분리. 예 ["1","14","0"], ["INJEONG"]
    public let flag: Int
    public let themes: [String]  // 끄투 theme 컬럼(분야·주제 코드). 없으면 빈 배열
    public init(text: String, types: [String], flag: Int, themes: [String] = []) {
        self.text = text; self.types = types; self.flag = flag; self.themes = themes
    }
}

public enum WordFlag {
    public static let loanword = 1, injeong = 2, spaced = 4, saturi = 8, old = 16, munhwa = 32
}

/// 끄투 const.js KOR_GROUP / KOR_STRICT / KOR_FLAG와 classic.js submit의 거절 순서.
public enum WordFilter {
    public static let korGroup: Set<String> = ["0", "1", "2", "3", "7", "8", "9", "11", "15", "16", "17", "18", "19", "20", "26", "INJEONG"]

    /// 주제 선택 창 목록. 끄투 kkutu.pug InjPickDiag처럼 KO_THEME + KO_INJEONG에서 IJP_EXCEPT(OIJ)를 빼고,
    /// 어인정 단어에 붙지 않는 KO_THEME(경제 등)도 뺐다(1001만 붙는다).
    public static let injeongThemes = [
        "1001",
        "IMS", "VOC", "KRR", "KTV",
        "NSK", "KOT", "DOT", "DRR", "DGM", "RAG", "LVL",
        "LOL", "MRN", "MMM", "MAP", "MKK", "MNG",
        "MOB", "HYK", "CYP", "HRH", "STA",
        "KGR", "ESB", "ELW", "OIM", "OVW", "NEX",
        "YRY", "KPO", "JLN", "JAN", "ZEL", "POK", "HAI",
        "HSS", "KMV", "HDC", "HOS",
    ]

    public static func inKorGroup(_ w: Word) -> Bool { w.types.contains { korGroup.contains($0) } }

    /// nil이면 허용. 404 사전에 없음(품사 그룹 밖·어인정 금지·고르지 않은 주제), 406 표준어 아님, 405 외래어.
    /// 끄투 끝말잇기는 어인정을 켜고 끄기만 한다. 주제 고르기는 단어 대결의 injpick을 빌려 온 이 앱의 확장이다.
    public static func rejectionCode(_ w: Word, options: RoomOptions) -> Int? {
        if !inKorGroup(w) { return 404 }
        if w.flag & WordFlag.injeong != 0 {
            if !options.injeong { return 404 }
            if let picked = options.injeongThemes, !w.themes.contains(where: picked.contains) { return 404 }
        }
        if options.strict {
            let strictType = w.types.contains { $0 == "1" || $0 == "INJEONG" }
            if !strictType || w.flag >= 4 { return 406 }
        }
        if options.noLoanword && w.flag & WordFlag.loanword != 0 { return 405 }
        return nil
    }
}
