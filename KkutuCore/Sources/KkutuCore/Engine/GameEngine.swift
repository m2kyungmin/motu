import Foundation

/// 끄투 classic.js + kkutu.js(KSH)의 결정론적 이식. 시계·타이머를 갖지 않는다.
/// 호출자는 handle()이 돌려준 nextDeadlineMs에 .deadline을 넣어 준다.
public final class GameEngine {
    public private(set) var snapshot: GameSnapshot
    let settings: RoomSettings
    let dict: WordIndex
    var rng: any RandomNumberGenerator
    private let titleOverride: String?

    private enum Pending: Equatable { case roundReady, turnStart, turnNext, turnEnd }
    private var pending: Pending?
    private var deadlineMs: Int?
    private var turnStartedAtMs = 0
    /// 끄투 game.dic. 방장이 바뀌어도 이어지도록 스냅샷에 담는다.
    private var wordUses: [String: Int] {
        get { snapshot.wordUses ?? [:] }
        set { snapshot.wordUses = newValue }
    }

    // 로봇 예약 (Task 7이 채운다)
    var robotFireAtMs: Int?
    var robotText: String?
    var robotDone: Set<String> = []

    public init(settings: RoomSettings, dictionary: WordIndex, rng: any RandomNumberGenerator = SystemRandomNumberGenerator(), titleOverride: String? = nil) {
        self.settings = settings
        self.dict = dictionary
        self.rng = rng
        self.titleOverride = titleOverride
        self.snapshot = GameSnapshot(totalRounds: settings.rounds)
    }

    /// 방장 승계: 다른 기기가 받아 둔 마지막 스냅샷으로 엔진을 되살린다. 예약은 resume이 새로 건다.
    public convenience init(resuming s: GameSnapshot, settings: RoomSettings, dictionary: WordIndex,
                            rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.init(settings: settings, dictionary: dictionary, rng: rng, titleOverride: s.title)
        snapshot = s
    }

    /// 나간 사람들을 자리에서 빼고 멈춘 단계를 이어 간다. 이미 자리에 없는 사람은 무시한다
    /// (나가던 방장이 스스로를 뺀 스냅샷을 받은 기기도 있고 못 받은 기기도 있다).
    /// 진행 중이던 턴은 남은 라운드 시간으로 처음부터 다시 시작한다.
    public func resume(dropping leavers: [PlayerID], nowMs now: Int) -> (events: [EngineEvent], nextDeadlineMs: Int?) {
        var ev: [EngineEvent] = []
        guard snapshot.phase != .idle, snapshot.phase != .ended else { return ([], nil) }
        let advancing = snapshot.phase == .turnResult && snapshot.roundOver != true   // 곧 다음 사람 차례
        for pid in leavers {
            guard let idx = snapshot.seats.firstIndex(where: { $0.id == pid }) else { continue }
            snapshot.seats.remove(at: idx)
            if idx < snapshot.turnIndex || (idx == snapshot.turnIndex && advancing) { snapshot.turnIndex -= 1 }
        }
        if !canContinue { gameEnd(&ev); return (ev, nil) }
        switch snapshot.phase {
        case .starting: schedule(.roundReady, at: now + 1000)
        case .roundReady, .turn: turnStart(now: now, &ev)
        case .turnResult: schedule(snapshot.roundOver == true ? .roundReady : .turnNext, at: now + 1000)
        case .idle, .ended: break
        }
        return (ev, nextDeadlineMs)
    }

    public func handle(_ input: EngineInput, nowMs: Int) -> (events: [EngineEvent], nextDeadlineMs: Int?) {
        var events: [EngineEvent] = []
        switch input {
        case .start(let players): start(players, now: nowMs, &events)
        case .submit(let pid, let text): submit(pid, text, now: nowMs, &events)
        case .playerLeft(let pid): playerLeft(pid, now: nowMs, &events)
        case .deadline: fireDeadline(now: nowMs, &events)
        }
        return (events, nextDeadlineMs)
    }

