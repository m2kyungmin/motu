import Testing
import Foundation
@testable import KkutuCore

private func ctx(_ c: Character, turnTimeMs: Int = 10800, firstMove: Bool = true, manner: Bool = false, chain: [String] = [], done: Set<String> = [], options: RoomOptions = RoomOptions()) -> Robot.Context {
    Robot.Context(char: c, subChar: Hangul.subChar(c), turnTimeMs: turnTimeMs, firstMove: firstMove, manner: manner, chain: chain, done: done, options: options)
}

@Suite struct RobotChoiceTests {
    let dict = fixtureIndex()

    @Test func level0PicksFirstShortWordWithTypingDelay() {
        var rng: any RandomNumberGenerator = ZeroRNG()
        let r = Robot.choose(level: 0, context: ctx("사"), dict: dict, rng: &rng)
        #expect(r?.text == "사과")
        #expect(r?.delayMs == 1200 + 0 + 2 * 1250)           // START + 생각(0) + 글자수×TYPE
    }

    @Test func level0SkipsWordsOverLengthLimit() {
        var rng: any RandomNumberGenerator = ZeroRNG()
        #expect(Robot.choose(level: 0, context: ctx("개"), dict: dict, rng: &rng) == nil)       // 개나리꽃 4글자 > 3
        #expect(Robot.choose(level: 2, context: ctx("개"), dict: dict, rng: &rng)?.text == "개나리꽃")
    }

    @Test func givesUpWithoutCandidates() {
        var rng: any RandomNumberGenerator = ZeroRNG()
        #expect(Robot.choose(level: 4, context: ctx("간"), dict: dict, rng: &rng) == nil)
    }

    @Test func skipsAlreadyTriedWords() {
        var rng: any RandomNumberGenerator = ZeroRNG()
        #expect(Robot.choose(level: 1, context: ctx("사", done: ["사과"]), dict: dict, rng: &rng)?.text == "사사")
    }

    @Test func level4HasZeroDelayAndTargetsSmallestFollowGroup() {
        var rng: any RandomNumberGenerator = ZeroRNG()
        // 후보 [사과, 사사], 끝 글자 과→이을 단어 2개, 사→2개: 동률이면 먼저 나온 '과' 그룹 → 사과
        let r = Robot.choose(level: 4, context: ctx("사"), dict: dict, rng: &rng)
        #expect(r?.text == "사과")
        #expect(r?.delayMs == 0)
        // 첫 수가 아니고 매너가 아니면 이을 단어가 0개인 끝 글자(한방)를 노린다: 표→[표범(범:1), 표고(고:0)] → 표고
        let r2 = Robot.choose(level: 4, context: ctx("표", firstMove: false), dict: dict, rng: &rng)
        #expect(r2?.text == "표고")
        // 매너면 0개 그룹은 제외 → 표범
        let r3 = Robot.choose(level: 4, context: ctx("표", firstMove: false, manner: true), dict: dict, rng: &rng)
        #expect(r3?.text == "표범")
    }

    @Test func thinkDelayUsesAssumedHit() {
        struct MaxRNG: RandomNumberGenerator { mutating func next() -> UInt64 { 999 } }   // random ≈ 0.999
        var rng: any RandomNumberGenerator = MaxRNG()
        let r = Robot.choose(level: 1, context: ctx("사"), dict: dict, rng: &rng)
        let expected = 800.0 + 500 * 2 * 0.999 / log(1.1 + Robot.assumedHit) + 2 * 750
        #expect(abs(Double(r!.delayMs) - expected) < 1.0)
    }
}

@Suite struct RobotInEngineTests {
    @Test func robotSubmitsAtScheduledTime() {
        var s = RoomSettings(); s.rounds = 1
        let e = GameEngine(settings: s, dictionary: fixtureIndex(), rng: ZeroRNG(), titleOverride: "사사")
        let human = Player(id: "H", name: "사람")
        let robot = Player(id: "R", name: "로봇", robotLevel: 4)
        _ = e.handle(.start(players: [robot, human]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        let r0 = e.handle(.deadline, nowMs: 4400)                           // 로봇 턴 시작, 레벨 4 → 지연 0
        #expect(r0.nextDeadlineMs == 4400)
        let r1 = e.handle(.deadline, nowMs: 4400)
        #expect(r1.events == [.turnEnd(player: "R", ok: true, value: "사과", score: 18, bonus: 0, hint: nil)])
        #expect(r1.nextDeadlineMs == 4400 + 1800)
    }

    @Test func slowRobotTimesOut() {
        var s = RoomSettings(); s.rounds = 1; s.roundSeconds = 10
        let e = GameEngine(settings: s, dictionary: fixtureIndex(), rng: ZeroRNG(), titleOverride: "개개")   // 개 → 개나리꽃(4글자)만
        let robot = Player(id: "R", name: "로봇", robotLevel: 0)                  // 길이 제한 3 → 포기
        _ = e.handle(.start(players: [robot, Player(id: "H", name: "사람")]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        let r0 = e.handle(.deadline, nowMs: 4400)
        #expect(r0.nextDeadlineMs == 4400 + 2500)                            // 로봇 예약 없음 → 턴 마감만
        let r1 = e.handle(.deadline, nowMs: 4400 + 2500)
        if case .turnEnd(let p, let ok, _, _, _, _) = r1.events[0] { #expect(p == "R" && !ok) } else { Issue.record("시간 초과여야 함") }
    }

    @Test func robotRetriesAfterRejection() {
        var s = RoomSettings(); s.rounds = 1
        // '인'의 후보는 인간뿐이고 인간은 한방(간으로 시작하는 단어 없음) → 첫 수라 402 → 다시 고를 단어가 없어 포기
        let e = GameEngine(settings: s, dictionary: fixtureIndex(), rng: ZeroRNG(), titleOverride: "인인")
        let robot = Player(id: "R", name: "로봇", robotLevel: 2)
        _ = e.handle(.start(players: [robot, Player(id: "H", name: "사람")]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        let r0 = e.handle(.deadline, nowMs: 4400)                            // 로봇 턴: 인간 예약
        #expect(r0.nextDeadlineMs == 4400 + 400 + 0 + 2 * 500)               // START 400 + 생각 0 + 2글자×500
        let fire = e.handle(.deadline, nowMs: 5800)
        #expect(fire.events == [.turnError(player: "R", code: 402, value: "인간")])
        #expect(fire.nextDeadlineMs == 4400 + 10900)                         // 다른 후보 없음 → 턴 마감만 남음
    }
}
