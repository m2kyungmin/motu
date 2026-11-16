/// 끄투 classic.js getSubChar의 두음법칙 이식.
/// 중성 인덱스(0xAC00 분해 기준): ㅏ0 ㅐ1 ㅑ2 ㅕ6 ㅖ7 ㅗ8 ㅚ11 ㅛ12 ㅜ13 ㅠ17 ㅡ18 ㅣ20
/// 초성 인덱스: ㄴ2 ㄹ5 ㅇ11
public enum Hangul {
    private static let rieulToNieun: Set<Int> = [0, 1, 8, 11, 13, 18]
    private static let rieulToIeung: Set<Int> = [2, 6, 7, 12, 17, 20]
    private static let nieunToIeung: Set<Int> = [6, 12, 17, 20]

    public static func subChar(_ c: Character) -> Character? {
        guard c.unicodeScalars.count == 1, let s = c.unicodeScalars.first else { return nil }
        let k = Int(s.value) - 0xAC00
        guard k >= 0, k <= 11171 else { return nil }
        let cho = k / 28 / 21, jung = (k / 28) % 21, jong = k % 28
        let newCho: Int
        switch cho {
        case 5:
            if rieulToNieun.contains(jung) { newCho = 2 }
            else if rieulToIeung.contains(jung) { newCho = 11 }
            else { return nil }
        case 2:
            guard nieunToIeung.contains(jung) else { return nil }
            newCho = 11
        default:
            return nil
        }
        guard let scalar = UnicodeScalar(0xAC00 + (newCho * 21 + jung) * 28 + jong) else { return nil }
        return Character(scalar)
    }

    /// 호환 자모 초성 19개, 0xAC00 분해의 초성 인덱스 순서.
    public static let choseongs: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")

    /// 완성형 한 글자의 초성. 한글 음절이 아니면 nil.
    public static func choseong(_ c: Character) -> Character? {
        guard c.unicodeScalars.count == 1, let s = c.unicodeScalars.first else { return nil }
        let k = Int(s.value) - 0xAC00
        guard k >= 0, k <= 11171 else { return nil }
        return choseongs[k / 28 / 21]
    }

    /// 낱말의 초성 줄. 한 글자라도 한글 음절이 아니면 nil.
    public static func initials(_ text: String) -> String? {
        var out = ""
        for c in text {
            guard let i = choseong(c) else { return nil }
            out.append(i)
        }
        return out
    }
}