    private var nextDeadlineMs: Int? { [deadlineMs, robotFireAtMs].compactMap { $0 }.min() }

    private func random(_ n: Int) -> Int { n <= 0 ? 0 : Int(rng.next() % UInt64(n)) }

    private func schedule(_ p: Pending, at ms: Int) { pending = p; deadlineMs = ms }

    // MARK: 흐름

    private func start(_ players: [Player], now: Int, _ ev: inout [EngineEvent]) {
        guard snapshot.phase == .idle || snapshot.phase == .ended, !players.isEmpty else { return }
        if settings.matchMode == .team && !TeamPlay.isBalanced(players) { return }
        snapshot = GameSnapshot(totalRounds: settings.rounds)
        if settings.matchMode == .team {
            var teams = Array(Set(players.compactMap(\.team))).sorted()
            teams.shuffle(using: &rng)
            snapshot.seats = TeamPlay.turnOrder(players, teams: teams)
        } else {
            snapshot.seats = players
        }
        for p in players { snapshot.scores[p.id] = 0 }
        snapshot.title = titleOverride ?? makeTitle()
        snapshot.phase = .starting
        wordUses = [:]
        ev.append(.starting(title: snapshot.title))
        schedule(.roundReady, at: now + 2000)
    }

    /// 끄투 getTitle: 길이 max(2, 라운드 수)인 단어 중 모든 글자로 이을 수 있는 것. 50회 실패면 기본 제목.
    private func makeTitle() -> String {
        let length = max(2, settings.rounds)
        for _ in 0..<50 {
            guard let w = dict.randomWord(length: length, rng: &rng) else { break }
            let ok = w.text.allSatisfy { dict.hasCandidate(first: $0, sub: Hangul.subChar($0), options: settings.options) }
            if ok { return w.text }
        }
        return "가나다라마바사아자차"
    }

    private func randomMission() -> String {
        String(Scoring.missionChars[random(Scoring.missionChars.count)])
    }

    private func roundReady(now: Int, _ ev: inout [EngineEvent]) {
        snapshot.round += 1
        guard snapshot.round <= snapshot.totalRounds else { gameEnd(&ev); return }
        let chars = Array(snapshot.title)
        let c = chars[min(snapshot.round - 1, chars.count - 1)]
        snapshot.char = String(c)
        snapshot.subChar = Hangul.subChar(c).map(String.init)
        snapshot.chain = []
        snapshot.mission = settings.options.mission ? randomMission() : nil
        snapshot.roundTimeMs = settings.roundSeconds * 1000
        snapshot.phase = .roundReady
        ev.append(.roundReady(round: snapshot.round, char: snapshot.char, subChar: snapshot.subChar, mission: snapshot.mission))
        schedule(.turnStart, at: now + 2400)
    }

    private func turnStart(now: Int, _ ev: inout [EngineEvent]) {
        guard !snapshot.seats.isEmpty else { gameEnd(&ev); return }
        snapshot.turnIndex = ((snapshot.turnIndex % snapshot.seats.count) + snapshot.seats.count) % snapshot.seats.count
        snapshot.roundTimeMs = min(snapshot.roundTimeMs, max(10_000, 150_000 - snapshot.chain.count * 1500))
        let speed = Scoring.turnSpeed(roundTimeMs: snapshot.roundTimeMs)
        snapshot.turnTimeMs = Scoring.turnTimeMs(speed: speed)
        turnStartedAtMs = now
        snapshot.phase = .turn
        let p = snapshot.seats[snapshot.turnIndex]
        ev.append(.turnStart(turn: snapshot.turnIndex, player: p.id, char: snapshot.char, subChar: snapshot.subChar,
                             speed: speed, roundTimeMs: snapshot.roundTimeMs, turnTimeMs: snapshot.turnTimeMs, mission: snapshot.mission))
        schedule(.turnEnd, at: now + min(snapshot.roundTimeMs, snapshot.turnTimeMs + 100))
        robotDone = []
        robotFireAtMs = nil; robotText = nil
        scheduleRobotIfNeeded(now: now)
    }

