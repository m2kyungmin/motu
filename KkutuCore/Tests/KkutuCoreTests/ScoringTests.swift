import Testing
@testable import KkutuCore

@Suite struct ScoringTests {
    @Test func preScoreMatchesKKuTu() {
        #expect(abs(Scoring.preScore(length: 2, chainCount: 0, tr: 1.0) - 17.672893501682115) < 1e-9)
        #expect(abs(Scoring.preScore(length: 2, chainCount: 0, tr: 0.5) - 13.254670126261587) < 1e-9)
        #expect(abs(Scoring.preScore(length: 3, chainCount: 4, tr: 1.0) - 29.330010505236334) < 1e-9)
        #expect(abs(Scoring.preScore(length: 5, chainCount: 10, tr: 0.0) - 24.12937306427178) < 1e-9)
    }

    @Test func penaltyMatchesKKuTu() {
        #expect(Scoring.penalty(chainCount: 0, score: 0) == 0)
        #expect(Scoring.penalty(chainCount: 0, score: 5) == -5)
        #expect(Scoring.penalty(chainCount: 3, score: 100) == -31)
        #expect(Scoring.penalty(chainCount: 10, score: 500) == -106)
        #expect(Scoring.penalty(chainCount: 2, score: 17) == -17)
    }

    @Test func turnSpeedBoundaries() {
        let cases: [(Int, Int)] = [(4999, 10), (5000, 9), (10999, 9), (11000, 8), (17999, 8), (18000, 7), (25999, 7), (26000, 6),
                                   (34999, 6), (35000, 5), (44999, 5), (45000, 4), (55999, 4), (56000, 3), (67999, 3), (68000, 2),
                                   (80999, 2), (81000, 1), (94999, 1), (95000, 0), (150000, 0)]
        for (rt, s) in cases { #expect(Scoring.turnSpeed(roundTimeMs: rt) == s, "rt=\(rt)") }
    }

    @Test func turnTime() {
        #expect(Scoring.turnTimeMs(speed: 0) == 15000)
        #expect(Scoring.turnTimeMs(speed: 3) == 10800)
        #expect(Scoring.turnTimeMs(speed: 10) == 1000)
    }

    @Test func missionChars() {
        #expect(Scoring.missionChars.count == 14)
        #expect(Scoring.missionChars.first == "가" && Scoring.missionChars.last == "하")
    }
}
