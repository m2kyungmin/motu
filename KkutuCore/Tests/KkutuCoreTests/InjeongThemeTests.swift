import Foundation
import Testing
@testable import KkutuCore

/// 어인정 주제 고르기. 공유 픽스처 대신 주제 열이 있는 작은 사전을 쓴다.
@Suite struct InjeongThemeTests {
    // 파일 순서상 포켓몬 단어가 먼저라, 거르지 않으면 로봇·힌트가 그것부터 집는다.
    let idx = WordIndex.parse(tsv: """
    가라오\tINJEONG\t2\tPOK
    가나다\tINJEONG\t2\tKPO
    가마솥\t1\t0
    가에서\t1,INJEONG\t1\t430,1001
    """)

    func options(_ themes: Set<String>?) -> RoomOptions {
        var o = RoomOptions(); o.injeong = true; o.injeongThemes = themes
        return o
    }

    @Test func pickedThemeOnly() {
        let o = options(["KPO"])
        #expect(WordFilter.rejectionCode(idx.lookup("가나다")!, options: o) == nil)
        #expect(WordFilter.rejectionCode(idx.lookup("가라오")!, options: o) == 404)
        #expect(WordFilter.rejectionCode(idx.lookup("가마솥")!, options: o) == nil)      // 일반 단어는 상관없다
        #expect(WordFilter.rejectionCode(idx.lookup("가에서")!, options: o) == nil)      // INJEONG 품사여도 어인정 표시가 없으면 일반 단어
    }

    @Test func nilMeansEveryTheme() {
        #expect(WordFilter.rejectionCode(idx.lookup("가라오")!, options: options(nil)) == nil)
        #expect(WordFilter.rejectionCode(idx.lookup("가나다")!, options: options(nil)) == nil)
    }

    @Test func emptyPickRejectsEveryInjeongWord() {
        #expect(WordFilter.rejectionCode(idx.lookup("가나다")!, options: options([])) == 404)
        #expect(WordFilter.rejectionCode(idx.lookup("가마솥")!, options: options([])) == nil)
    }

    @Test func themesIgnoredWhenInjeongOff() {
        var o = options(["KPO"]); o.injeong = false
        #expect(WordFilter.rejectionCode(idx.lookup("가나다")!, options: o) == 404)
    }

    @Test func candidatesAndRobotFollowPick() {
        let o = options(["KPO"])
        #expect(idx.candidates(first: "가", sub: nil, options: o).map(\.text) == ["가나다", "가마솥", "가에서"])
        var rng: any RandomNumberGenerator = ZeroRNG()
        let ctx = Robot.Context(char: "가", subChar: nil, turnTimeMs: 10_000, firstMove: false, manner: false, chain: [], done: [], options: o)
        #expect(Robot.choose(level: 0, context: ctx, dict: idx, rng: &rng)?.text == "가나다")
    }

    @Test func build3SettingsStillDecode() throws {
        // 빌드 2·3이 보내는 방 설정에는 주제 키가 없다.
        let json = #"{"rounds":5,"roundSeconds":60,"maxPlayers":8,"options":{"manner":false,"injeong":true,"mission":false,"noLoanword":false,"strict":false}}"#
        let s = try JSONDecoder().decode(RoomSettings.self, from: Data(json.utf8))
        #expect(s.options.injeongThemes == nil)
        #expect(WordFilter.rejectionCode(idx.lookup("가라오")!, options: s.options) == nil)

        var picked = s; picked.options.injeongThemes = ["KPO", "POK"]
        let back = try JSONDecoder().decode(RoomSettings.self, from: JSONEncoder().encode(picked))
        #expect(back == picked)
    }

    @Test func pickListLikeKKuTu() {
        let list = WordFilter.injeongThemes
        #expect(list.count == 40)
        #expect(list.first == "1001")                 // 끄투 주제 선택 창 순서: KO_THEME 다음 KO_INJEONG
        #expect(!list.contains("OIJ"))                // IJP_EXCEPT
        #expect(Set(list).count == list.count)
        #expect(list.allSatisfy { WordLabels.themeNames[$0] != nil })
    }
}
