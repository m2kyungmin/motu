import Foundation
import Testing
@testable import KkutuCore

/// 시나리오 공통: 라운드 2, 60초, 플레이어 A·B, 제목 "사과" (라운드1 '사', 라운드2 '과')
private func makeEngine(title: String = "사과", rounds: Int = 2, seconds: Int = 60, options: RoomOptions = RoomOptions(), dict: WordIndex = fixtureIndex()) -> GameEngine {
    var s = RoomSettings(); s.rounds = rounds; s.roundSeconds = seconds; s.options = options
    return GameEngine(settings: s, dictionary: dict, rng: ZeroRNG(), titleOverride: title)
}
private let A = Player(id: "A", name: "에이")
private let B = Player(id: "B", name: "비")

@Suite struct GameEngineFlowTests {
    @Test func startThenRoundReadyThenTurnStart() {
        let e = makeEngine()
        var r = e.handle(.start(players: [A, B]), nowMs: 0)
        #expect(r.events == [.starting(title: "사과")])
        #expect(r.nextDeadlineMs == 2000)

        r = e.handle(.deadline, nowMs: 2000)
        #expect(r.events == [.roundReady(round: 1, char: "사", subChar: nil, mission: nil)])
        #expect(r.nextDeadlineMs == 4400)

        r = e.handle(.deadline, nowMs: 4400)
        #expect(r.events == [.turnStart(turn: 0, player: "A", char: "사", subChar: nil, speed: 3, roundTimeMs: 60000, turnTimeMs: 10800, mission: nil)])
        #expect(r.nextDeadlineMs == 4400 + 10900)
        #expect(e.snapshot.phase == .turn)
    }

