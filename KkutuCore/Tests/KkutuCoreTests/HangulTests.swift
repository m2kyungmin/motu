import Testing
@testable import KkutuCore

@Suite struct HangulTests {
    @Test("ㄹ+ㅏㅐㅗㅚㅜㅡ → ㄴ", arguments: [("라","나"),("래","내"),("로","노"),("뢰","뇌"),("루","누"),("르","느"),("름","늠"),("락","낙")])
    func rieulToNieun(pair: (String, String)) {
        #expect(Hangul.subChar(Character(pair.0)) == Character(pair.1))
    }

    @Test("ㄹ+ㅑㅕㅖㅛㅠㅣ → ㅇ", arguments: [("량","양"),("려","여"),("례","예"),("료","요"),("류","유"),("리","이"),("력","역")])
    func rieulToIeung(pair: (String, String)) {
        #expect(Hangul.subChar(Character(pair.0)) == Character(pair.1))
    }

    @Test("ㄴ+ㅕㅛㅠㅣ → ㅇ", arguments: [("녀","여"),("뇨","요"),("뉴","유"),("니","이")])
    func nieunToIeung(pair: (String, String)) {
        #expect(Hangul.subChar(Character(pair.0)) == Character(pair.1))
    }

    @Test("변환 없음", arguments: ["가", "나", "노", "늠", "레", "렐", "ㄹ", "a", "1", "😀"])
    func noSub(s: String) {
        #expect(Hangul.subChar(Character(s)) == nil)
    }

    @Test func nonHangulReturnsNil() {
        #expect(Hangul.subChar("x") == nil)
        #expect(Hangul.subChar("\u{AC00}") == nil)   // 가
        #expect(Hangul.subChar("\u{D7A3}") == nil)   // 힣
    }
}
