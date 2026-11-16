import Testing
@testable import KkutuCore

@Suite struct BombRoundTests {
    @Test func chainsAndMovesTheCharacter() {
        var r = BombRound(start: "사", dictionary: fixtureIndex())
        #expect(r.submit("사과") == .accepted)
        #expect(r.char == "과")
        #expect(r.submit(" 과자 ") == .accepted)       // 앞뒤 공백은 지운다
        #expect(r.char == "자")
        #expect(r.chain == ["사과", "과자"])
    }

    @Test func rejectionsFollowKKuTu() {
        var r = BombRound(start: "사", dictionary: fixtureIndex())
        #expect(r.submit("사") == .notChainable)        // 한 글자
        #expect(r.submit("과자") == .notChainable)      // 첫 글자가 다름
        #expect(r.submit("사사사") == .rejected(code: 404))
        #expect(r.submit("사사") == .accepted)
        #expect(r.submit("사과") == .accepted)
        #expect(r.char == "과")
        var again = BombRound(start: "사", dictionary: fixtureIndex())
        _ = again.submit("사사")
        #expect(again.submit("사사") == .rejected(code: 409))   // 같은 판에서 다시 못 씀
    }

    @Test func dueumSubCharIsAccepted() {
        var r = BombRound(start: "녀", dictionary: fixtureIndex())
        #expect(r.subChar == "여")
        #expect(r.submit("여자") == .accepted)
    }

    @Test func optionsApply() {
        var o = RoomOptions(); o.noLoanword = true
        var r = BombRound(start: "린", dictionary: fixtureIndex(), options: o)
        #expect(r.submit("린스") == .rejected(code: 405))
    }

    @Test func randomStartHasEnoughFollowUps() {
        var rng: any RandomNumberGenerator = ZeroRNG()
        let c = BombRound.randomStart(dictionary: fixtureIndex(), minCandidates: 1, rng: &rng)
        #expect(fixtureIndex().hasCandidate(first: c, sub: Hangul.subChar(c), options: RoomOptions()))
    }
}
