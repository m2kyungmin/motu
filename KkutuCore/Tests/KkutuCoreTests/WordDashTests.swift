import Testing
@testable import KkutuCore

@Suite struct WordDashTests {
    @Test func initialsOfWords() {
        #expect(Hangul.choseong("사") == "ㅅ")
        #expect(Hangul.choseong("까") == "ㄲ")
        #expect(Hangul.choseong("a") == nil)
        #expect(Hangul.initials("자동차") == "ㅈㄷㅊ")
        #expect(Hangul.initials("사a") == nil)
    }

    @Test func initialsPromptNeedsExactPattern() {
        var d = WordDash(prompt: .initials("ㅅㄱ"), dictionary: fixtureIndex())
        #expect(d.submit("사과") == .accepted)
        #expect(d.submit("사과") == .rejected(code: 409))
        #expect(d.submit("사구") == .rejected(code: 404))     // 초성은 맞지만 사전에 없다
        #expect(d.submit("과자") == .offPrompt)
        #expect(d.submit("사과나") == .offPrompt)             // 길이가 다르다
        #expect(d.submit("싸과") == .offPrompt)               // ㅆ은 ㅅ이 아니다
        #expect(d.words == ["사과"])
    }

    @Test func startsPromptAcceptsDueum() {
        var d = WordDash(prompt: .starts("녀"), dictionary: fixtureIndex())
        #expect(d.submit("녀") == .offPrompt)                 // 한 글자
        #expect(d.submit("여자") == .accepted)                // 두음법칙
        var o = RoomOptions(); o.noLoanword = true
        var r = WordDash(prompt: .starts("린"), dictionary: fixtureIndex(), options: o)
        #expect(r.submit("린스") == .rejected(code: 405))
    }

    @Test func indexFindsByInitials() {
        let found = fixtureIndex().words(initials: "ㄱㄱ", options: RoomOptions(), limit: 10).map(\.text)
        #expect(Set(found) == ["가가", "가게"])
        #expect(fixtureIndex().words(initials: "ㄱㄱ", options: RoomOptions(), limit: 1).count == 1)
    }

    @Test func randomPromptHasAnswers() {
        var rng: any RandomNumberGenerator = ZeroRNG()
        let p = WordDash.randomPrompt(.initials, dictionary: fixtureIndex(), minAnswers: 1, rng: &rng)
        guard case .initials(let i) = p else { Issue.record("초성 문제가 아님"); return }
        #expect(!fixtureIndex().words(initials: i, options: RoomOptions(), limit: 1).isEmpty)
        let s = WordDash.randomPrompt(.starts, dictionary: fixtureIndex(), minAnswers: 1, avoiding: [], rng: &rng)
        guard case .starts(let t) = s, let c = t.first else { Issue.record("시작 글자 문제가 아님"); return }
        #expect(fixtureIndex().hasCandidate(first: c, sub: Hangul.subChar(c), options: RoomOptions()))
    }

    @Test func ledgerKeepsOneAndCaps() {
        var l = BallLedger(players: 2, start: 2, cap: 5)
        let removed = l.remove(0), removedAgain = l.remove(0)
        #expect(removed && !removedAgain)                     // 1개 밑으로는 못 뺀다
        let a = l.add(1), b = l.add(1), c = l.add(0)          // 1 + 4 = 5, 그다음은 전체 상한
        #expect(a && b && !c)
        #expect(l.counts == [1, 4])
        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        let balls = l.shuffledBalls(rng: &rng)
        #expect(balls.filter { $0 == 1 }.count == 4 && balls.count == 5)
    }
}
