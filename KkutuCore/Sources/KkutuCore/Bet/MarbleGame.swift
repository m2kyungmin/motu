import Foundation

/// 마블 룰렛 방 설정. RoomSettings.marble이 nil이 아니면 그 방은 끝말잇기 대신 마블 룰렛이다.
public struct MarbleSettings: Codable, Hashable, Sendable {
    public static let secondsChoices = [30, 60, 90]
    public static let startChoices = [2, 3, 5]
    public var initials = true          // false면 시작 글자 문제
    public var seconds = 60
    public var startBalls = 3
    public var lastLoses = false        // false: 먼저 도착한 공이 벌칙, true: 마지막 공이 벌칙
    /// 시작 전에 건 벌칙. 하나면 그대로, 여럿이면 끝나고 그중에서 뽑는다. nil이면 아직 안 정함.
    public var penalties: [String]? = nil
    public init() {}
}

/// 방장이 모두에게 보내는 마블 룰렛 상태. 사람은 players 안의 번호로 가리킨다(공 색·경주 순서도 이 번호).
public struct MarbleSnapshot: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Sendable { case playing, racing, done }
    public struct Move: Codable, Hashable, Sendable {
        public let player: Int
        public let word: String
        public let target: Int          // player와 같으면 자기 공 빼기, 다르면 그 사람에게 넣기
    }

    public var players: [PlayerID]
    public var prompt: WordDash.Prompt
    public var counts: [Int]
    public var moves: [Move] = []
    public var phase: Phase = .playing
    public var remainingMs = 0          // 보내는 순간 남은 시간. 기기마다 시계가 달라 절대 시각 대신 쓴다.
    public var order: [Int]? = nil      // 경주에 넣을 공 주인 번호, 섞인 순서(racing부터)
    public var loser: Int? = nil        // done
    public var penalty: Int? = nil      // done 뒤 방장이 뽑은 벌칙(settings.penalties 안의 번호)
}

/// 방장 기기의 마블 룰렛 판정: 모두에게 같은 문제 하나, 시간 안에 동시에 친다.
/// 누가 쓴 단어든 한 번 나오면 끝이고, 맞힌 단어 하나가 공 하나(내 공 빼기 또는 남에게 넣기)다.
public struct MarbleGame {
    public private(set) var snapshot: MarbleSnapshot
    public let deadlineMs: Int
    private var ledger: BallLedger
    private var used: Set<String> = []
    private let dict: WordIndex
    private let options: RoomOptions

    /// 431 내 공이 1개뿐, 432 공이 가득 참, 433 시간 끝, 403 이 판 사람이 아님. 거절된 단어는 쓴 것으로 치지 않는다.
    public enum Outcome: Equatable, Sendable {
        case accepted(MarbleSnapshot.Move)
        case rejected(code: Int)
        case offPrompt
    }

    public init(players: [PlayerID], settings: MarbleSettings, options: RoomOptions, dictionary: WordIndex,
                nowMs: Int, rng: inout any RandomNumberGenerator) {
        // 여럿이 같은 답 더미를 나눠 쓰므로 답이 넉넉한 문제만.
        let prompt = WordDash.randomPrompt(settings.initials ? .initials : .starts, dictionary: dictionary,
                                           options: options, minAnswers: 80, rng: &rng)
        ledger = BallLedger(players: players.count, start: settings.startBalls)
        snapshot = MarbleSnapshot(players: players, prompt: prompt, counts: ledger.counts)
        deadlineMs = nowMs + settings.seconds * 1000
        dict = dictionary
        self.options = options
    }

    public func remainingMs(nowMs: Int) -> Int { max(0, deadlineMs - nowMs) }

    /// target이 nil이거나 자기 자신이면 자기 공 빼기.
    public mutating func submit(_ raw: String, from pid: PlayerID, target: PlayerID?, nowMs: Int) -> Outcome {
        guard snapshot.phase == .playing, nowMs < deadlineMs else { return .rejected(code: 433) }
        guard let me = snapshot.players.firstIndex(of: pid) else { return .rejected(code: 403) }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WordDash.fits(text, snapshot.prompt) else { return .offPrompt }
        if used.contains(text) { return .rejected(code: 409) }
        guard let word = dict.word(text, options: options) else { return .rejected(code: 404) }
        if let code = WordFilter.rejectionCode(word, options: options) { return .rejected(code: code) }
        let to = target.flatMap { snapshot.players.firstIndex(of: $0) } ?? me
        if to == me {
            guard ledger.remove(me) else { return .rejected(code: 431) }
        } else {
            guard ledger.add(to) else { return .rejected(code: 432) }
        }
        used.insert(text)
        let move = MarbleSnapshot.Move(player: me, word: text, target: to)
        snapshot.moves.append(move)
        snapshot.counts = ledger.counts
        return .accepted(move)
    }

    /// 시간이 다 됐다: 공을 섞어 경주 순서를 정한다.
    public mutating func startRace(rng: inout any RandomNumberGenerator) {
        guard snapshot.phase == .playing else { return }
        snapshot.phase = .racing
        snapshot.order = ledger.shuffledBalls(rng: &rng)
    }

    /// 방장 화면의 경주가 벌칙 공 주인을 정했다.
    public mutating func finish(loser: Int) {
        guard snapshot.phase == .racing, snapshot.counts.indices.contains(loser) else { return }
        snapshot.phase = .done
        snapshot.loser = loser
    }

    /// 벌칙 공 주인이 정해진 뒤 n개 중 하나를 뽑는다. 한 번만.
    public mutating func drawPenalty(among n: Int, rng: inout any RandomNumberGenerator) {
        guard snapshot.phase == .done, snapshot.penalty == nil, n > 0 else { return }
        snapshot.penalty = Int.random(in: 0..<n, using: &rng)
    }

    /// 로봇이 칠 단어: 아직 안 나온 답 하나. 답이 바닥나면 nil.
    public func robotWord(rng: inout any RandomNumberGenerator) -> String? {
        WordDash.answers(snapshot.prompt, dictionary: dict, options: options, limit: 400)
            .filter { !used.contains($0) }.randomElement(using: &rng)
    }

    /// 로봇의 공 대상: 자기 공을 뺄 수 있으면 빼고, 아니면 남 중 아무에게나 넣는다.
    public func robotTarget(_ pid: PlayerID, rng: inout any RandomNumberGenerator) -> PlayerID? {
        guard let me = snapshot.players.firstIndex(of: pid) else { return nil }
        if ledger.canRemove(me) { return pid }
        return snapshot.players.filter { $0 != pid }.randomElement(using: &rng)
    }
}
