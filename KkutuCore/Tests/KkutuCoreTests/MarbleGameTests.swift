import Testing
import Foundation
@testable import KkutuCore

@Suite struct MarbleGameTests {
    /// 픽스처 사전은 작아서 답 80개 문제가 없다. 기본값 "ㅅㄱ"(사과)로 떨어진다.
    func game(start: Int = 2, players: [PlayerID] = ["a", "b"]) -> MarbleGame {
        var rng: any RandomNumberGenerator = ZeroRNG()
        var s = MarbleSettings(); s.startBalls = start; s.seconds = 30
        return MarbleGame(players: players, settings: s, options: RoomOptions(), dictionary: fixtureIndex(), nowMs: 0, rng: &rng)
    }

    @Test func sharedPoolAndOwnBallRemoval() {
        var g = game()
        #expect(g.snapshot.prompt == .initials("ㅅㄱ"))
        #expect(g.submit("사과", from: "a", target: nil, nowMs: 100) == .accepted(.init(player: 0, word: "사과", target: 0)))
        #expect(g.submit("사과", from: "b", target: nil, nowMs: 200) == .rejected(code: 409))   // 남이 쓴 단어도 끝
        #expect(g.snapshot.counts == [1, 2])
    }

    @Test func floorAndCapDoNotSpendTheWord() {
        var g = game(start: 1)
        #expect(g.submit("사과", from: "a", target: "a", nowMs: 1) == .rejected(code: 431))      // 1개 밑으로 못 뺀다
        #expect(g.submit("사과", from: "a", target: "b", nowMs: 2) == .accepted(.init(player: 0, word: "사과", target: 1)))
        #expect(g.snapshot.counts == [1, 2])
        var full = game(start: 30)                                                               // 30 + 30 = 상한 60
        #expect(full.submit("사과", from: "a", target: "b", nowMs: 1) == .rejected(code: 432))
        #expect(full.submit("사과", from: "a", target: nil, nowMs: 1) == .accepted(.init(player: 0, word: "사과", target: 0)))
    }

    @Test func deadlineStrangersAndOffPrompt() {
        var g = game()
        #expect(g.submit("사과", from: "z", target: nil, nowMs: 1) == .rejected(code: 403))
        #expect(g.submit("과자", from: "a", target: nil, nowMs: 1) == .offPrompt)
        #expect(g.submit("사과", from: "a", target: nil, nowMs: 30_000) == .rejected(code: 433))
        #expect(g.remainingMs(nowMs: 29_000) == 1000)
    }

    @Test func raceOrderAndFinish() {
        var g = game(start: 2)
        _ = g.submit("사과", from: "a", target: "b", nowMs: 1)
        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        g.startRace(rng: &rng)
        #expect(g.snapshot.phase == .racing)
        #expect(g.snapshot.order?.sorted() == [0, 0, 1, 1, 1])
        #expect(g.submit("사사", from: "a", target: nil, nowMs: 2) == .rejected(code: 433))  // 경주 중엔 못 친다
        g.drawPenalty(among: 3, rng: &rng)
        #expect(g.snapshot.penalty == nil)                       // 끝나기 전엔 못 뽑는다
        g.finish(loser: 1)
        #expect(g.snapshot.phase == .done && g.snapshot.loser == 1)
        g.drawPenalty(among: 3, rng: &rng)
        let first = g.snapshot.penalty
        #expect(first.map { (0..<3).contains($0) } == true)
        g.drawPenalty(among: 3, rng: &rng)
        #expect(g.snapshot.penalty == first)                     // 한 번만 뽑는다
    }

    @Test func robotPicksUnusedAnswerAndSensibleTarget() {
        var g = game(start: 1)
        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        #expect(g.robotWord(rng: &rng) == "사과")
        #expect(g.robotTarget("a", rng: &rng) == "b")          // 1개라 못 빼니 남에게
        _ = g.submit("사과", from: "a", target: "b", nowMs: 1)
        #expect(g.robotWord(rng: &rng) == nil)
        #expect(g.robotTarget("b", rng: &rng) == "b")          // 2개라 자기 공을 뺀다
    }

    @Test func snapshotRoundTripsAndOldSettingsDecode() throws {
        let g = game()
        let data = try JSONEncoder().encode(g.snapshot)
        #expect(try JSONDecoder().decode(MarbleSnapshot.self, from: data) == g.snapshot)
        let old = #"{"rounds":5,"roundSeconds":60,"maxPlayers":8,"options":{"manner":false,"injeong":false,"mission":false,"noLoanword":false,"strict":false}}"#
        #expect(try JSONDecoder().decode(RoomSettings.self, from: Data(old.utf8)).marble == nil)
    }
}