    /// 스펙 §5.2: 두 글자 이상이고 첫 글자가 제시 글자나 두음 보조 글자. 화면도 제출 전에 이것으로 흔들기를 정한다.
    public static func isChainable(_ text: String, char: String, subChar: String?) -> Bool {
        guard text.count > 1, let first = text.first else { return false }
        return String(first) == char || String(first) == subChar
    }

    private func isChainable(_ text: String) -> Bool {
        Self.isChainable(text, char: snapshot.char, subChar: snapshot.subChar)
    }

    private func submit(_ pid: PlayerID, _ raw: String, now: Int, _ ev: inout [EngineEvent]) {
        guard snapshot.phase == .turn, let cur = snapshot.currentPlayer, cur.id == pid else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isChainable(text), let last = text.last else { return }
        if snapshot.chain.contains(text) { ev.append(.turnError(player: pid, code: 409, value: text)); return }
        guard let word = dict.word(text, options: settings.options) else { ev.append(.turnError(player: pid, code: 404, value: text)); return }
        if let code = WordFilter.rejectionCode(word, options: settings.options) {
            ev.append(.turnError(player: pid, code: code, value: text)); return
        }
        let lastSub = Hangul.subChar(last)
        let firstMove = snapshot.chain.isEmpty
        if firstMove || settings.options.manner {
            let used = Set(snapshot.chain + [text])
            if !dict.hasCandidate(first: last, sub: lastSub, options: settings.options, excluding: used) {
                ev.append(.turnError(player: pid, code: firstMove ? 402 : 403, value: text)); return
            }
        }
        let delay = now - turnStartedAtMs
        let (score, bonus) = computeScore(text: text, delayMs: delay)
        wordUses[text, default: 0] += 1
        snapshot.chain.append(text)
        snapshot.roundTimeMs -= delay
        snapshot.char = String(last)
        snapshot.subChar = lastSub.map(String.init)
        snapshot.scores[pid, default: 0] += score
        snapshot.phase = .turnResult
        snapshot.roundOver = false
        ev.append(.turnEnd(player: pid, ok: true, value: text, score: score, bonus: bonus, hint: nil))
        if bonus > 0 { snapshot.mission = randomMission() }
        robotFireAtMs = nil; robotText = nil
        schedule(.turnNext, at: now + snapshot.turnTimeMs / 6)
    }

    /// 끄투 classic.js getScore. 반환: (최종 점수, 미션 보너스분)
    private func computeScore(text: String, delayMs: Int) -> (Int, Int) {
        let tr = 1.0 - Double(delayMs) / Double(max(1, snapshot.turnTimeMs))
        var s = Scoring.preScore(length: text.count, chainCount: snapshot.chain.count, tr: tr)
        if let n = wordUses[text], n > 0 { s *= 15.0 / Double(n + 15) }
        let base = Int(s.rounded())
        if let m = snapshot.mission, let mc = m.first {
            let k = text.filter { $0 == mc }.count
            if k > 0 { s += s * 0.5 * Double(k) }
        }
        let total = Int(s.rounded())
        return (total, total - base)
    }

    private func turnTimeout(now: Int, _ ev: inout [EngineEvent]) {
        guard let p = snapshot.currentPlayer, let c = snapshot.char.first else { gameEnd(&ev); return }
        let cur = snapshot.scores[p.id, default: 0]
        let pen = Scoring.penalty(chainCount: snapshot.chain.count, score: cur)
        snapshot.scores[p.id] = cur + pen
        let hints = dict.candidates(first: c, sub: snapshot.subChar?.first, options: settings.options, excluding: Set(snapshot.chain))
        let hint = hints.isEmpty ? nil : hints[random(hints.count)].text
        snapshot.phase = .turnResult
        snapshot.roundOver = true
        robotFireAtMs = nil; robotText = nil
        ev.append(.turnEnd(player: p.id, ok: false, value: nil, score: pen, bonus: 0, hint: hint))
        schedule(.roundReady, at: now + 3000)
    }

