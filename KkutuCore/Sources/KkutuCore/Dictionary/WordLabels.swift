/// 끄투 ko_KR.json의 class_* / theme_* 이름표와, 단어 기록에 붙는 짧은 설명.
/// 끄투 사전의 뜻(mean) 컬럼은 공개 저장소에서 전부 자리표시자라, 보여 줄 수 있는 건 품사·분야·표시뿐이다.
public enum WordLabels {
    /// 끄투 pushHistory가 단어 옆에 다는 품사 약칭. 이름 없는 코드(0 등)는 끄투처럼 건너뛴다.
    public static let classNames: [String: String] = [
        "1": "명",
        "2": "대명",
        "3": "수",
        "4": "조",
        "5": "동",
        "6": "형",
        "7": "관",
        "8": "부",
        "9": "감",
        "10": "접",
        "11": "의명",
        "12": "조동",
        "13": "조형",
        "14": "어",
        "15": "관·명",
        "16": "수·관",
        "17": "명·부",
        "18": "감·명",
        "19": "대·부",
        "20": "대·감",
        "21": "동·형",
        "22": "관·감",
        "23": "부·감",
        "24": "의명·조",
        "25": "수·관·명",
        "26": "대·관",
    ]

    /// 끄투 processWord가 뜻 앞에 붙이는 분야·주제 이름.
    public static let themeNames: [String: String] = [
        "10": "가톨릭",
        "20": "건설",
        "30": "경제",
        "40": "고적",
        "50": "고유",
        "60": "공업",
        "70": "광업",
        "80": "교육",
        "90": "교통",
        "100": "군사",
        "110": "기계",
        "120": "기독교",
        "130": "논리",
        "140": "농업",
        "150": "문학",
        "160": "물리",
        "170": "미술",
        "180": "민속",
        "190": "동물",
        "200": "법률",
        "210": "불교",
        "220": "사회",
        "230": "생물",
        "240": "수학",
        "250": "수산",
        "260": "수공",
        "270": "식물",
        "280": "심리",
        "290": "약학",
        "300": "언론",
        "310": "언어",
        "320": "역사",
        "330": "연영",
        "340": "예술",
        "350": "운동",
        "360": "음악",
        "370": "의학",
        "380": "인명",
        "390": "전기",
        "400": "정치",
        "410": "종교",
        "420": "지리",
        "430": "지명",
        "440": "책명",
        "450": "천문",
        "460": "철학",
        "470": "출판",
        "480": "통신",
        "490": "컴퓨터",
        "500": "한의학",
        "510": "항공",
        "520": "해양",
        "530": "화학",
        "1001": "나라 이름과 수도",
        "CYP": "사이퍼즈",
        "DGM": "디지몬",
        "DOT": "도타 2",
        "DRR": "듀라라라!!",
        "ELW": "엘소드",
        "ESB": "앙상블 스타즈!",
        "HAI": "하이큐!!",
        "HDC": "함대 컬렉션",
        "HOS": "히어로즈 오브 더 스톰",
        "HRH": "스즈미야 하루히",
        "HSS": "하스스톤",
        "HYK": "빙과",
        "IMS": "THE iDOLM@STER",
        "JAN": "만화/애니메이션",
        "JLN": "라이트 노벨",
        "KGR": "아지랑이 프로젝트",
        "KMV": "한국 영화",
        "KOT": "대한민국 철도역",
        "KPO": "유명인",
        "KRR": "개구리 중사 케로로",
        "KTV": "국내 방송 프로그램",
        "LOL": "리그 오브 레전드",
        "LVL": "러브 라이브!",
        "MAP": "메이플스토리",
        "MKK": "메카쿠시티 액터즈",
        "MMM": "마법소녀 마도카☆마기카",
        "MNG": "모노가타리 시리즈",
        "MOB": "모바일 게임",
        "MRN": "마법소녀 리리컬 나노하",
        "NEX": "온라인 게임",
        "NSK": "니세코이",
        "OIJ": "신조어",
        "OIM": "오레이모",
        "OVW": "오버워치",
        "POK": "포켓몬스터",
        "RAG": "라면/과자",
        "STA": "스타크래프트",
        "VOC": "VOCALOID",
        "WMV": "외국 영화",
        "WOW": "월드 오브 워크래프트",
        "YRY": "유루유리",
        "ZEL": "젤다의 전설",
        "e03": "★",
        "e05": "동물",
        "e08": "인체",
        "e12": "감정",
        "e13": "음식",
        "e15": "지명",
        "e18": "사람",
        "e20": "식물",
        "e43": "날씨",
    ]

    /// 단어 기록 한 칸에 들어갈 설명 조각. 품사는 배지, 분야는 〈〉, 표시는 분야가 없을 때 덧붙인다.
    public struct Description: Equatable, Sendable {
        public let classes: [String]
        public let themes: [String]
        public let marks: [String]
    }

    public static func describe(_ w: Word) -> Description {
        func names(_ codes: [String], _ table: [String: String]) -> [String] {
            var out: [String] = []
            for c in codes { if let n = table[c], !out.contains(n) { out.append(n) } }
            return out
        }
        var marks: [String] = []
        if w.flag & WordFlag.loanword != 0 { marks.append("외래어") }
        if w.flag & WordFlag.injeong != 0 { marks.append("어인정") }
        if w.flag & WordFlag.saturi != 0 { marks.append("방언") }
        if w.flag & WordFlag.old != 0 { marks.append("옛말") }
        if w.flag & WordFlag.munhwa != 0 { marks.append("북한말") }
        return Description(classes: names(w.types, classNames), themes: names(w.themes, themeNames), marks: marks)
    }

    /// 품사 → 분야·주제 → 표시 순으로 이어 붙인 것.
    public static func labels(_ w: Word) -> [String] {
        let d = describe(w)
        return d.classes + d.themes + d.marks
    }

    /// 끄투 processWord처럼 분야가 하나면 "〈포켓몬스터〉", 여럿이면 "1〈동방 프로젝트〉2〈영화〉".
    public static func themeLine(_ themes: [String]) -> String {
        if themes.count == 1 { return "〈\(themes[0])〉" }
        return themes.enumerated().map { "\($0.offset + 1)〈\($0.element)〉" }.joined()
    }
}