    @Test func approvedSubmitScoresAndAdvancesTurn() {
        let e = makeEngine()
        _ = e.handle(.start(players: [A, B]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        _ = e.handle(.deadline, nowMs: 4400)

        var r = e.handle(.submit(player: "A", text: "사과"), nowMs: 5400)   // 1000ms 걸림
        #expect(r.events == [.turnEnd(player: "A", ok: true, value: "사과", score: 17, bonus: 0, hint: nil)])
        #expect(r.nextDeadlineMs == 5400 + 1800)                         // turnTime/6
        #expect(e.snapshot.scores["A"] == 17)
        #expect(e.snapshot.chain == ["사과"])
        #expect(e.snapshot.char == "과")
        #expect(e.snapshot.roundTimeMs == 59000)

        r = e.handle(.deadline, nowMs: 7200)
        #expect(r.events == [.turnStart(turn: 1, player: "B", char: "과", subChar: nil, speed: 3, roundTimeMs: 59000, turnTimeMs: 10800, mission: nil)])

        r = e.handle(.submit(player: "B", text: "과자"), nowMs: 7700)      // 500ms, chain 1
        #expect(r.events == [.turnEnd(player: "B", ok: true, value: "과자", score: 19, bonus: 0, hint: nil)])
        #expect(e.snapshot.char == "자")
    }

    @Test func timeoutPenalizesAndStartsNextRoundWithSamePlayer() {
        let e = makeEngine()
        _ = e.handle(.start(players: [A, B]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        _ = e.handle(.deadline, nowMs: 4400)
        _ = e.handle(.submit(player: "A", text: "사과"), nowMs: 5400)
        _ = e.handle(.deadline, nowMs: 7200)                              // B 턴 시작
        _ = e.handle(.submit(player: "B", text: "과자"), nowMs: 7700)
        let r0 = e.handle(.deadline, nowMs: 9500)                         // A 턴 시작, 글자 '자'
        #expect(r0.nextDeadlineMs == 9500 + 10900)

        var r = e.handle(.deadline, nowMs: 20400)                          // A 시간 초과
        #expect(r.events == [.turnEnd(player: "A", ok: false, value: nil, score: -17, bonus: 0, hint: "자동차")])
        #expect(e.snapshot.scores["A"] == 0)
        #expect(r.nextDeadlineMs == 23400)

        r = e.handle(.deadline, nowMs: 23400)
        #expect(r.events == [.roundReady(round: 2, char: "과", subChar: nil, mission: nil)])
        #expect(e.snapshot.chain.isEmpty)
        r = e.handle(.deadline, nowMs: 25800)
        if case .turnStart(let turn, let player, _, _, _, _, _, _) = r.events[0] {
            #expect(turn == 0 && player == "A")                           // 시간 초과한 사람이 다음 라운드 첫 턴
        } else { Issue.record("turnStart 아님") }
    }

    @Test func gameEndsAfterLastRoundWithRanking() {
        let e = makeEngine(rounds: 1)
        _ = e.handle(.start(players: [A, B]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        _ = e.handle(.deadline, nowMs: 4400)
        _ = e.handle(.submit(player: "A", text: "사과"), nowMs: 4400)      // 18점
        _ = e.handle(.deadline, nowMs: 6200)                              // B 턴
        _ = e.handle(.deadline, nowMs: 6200 + 10900)                      // B 시간 초과 (0점 → 패널티 0)
        let r = e.handle(.deadline, nowMs: 6200 + 10900 + 3000)
        #expect(r.events == [.gameEnd(ranking: [ScoreEntry(player: "A", score: 18, rank: 1), ScoreEntry(player: "B", score: 0, rank: 2)])])
        #expect(r.nextDeadlineMs == nil)
        #expect(e.snapshot.phase == .ended)
    }

    @Test func tiedScoresShareRank() {
        let e = makeEngine(rounds: 1)
        _ = e.handle(.start(players: [A, B]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        _ = e.handle(.deadline, nowMs: 4400)
        _ = e.handle(.deadline, nowMs: 4400 + 10900)                      // A 시간 초과, 0점
        let r = e.handle(.deadline, nowMs: 4400 + 10900 + 3000)
        #expect(r.events == [.gameEnd(ranking: [ScoreEntry(player: "A", score: 0, rank: 1), ScoreEntry(player: "B", score: 0, rank: 1)])])
    }
}

@Suite struct GameEngineRejectionTests {
    private func atFirstTurn(title: String = "사과", options: RoomOptions = RoomOptions()) -> GameEngine {
        let e = makeEngine(title: title, options: options)
        _ = e.handle(.start(players: [A, B]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        _ = e.handle(.deadline, nowMs: 4400)
        return e
    }

    @Test func duplicateWordIs409() {
        let e = atFirstTurn(title: "사사")
        _ = e.handle(.submit(player: "A", text: "사사"), nowMs: 4400)
        _ = e.handle(.deadline, nowMs: 6200)
        let r = e.handle(.submit(player: "B", text: "사사"), nowMs: 6300)
        #expect(r.events == [.turnError(player: "B", code: 409, value: "사사")])
        #expect(e.snapshot.phase == .turn)
        #expect(r.nextDeadlineMs == 6200 + 10900)                         // 마감 유지
    }

    @Test func unknownWordIs404() {
        let e = atFirstTurn()
        #expect(e.handle(.submit(player: "A", text: "사람들"), nowMs: 4500).events == [.turnError(player: "A", code: 404, value: "사람들")])
    }

    @Test func strictIs406() {
        var o = RoomOptions(); o.strict = true
        let e = atFirstTurn(title: "표린", options: o)
        #expect(e.handle(.submit(player: "A", text: "표고"), nowMs: 4500).events == [.turnError(player: "A", code: 406, value: "표고")])
    }

    @Test func loanwordIs405() {
        var o = RoomOptions(); o.noLoanword = true
        let e = atFirstTurn(title: "린스", options: o)          // 라운드1 글자 '린', 보조 '인'
        #expect(e.handle(.submit(player: "A", text: "린스"), nowMs: 4500).events == [.turnError(player: "A", code: 405, value: "린스")])
    }

    @Test func firstMoveOneShotIs402() {
        let e = atFirstTurn(title: "인간")
        #expect(e.handle(.submit(player: "A", text: "인간"), nowMs: 4500).events == [.turnError(player: "A", code: 402, value: "인간")])
    }

    @Test func mannerOneShotIs403() {
        var o = RoomOptions(); o.manner = true
        let e = atFirstTurn(title: "표범", options: o)
        _ = e.handle(.submit(player: "A", text: "표범"), nowMs: 4400)
        _ = e.handle(.deadline, nowMs: 6200)
        _ = e.handle(.submit(player: "B", text: "범인"), nowMs: 6200)
        _ = e.handle(.deadline, nowMs: 8000)
        #expect(e.handle(.submit(player: "A", text: "인간"), nowMs: 8000).events == [.turnError(player: "A", code: 403, value: "인간")])
    }

    @Test func withoutMannerOneShotIsAllowedAfterFirstMove() {
        let e = atFirstTurn(title: "표범")
        _ = e.handle(.submit(player: "A", text: "표범"), nowMs: 4400)
        _ = e.handle(.deadline, nowMs: 6200)
        _ = e.handle(.submit(player: "B", text: "범인"), nowMs: 6200)
        _ = e.handle(.deadline, nowMs: 8000)
        if case .turnEnd(_, let ok, _, _, _, _) = e.handle(.submit(player: "A", text: "인간"), nowMs: 8000).events[0] { #expect(ok) }
        else { Issue.record("승인돼야 함") }
    }

    @Test("ignores submit out of turn") func ignoresSubmitOutOfTurn() {
        let e = atFirstTurn()
        let before = e.snapshot
        #expect(e.handle(.submit(player: "B", text: "사과"), nowMs: 4500).events.isEmpty)
        #expect(e.handle(.submit(player: "없음", text: "사과"), nowMs: 4500).events.isEmpty)
        #expect(e.snapshot == before)
        let idle = makeEngine()
        #expect(idle.handle(.submit(player: "A", text: "사과"), nowMs: 0).events.isEmpty)
    }

    @Test("ignores unchainable") func ignoresUnchainable() {
        let e = atFirstTurn()
        #expect(e.handle(.submit(player: "A", text: "apple"), nowMs: 4500).events.isEmpty)
        #expect(e.handle(.submit(player: "A", text: "과자"), nowMs: 4500).events.isEmpty)
        #expect(e.handle(.submit(player: "A", text: "사"), nowMs: 4500).events.isEmpty)
        #expect(e.handle(.submit(player: "A", text: ""), nowMs: 4500).events.isEmpty)
    }

    @Test("trims whitespace") func trimsWhitespace() {
        let e = atFirstTurn()
        if case .turnEnd(_, let ok, let value, _, _, _) = e.handle(.submit(player: "A", text: " 사과\n"), nowMs: 4500).events[0] {
            #expect(ok && value == "사과")
        } else { Issue.record("승인돼야 함") }
    }
}

@Suite struct GameEngineRuleDetailTests {
    @Test func subCharIsAccepted() {
        let e = makeEngine(title: "녀자")
        _ = e.handle(.start(players: [A, B]), nowMs: 0)
        let r = e.handle(.deadline, nowMs: 2000)
        #expect(r.events == [.roundReady(round: 1, char: "녀", subChar: "여", mission: nil)])
        _ = e.handle(.deadline, nowMs: 4400)
        if case .turnEnd(_, let ok, let value, _, _, _) = e.handle(.submit(player: "A", text: "여자"), nowMs: 4400).events[0] {
            #expect(ok && value == "여자")
        } else { Issue.record("두음 보조 글자로 시작한 단어는 승인") }
    }

    @Test func missionBonusAndReroll() {
        var o = RoomOptions(); o.mission = true
        let e = makeEngine(title: "가가", options: o)
        _ = e.handle(.start(players: [A, B]), nowMs: 0)
        let r0 = e.handle(.deadline, nowMs: 2000)
        #expect(r0.events == [.roundReady(round: 1, char: "가", subChar: nil, mission: "가")])   // ZeroRNG → 첫 미션 글자
        _ = e.handle(.deadline, nowMs: 4400)
        let r = e.handle(.submit(player: "A", text: "가가"), nowMs: 4400)
        #expect(r.events == [.turnEnd(player: "A", ok: true, value: "가가", score: 35, bonus: 17, hint: nil)])   // 18 기본 + 가 2회 → ×2
        #expect(e.snapshot.mission == "가")                                                   // 새 미션(ZeroRNG라 또 '가')
    }

    @Test func repeatedWordDecaysAcrossRounds() {
        let e = makeEngine(title: "사사", rounds: 2)
        _ = e.handle(.start(players: [A, B]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        _ = e.handle(.deadline, nowMs: 4400)
        _ = e.handle(.submit(player: "A", text: "사사"), nowMs: 4400)      // 18
        _ = e.handle(.deadline, nowMs: 6200)                              // B 턴, 글자 '사'
        _ = e.handle(.submit(player: "B", text: "사과"), nowMs: 6200)
        _ = e.handle(.deadline, nowMs: 8000)                              // A 턴, 글자 '과'
        _ = e.handle(.deadline, nowMs: 8000 + 10900)                      // A 시간 초과
        _ = e.handle(.deadline, nowMs: 8000 + 10900 + 3000)               // 라운드 2, 글자 '사'
        _ = e.handle(.deadline, nowMs: 8000 + 10900 + 3000 + 2400)        // A 턴
        let r = e.handle(.submit(player: "A", text: "사사"), nowMs: 8000 + 10900 + 3000 + 2400)
        #expect(r.events == [.turnEnd(player: "A", ok: true, value: "사사", score: 17, bonus: 0, hint: nil)])  // 18 × 15/16 → 17
    }

    @Test("deadline clipped by round time") func deadlineClippedByRoundTime() {
        let e = makeEngine(title: "사과", rounds: 1, seconds: 10)
        _ = e.handle(.start(players: [A, B]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        var now = 4400
        var r = e.handle(.deadline, nowMs: now)
        #expect(r.events == [.turnStart(turn: 0, player: "A", char: "사", subChar: nil, speed: 9, roundTimeMs: 10000, turnTimeMs: 2400, mission: nil)])
        #expect(r.nextDeadlineMs == now + 2500)
        // 남은 라운드 시간: 10000 → 7700 → 5400 → 3100 → 2200 → 1300 → 400 (3100부터는 speed 10, turnTime 1000)
        let moves: [(PlayerID, String, Int)] = [("A", "사과", 2300), ("B", "과자", 2300), ("A", "자동차", 2300), ("B", "차표", 900), ("A", "표범", 900), ("B", "범인", 900)]
        for (pid, word, delay) in moves {
            now += delay
            r = e.handle(.submit(player: pid, text: word), nowMs: now)
            guard case .turnEnd(_, let ok, _, _, _, _) = r.events.first, ok else { Issue.record("\(word) 승인돼야 함: \(r.events)"); return }
            now = r.nextDeadlineMs!
            r = e.handle(.deadline, nowMs: now)             // 다음 사람 turnStart
        }
        if case .turnStart(_, let player, _, _, let speed, let roundTimeMs, let turnTimeMs, _) = r.events[0] {
            #expect(player == "A" && roundTimeMs == 400 && speed == 10 && turnTimeMs == 1000)
            #expect(r.nextDeadlineMs == now + 400)          // min(roundTime 400, turnTime+100)
        } else { Issue.record("turnStart 아님") }
    }

    @Test("title falls back") func titleFallsBack() {
        let tiny = WordIndex.parse(tsv: "가나\t1\t0\n")
        var s = RoomSettings(); s.rounds = 3
        let e = GameEngine(settings: s, dictionary: tiny, rng: ZeroRNG())
        #expect(e.handle(.start(players: [A, B]), nowMs: 0).events == [.starting(title: "가나다라마바사아자차")])
    }

    @Test func generatedTitleHasFollowableChars() {
        var s = RoomSettings(); s.rounds = 2
        let e = GameEngine(settings: s, dictionary: fixtureIndex(), rng: SystemRandomNumberGenerator())
        guard case .starting(let title) = e.handle(.start(players: [A, B]), nowMs: 0).events[0] else { Issue.record("starting 아님"); return }
        #expect(title.count == 2)
        for c in title { #expect(fixtureIndex().hasCandidate(first: c, sub: Hangul.subChar(c), options: RoomOptions()), "\(c)") }
    }

    @Test func currentPlayerLeavingStartsNextTurn() {
        let e = makeEngine()
        let C = Player(id: "C", name: "씨")
        _ = e.handle(.start(players: [A, B, C]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        _ = e.handle(.deadline, nowMs: 4400)                              // A 턴
        let r = e.handle(.playerLeft("A"), nowMs: 5000)
        if case .turnStart(let turn, let player, _, _, _, _, _, _) = r.events[0] { #expect(turn == 0 && player == "B") }
        else { Issue.record("B 턴이 바로 시작돼야 함") }
        #expect(e.snapshot.seats.map(\.id) == ["B", "C"])
    }

    @Test func lastHumanLeavingEndsGame() {
        let e = makeEngine()
        _ = e.handle(.start(players: [A, B]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        let r = e.handle(.playerLeft("B"), nowMs: 2500)
        if case .gameEnd(let ranking) = r.events[0] { #expect(ranking.map(\.player) == ["A"]) }
        else { Issue.record("gameEnd여야 함") }
        #expect(r.nextDeadlineMs == nil)
    }
}

/// 화면이 제출 전에 같은 규칙으로 흔들기 여부를 판단한다(스펙 §5.3-1).
@Suite struct ChainableRuleTests {
    @Test func publicIsChainableMatchesEngineRule() {
        #expect(GameEngine.isChainable("사과", char: "사", subChar: nil))
        #expect(GameEngine.isChainable("여자", char: "녀", subChar: "여"))
        #expect(!GameEngine.isChainable("과자", char: "사", subChar: nil))
        #expect(!GameEngine.isChainable("사", char: "사", subChar: nil))
        #expect(!GameEngine.isChainable("", char: "사", subChar: nil))
        #expect(!GameEngine.isChainable("apple", char: "사", subChar: nil))
    }
}

/// 방장 승계: 다른 기기가 가진 마지막 스냅샷으로 엔진을 되살려 이어 간다.
@Suite struct HostMigrationTests {
    private let C = Player(id: "C", name: "씨")
    private func settings() -> RoomSettings { var s = RoomSettings(); s.rounds = 2; s.roundSeconds = 60; return s }
    /// A·B·C 시작 → A가 "사과" → (다음 단계 예약 상태, 스냅샷은 .turnResult)
    private func afterASubmits() -> GameEngine {
        let e = GameEngine(settings: settings(), dictionary: fixtureIndex(), rng: ZeroRNG(), titleOverride: "사과")
        _ = e.handle(.start(players: [A, B, C]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        _ = e.handle(.deadline, nowMs: 4400)
        _ = e.handle(.submit(player: "A", text: "사과"), nowMs: 5400)
        return e
    }
    private func resumed(_ s: GameSnapshot) -> GameEngine {
        GameEngine(resuming: s, settings: settings(), dictionary: fixtureIndex(), rng: ZeroRNG())
    }
    private func startedPlayer(_ events: [EngineEvent]) -> PlayerID? {
        if case .turnStart(_, let p, _, _, _, _, _, _) = events.first { return p }
        return nil
    }

    @Test func midTurnRestartsThatTurnAndKeepsScoresAndChain() {
        let e = afterASubmits()
        _ = e.handle(.deadline, nowMs: 7200)                      // B 턴
        let r = resumed(e.snapshot).resume(dropping: ["C"], nowMs: 100_000)
        #expect(startedPlayer(r.events) == "B")
        #expect(r.nextDeadlineMs == 100_000 + 10_900)
        let n = resumed(e.snapshot); _ = n.resume(dropping: ["C"], nowMs: 100_000)
        #expect(n.snapshot.scores["A"] == 17)
        #expect(n.snapshot.chain == ["사과"])
        #expect(n.snapshot.char == "과")
        #expect(n.snapshot.seats.map(\.id) == ["A", "B"])
    }

    @Test func leaverWhoseTurnItWasPassesToTheNextSeat() {
        let e = afterASubmits()
        _ = e.handle(.deadline, nowMs: 7200)                      // B 턴
        let r = resumed(e.snapshot).resume(dropping: ["B"], nowMs: 100_000)
        #expect(startedPlayer(r.events) == "C")
    }

    @Test func afterAcceptedWordTheNextPlayerGoes() {
        // A 차례가 막 끝나 다음은 B. 누가 나가든 원래 순서에서 다음 사람.
        for (leaver, next) in [("C", "B"), ("B", "C"), ("A", "B")] {
            let n = resumed(afterASubmits().snapshot)
            let r = n.resume(dropping: [leaver], nowMs: 100_000)
            #expect(r.events.isEmpty)
            #expect(r.nextDeadlineMs == 101_000)
            #expect(startedPlayer(n.handle(.deadline, nowMs: 101_000).events) == next, "\(leaver) 나감")
        }
    }

    @Test func afterTimeoutTheNextRoundStartsWithTheSamePlayer() {
        let e = afterASubmits()
        _ = e.handle(.deadline, nowMs: 7200)                      // B 턴
        _ = e.handle(.deadline, nowMs: 7200 + 10_900)             // B 시간 초과
        #expect(e.snapshot.roundOver == true)
        let n = resumed(e.snapshot)
        #expect(n.resume(dropping: ["C"], nowMs: 100_000).nextDeadlineMs == 101_000)
        #expect(n.handle(.deadline, nowMs: 101_000).events == [.roundReady(round: 2, char: "과", subChar: nil, mission: nil)])
        #expect(startedPlayer(n.handle(.deadline, nowMs: 103_400).events) == "B")
    }

    @Test func fewerThanTwoSeatsEndsTheGame() {
        let e = GameEngine(settings: settings(), dictionary: fixtureIndex(), rng: ZeroRNG(), titleOverride: "사과")
        _ = e.handle(.start(players: [A, B]), nowMs: 0)
        _ = e.handle(.deadline, nowMs: 2000)
        let r = resumed(e.snapshot).resume(dropping: ["A"], nowMs: 5000)
        if case .gameEnd(let ranking) = r.events.first { #expect(ranking.map(\.player) == ["B"]) } else { Issue.record("gameEnd여야 함") }
        #expect(r.nextDeadlineMs == nil)
    }

    @Test func droppingSomeoneAlreadyGoneIsHarmless() {
        let e = afterASubmits()
        _ = e.handle(.deadline, nowMs: 7200)                      // B 턴
        _ = e.handle(.playerLeft("C"), nowMs: 8000)               // 나가던 방장이 스스로를 이미 뺌
        let r = resumed(e.snapshot).resume(dropping: ["C"], nowMs: 100_000)
        #expect(startedPlayer(r.events) == "B")
    }

    @Test func wordUsesTravelInTheSnapshot() {
        #expect(afterASubmits().snapshot.wordUses == ["사과": 1])
    }

    @Test func snapshotsWithoutTheNewKeysStillDecode() throws {
        // 빌드 2 방장이 보낸 스냅샷에는 wordUses·roundOver 키가 없다.
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(afterASubmits().snapshot)) as! [String: Any]
        obj["wordUses"] = nil; obj["roundOver"] = nil
        let s = try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: obj))
        #expect(s.wordUses == nil && s.chain == ["사과"])
    }
}