    private func fireDeadline(now: Int, _ ev: inout [EngineEvent]) {
        if let fire = robotFireAtMs, fire <= (deadlineMs ?? Int.max), let text = robotText, let p = snapshot.currentPlayer {
            robotFireAtMs = nil; robotText = nil
            submit(p.id, text, now: now, &ev)
            if snapshot.phase == .turn { scheduleRobotIfNeeded(now: now) }   // 거절됐으면 다른 단어로
            return
        }
        guard let p = pending else { return }
        pending = nil; deadlineMs = nil
        switch p {
        case .roundReady: roundReady(now: now, &ev)
        case .turnStart: turnStart(now: now, &ev)
        case .turnNext: snapshot.turnIndex += 1; turnStart(now: now, &ev)
        case .turnEnd: turnTimeout(now: now, &ev)
        }
    }

    private func playerLeft(_ pid: PlayerID, now: Int, _ ev: inout [EngineEvent]) {
        guard snapshot.phase != .idle, snapshot.phase != .ended,
              let idx = snapshot.seats.firstIndex(where: { $0.id == pid }) else { return }
        let wasCurrent = idx == snapshot.turnIndex
        snapshot.seats.remove(at: idx)
        if idx < snapshot.turnIndex { snapshot.turnIndex -= 1 }
        if !canContinue { gameEnd(&ev); return }
        if wasCurrent {
            if snapshot.phase == .turn {
                turnStart(now: now, &ev)                    // 다음 사람(같은 인덱스)이 바로 시작
            } else if pending == .turnNext {
                snapshot.turnIndex -= 1                     // turnNext가 +1 하면 원래 다음 사람이 됨
            }
        }
    }

    private var canContinue: Bool {
        snapshot.seats.count >= 2 && snapshot.seats.contains(where: { !$0.isRobot })
            && (settings.matchMode != .team || Set(snapshot.seats.compactMap(\.team)).count >= 2)
    }

    private func gameEnd(_ ev: inout [EngineEvent]) {
        let teamScores = snapshot.teamScores
        let sorted = snapshot.seats.map { player in
            let score = settings.matchMode == .team ? teamScores[player.team ?? 0, default: 0] : snapshot.scores[player.id, default: 0]
            return (player.id, score)
        }.sorted { $0.1 > $1.1 }
        var ranking: [ScoreEntry] = []
        for (i, e) in sorted.enumerated() {
            let rank = (i > 0 && sorted[i - 1].1 == e.1) ? ranking[i - 1].rank : i + 1
            ranking.append(ScoreEntry(player: e.0, score: e.1, rank: rank))
        }
        snapshot.phase = .ended
        pending = nil; deadlineMs = nil
        robotFireAtMs = nil; robotText = nil
        ev.append(.gameEnd(ranking: ranking))
    }

    // MARK: 로봇
    func scheduleRobotIfNeeded(now: Int) {
        guard snapshot.phase == .turn, let p = snapshot.currentPlayer, let level = p.robotLevel, let c = snapshot.char.first else { return }
        let ctx = Robot.Context(char: c, subChar: snapshot.subChar?.first, turnTimeMs: snapshot.turnTimeMs,
                                firstMove: snapshot.chain.isEmpty, manner: settings.options.manner,
                                chain: snapshot.chain, done: robotDone, options: settings.options)
        guard let (text, delay) = Robot.choose(level: level, context: ctx, dict: dict, rng: &rng) else { return }
        robotDone.insert(text)
        robotText = text
        robotFireAtMs = now + delay
    }
}
