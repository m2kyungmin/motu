import Foundation
import Testing
@testable import KkutuCore

@Suite struct WordIndexTests {
    let idx = fixtureIndex()

    @Test func parsesAllRows() {
        #expect(idx.count == 23)
        #expect(idx.lookup("라면")?.types == ["1", "14", "0"])
        #expect(idx.lookup("린스")?.flag == 1)
        #expect(idx.lookup("없는단어") == nil)
    }

    @Test func parseSkipsMalformedLines() {
        let i = WordIndex.parse(tsv: "사과\t1\t0\n깨진줄\n\n과자\t1\tx\n")
        #expect(i.count == 1)
    }

    @Test func parsesOptionalThemeColumn() {
        let i = WordIndex.parse(tsv: "사과\t1,1\t0\t270,320\n린스\t1\t1\t\n과자\t1\t0\n")
        #expect(i.lookup("사과")?.themes == ["270", "320"])
        #expect(i.lookup("린스")?.themes == [])
        #expect(i.lookup("과자")?.themes == [])      // 주제 열이 없던 옛 형식도 읽는다
    }

    @Test func labelsFollowKKuTuHistory() {
        // 품사는 중복 없이, 이름 없는 코드(0)·주제는 건너뛰고, 분야 다음에 표시.
        let w = Word(text: "가나", types: ["1", "1", "0"], flag: WordFlag.loanword | WordFlag.saturi, themes: ["270", "없음"])
        #expect(WordLabels.labels(w) == ["명", "식물", "외래어", "방언"])
        #expect(WordLabels.labels(Word(text: "다라", types: ["0"], flag: 0)) == [])
    }

    @Test func themeLineLikeKKuTu() {
        #expect(WordLabels.themeLine(["포켓몬스터"]) == "〈포켓몬스터〉")
        #expect(WordLabels.themeLine(["동방 프로젝트", "영화"]) == "1〈동방 프로젝트〉2〈영화〉")
        #expect(WordLabels.themeLine([]) == "")
        let d = WordLabels.describe(Word(text: "가나", types: ["1", "17"], flag: WordFlag.old, themes: ["STA"]))
        #expect(d == WordLabels.Description(classes: ["명", "명·부"], themes: ["스타크래프트"], marks: ["옛말"]))
    }

    @Test func korGroupFilter() {
        #expect(WordFilter.rejectionCode(idx.lookup("개굴개굴")!, options: RoomOptions()) == 404)   // type 6
        #expect(WordFilter.rejectionCode(idx.lookup("하다")!, options: RoomOptions()) == 404)       // type 5
        #expect(WordFilter.rejectionCode(idx.lookup("과히")!, options: RoomOptions()) == nil)       // type 8
    }

    @Test func injeongOption() {
        let w = idx.lookup("어인정단어")!
        #expect(WordFilter.rejectionCode(w, options: RoomOptions()) == 404)
        var o = RoomOptions(); o.injeong = true
        #expect(WordFilter.rejectionCode(w, options: o) == nil)
    }

    @Test func loanwordOption() {
        var o = RoomOptions(); o.noLoanword = true
        #expect(WordFilter.rejectionCode(idx.lookup("린스")!, options: o) == 405)
        #expect(WordFilter.rejectionCode(idx.lookup("린스")!, options: RoomOptions()) == nil)
    }

    @Test func strictOption() {
        var o = RoomOptions(); o.strict = true
        #expect(WordFilter.rejectionCode(idx.lookup("표고")!, options: o) == 406)   // flag 4
        #expect(WordFilter.rejectionCode(idx.lookup("과히")!, options: o) == 406)   // type 8 (1 아님)
        #expect(WordFilter.rejectionCode(idx.lookup("사과")!, options: o) == nil)   // type 1, flag 0
    }

    @Test func strictRejectsFlagAbove3() {
        var o = RoomOptions(); o.strict = true
        #expect(WordFilter.rejectionCode(idx.lookup("녀자")!, options: o) == 406)
    }

    @Test func candidatesUseSubChar() {
        let c = idx.candidates(first: "녀", sub: "여", options: RoomOptions()).map(\.text)
        #expect(c == ["녀자", "여자"])
        let only = idx.candidates(first: "녀", sub: nil, options: RoomOptions()).map(\.text)
        #expect(only == ["녀자"])
    }

    @Test func candidatesExcludeChainAndFiltered() {
        #expect(idx.candidates(first: "개", sub: nil, options: RoomOptions()).map(\.text) == ["개나리꽃"])
        #expect(idx.candidates(first: "사", sub: nil, options: RoomOptions(), excluding: ["사과"]).map(\.text) == ["사사"])
        #expect(idx.candidates(first: "간", sub: nil, options: RoomOptions()).isEmpty)
    }

    @Test func hasCandidateAndCount() {
        #expect(idx.hasCandidate(first: "과", sub: nil, options: RoomOptions()))
        #expect(!idx.hasCandidate(first: "간", sub: nil, options: RoomOptions()))
        #expect(idx.countCandidates(first: "과", sub: nil, options: RoomOptions(), excluding: [], upTo: 1) == 1)
        #expect(idx.countCandidates(first: "과", sub: nil, options: RoomOptions(), excluding: [], upTo: 10) == 2)
        var o = RoomOptions(); o.noLoanword = true
        #expect(idx.hasCandidate(first: "린", sub: "인", options: o))      // 인간이 있음
        #expect(!idx.hasCandidate(first: "린", sub: nil, options: o))     // 린스뿐인데 외래어 금지
    }

    @Test func randomWordByLength() {
        var rng: any RandomNumberGenerator = ZeroRNG()
        #expect(idx.randomWord(length: 3, rng: &rng)?.text == "자동차")      // 파일 순서상 첫 3글자 KOR_GROUP 단어
        #expect(idx.randomWord(length: 5, rng: &rng)?.text == "어인정단어")  // INJEONG은 KOR_GROUP에 포함
        #expect(idx.randomWord(length: 7, rng: &rng) == nil)
    }

    @Test func compoundNounsOnlyWhenOptionOn() {
        let i = WordIndex.parse(tsv: "도라지\t1\t0\n차\t1\t0\n치킨\t1\t1\n먹\t1\t0\n하다\t5\t0\n옛말\t1\t16\n")
        var o = RoomOptions()
        #expect(i.word("도라지차", options: o) == nil)                 // 꺼져 있으면 사전 그대로
        o.compound = true
        #expect(i.word("도라지차", options: o)?.types == ["1"])
        #expect(i.word("도라지", options: o)?.text == "도라지")          // 사전 단어는 그대로
        #expect(i.word("차차", options: o) == nil)                     // 두 글자는 복합어로 보지 않는다
        #expect(i.word("도라지하다", options: o) == nil)                // 명사끼리만
        #expect(i.word("도라지없음", options: o) == nil)
        #expect(i.word("치킨차", options: o)?.flag == WordFlag.loanword) // 외래어 표시는 이어받는다
        o.noLoanword = true
        #expect(i.word("치킨차", options: o) == nil)
        o.strict = true
        #expect(i.word("옛말차", options: o) == nil)                   // 부분도 옵션을 통과해야 한다
    }

    @Test func compoundKeyIsOptionalOnTheWire() throws {
        let old = try JSONDecoder().decode(RoomOptions.self, from: Data(#"{"manner":false,"injeong":false,"mission":false,"noLoanword":false,"strict":false}"#.utf8))
        #expect(old.compound == false)
    }
}
