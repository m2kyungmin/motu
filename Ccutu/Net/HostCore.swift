import Foundation
import KkutuCore

/// 방장 기기에서 도는 끄투 서버 역할. 엔진을 소유하고 마감 타이머를 하나만 건다.
@MainActor @Observable
final class HostCore {
    private(set) var state: RoomState
    /// 플레이어별 전달 경로. 조립 지점(SessionCoordinator)이 넣어 준다.
    var deliver: (HostMessage, PlayerID) -> Void = { _, _ in }

    private let dictionary: WordIndex
    private var engine: GameEngine?
    private var marble: MarbleGame?
    private var robotTasks: [Task<Void, Never>] = []
    private var timer: Task<Void, Never>?
    private var nowMs: Int { Int(Date().timeIntervalSince1970 * 1000) }

    // 방장 승계: 이전 방장 대신 이 기기가 방을 이어받을 때만 쓴다.
    /// 다시 들어오길 기다리는 사람들. nil이면 승계 중이 아니다.
    private var awaiting: Set<PlayerID>?
    private var leavers: [PlayerID] = []
    private var migrationTimer: Task<Void, Never>?
    static let rejoinWaitSeconds = 8

    init(roomName: String, host: RoomPlayer, dictionary: WordIndex, settings: RoomSettings = RoomSettings(), isPractice: Bool = false) {
        state = RoomState(name: roomName, hostID: host.id, settings: settings, players: [host], gaming: false,
                          roomID: String(UUID().uuidString.prefix(8)), isPractice: isPractice)
        self.dictionary = dictionary
    }

    /// 이전 방장이 나간 방을 이 기기(me)가 이어받는다. 게임 중이면 마지막 스냅샷으로 엔진을 되살린다.
    /// 다른 사람들이 다시 들어오거나 rejoinWaitSeconds가 지나면 finishMigration이 상태를 알리고 게임을 재개한다.
    init(resuming room: RoomState, snapshot: GameSnapshot?, me: PlayerID, oldHost: PlayerID, dictionary: WordIndex) {
        var s = room
        s.players.removeAll { $0.id == oldHost }
        s.hostID = me
        if let i = s.players.firstIndex(where: { $0.id == me }) { s.players[i].ready = true }
        if s.roomID == nil { s.roomID = String(UUID().uuidString.prefix(8)) }
        self.dictionary = dictionary
        if s.gaming, let snapshot {
            engine = GameEngine(resuming: snapshot, settings: s.settings, dictionary: dictionary)
        } else {
            s.gaming = false                                  // 게임 상태를 못 받았으면 대기실로
        }
        state = s
        leavers = [oldHost]
        awaiting = Set(s.players.filter { !$0.isRobot && $0.id != me }.map(\.id))
    }

    /// deliver를 연결한 뒤 부른다.
    func beginMigration() {
        guard let awaiting else { return }
        if awaiting.isEmpty { finishMigration(); return }
        migrationTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.rejoinWaitSeconds))
            guard !Task.isCancelled else { return }
            self?.finishMigration()
        }
    }

    private func finishMigration() {
        guard let missing = awaiting else { return }
        awaiting = nil
        migrationTimer?.cancel(); migrationTimer = nil
        state.players.removeAll { missing.contains($0.id) }
        broadcastState()
        guard let engine else { return }
        let (events, deadline) = engine.resume(dropping: leavers + missing, nowMs: nowMs)
        for e in events { broadcast(.gameEvent(e, engine.snapshot)) }
        schedule(deadline)
    }

    /// 전송 연결 단계에서 받을지. 게임 중이어도 이미 자리가 있던 사람의 재입장은 받는다.
    func canAdmit(_ pid: PlayerID?) -> Bool {
        if canAccept { return true }
        guard let pid else { return false }
        return state.players.contains { $0.id == pid && !$0.isRobot }
    }

    /// 말풍선 한 줄에 들어갈 만큼. 끄투는 200자에서 자른다.
    static let chatLimit = 100

    var canAccept: Bool { !state.gaming && state.players.count < state.settings.maxPlayers }

    func receive(_ msg: ClientMessage, from pid: PlayerID) {
        if awaiting != nil {
            // 승계 중에는 재입장과 나가기만 받는다(엔진 시계가 아직 서 있다).
            switch msg {
            case .join:
                awaiting?.remove(pid)
                if awaiting?.isEmpty == true { finishMigration() }
            case .leave:
                remove(pid)
            default: break
            }
            return
        }
        switch msg {
        case .join(_, let name, let appearance):
            // ID는 전송 경로가 붙여 준 pid만 믿는다(메시지 본문 id로 남을 흉내 내지 못하게).
            let id = pid
            if state.players.contains(where: { $0.id == id }) {                                // 이미 앉은 사람의 재join
                broadcastState()
                if marble != nil { broadcastMarble() }
                return
            }
            guard canAccept else { deliver(.error(code: 429), id); return }
            let clean = String(name.filter { !$0.isNewline }.prefix(20))
            state.players.append(RoomPlayer(id: id, name: clean.isEmpty ? "플레이어" : clean, ready: false, robotLevel: nil,
                                            team: nextTeam, appearance: appearance?.sanitized))
            broadcastState()
        case .ready(let r):
            guard let i = state.players.firstIndex(where: { $0.id == pid }) else { return }
            state.players[i].ready = r
            broadcastState()
        case .setTeam(let team):
            guard !state.gaming, state.settings.matchMode == .team, (1...4).contains(team),
                  let i = state.players.firstIndex(where: { $0.id == pid && !$0.isRobot }) else { return }
            state.players[i].team = team
            state.players[i].ready = pid == state.hostID
            broadcastState()
        case .setRobotTeam(let id, let team):
            guard pid == state.hostID, !state.gaming, state.settings.matchMode == .team, (1...4).contains(team),
                  let i = state.players.firstIndex(where: { $0.id == id && $0.isRobot }) else { return }
            state.players[i].team = team
            broadcastState()
        case .updateSettings(let s):
            guard pid == state.hostID, !state.gaming else { return }
            state.settings = s
            broadcastState()
        case .addRobot(let level):
            guard pid == state.hostID, !state.gaming, canAccept else { return }
            addRobot(level: level)
        case .removeRobot(let id):
            guard pid == state.hostID, !state.gaming else { return }
            state.players.removeAll { $0.id == id && $0.isRobot }
            broadcastState()
        case .start:
            guard pid == state.hostID, !state.gaming else { return }
            startGame()
        case .submit(let text):
            dispatch(.submit(player: pid, text: text))
        case .chat(let text):
            guard state.players.contains(where: { $0.id == pid }) else { return }
            let clean = String(text.filter { !$0.isNewline }.trimmingCharacters(in: .whitespaces).prefix(Self.chatLimit))
            guard !clean.isEmpty else { return }
            broadcast(.chat(from: pid, text: clean))
        case .marbleWord(let text, let target):
            marbleSubmit(text, from: pid, target: target)
        case .marbleLoser(let i):
            guard pid == state.hostID, marble != nil else { return }
            marble?.finish(loser: i)
            if state.settings.marble?.penalties?.count == 1 { drawPenalty() }   // 하나로 정해 둔 벌칙은 바로
            broadcastMarble()
        case .marbleDraw:
            guard pid == state.hostID else { return }
            drawPenalty()
            broadcastMarble()
        case .restart:
            guard pid == state.hostID, state.gaming else { return }
            stopMarble()
            timer?.cancel(); engine = nil
            state.gaming = false
            for i in state.players.indices where !state.players[i].isRobot && state.players[i].id != state.hostID { state.players[i].ready = false }
            broadcastState()
        case .leave:
            remove(pid)
        }
    }

    func addRobot(level: Int) {
        let id = "robot-\(UUID().uuidString.prefix(6))"
        state.players.append(RoomPlayer(id: id, name: "모투 봇 · \(Robot.levelName(level))", ready: true, robotLevel: level, team: nextTeam))
        broadcastState()
    }

    func remove(_ pid: PlayerID) {
        if awaiting != nil {
            awaiting?.remove(pid)
            state.players.removeAll { $0.id == pid }
            leavers.append(pid)
            if awaiting?.isEmpty == true { finishMigration() }
            return
        }
        state.players.removeAll { $0.id == pid }
        if state.gaming { dispatch(.playerLeft(pid)) }
        broadcastState()
    }

    func stop() { timer?.cancel(); migrationTimer?.cancel(); engine = nil; stopMarble() }

    private func startGame() {
        guard state.players.count >= 2 else { deliver(.error(code: 411), state.hostID); return }
        let others = state.players.filter { $0.id != state.hostID }
        guard others.allSatisfy(\.ready) else { deliver(.error(code: 412), state.hostID); return }
        let seats = state.players.map { Player(id: $0.id, name: $0.name, robotLevel: $0.robotLevel, team: $0.team, appearance: $0.appearance) }.shuffled()
        if state.settings.matchMode == .team && !TeamPlay.isBalanced(seats) {
            deliver(.error(code: 418), state.hostID); return
        }
        state.gameID = UUID().uuidString
        state.gaming = true
        broadcastState()
        if let m = state.settings.marble { startMarble(m); return }
        engine = GameEngine(settings: state.settings, dictionary: dictionary)
        dispatch(.start(players: seats))
    }

    private var nextTeam: Int? {
        guard state.settings.matchMode == .team else { return nil }
        return (1...2).min { a, b in
            state.players.filter { $0.team == a }.count < state.players.filter { $0.team == b }.count
        }
    }

    private func dispatch(_ input: EngineInput) {
        guard let engine else { return }
        let (events, deadline) = engine.handle(input, nowMs: nowMs)
        for e in events { broadcast(.gameEvent(e, engine.snapshot)) }
        schedule(deadline)
    }

    private func schedule(_ deadlineMs: Int?) {
        timer?.cancel()
        guard let deadlineMs else { return }
        timer = Task { [weak self] in
            guard let self else { return }
            let wait = max(0, deadlineMs - self.nowMs)
            try? await Task.sleep(for: .milliseconds(wait))
            guard !Task.isCancelled else { return }
            self.dispatch(.deadline)
        }
    }

    // MARK: 마블 룰렛

    private func startMarble(_ settings: MarbleSettings) {
        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        let g = MarbleGame(players: state.players.map(\.id), settings: settings, options: state.settings.options,
                           dictionary: dictionary, nowMs: nowMs, rng: &rng)
        marble = g
        broadcastMarble()
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(g.remainingMs(nowMs: Int(Date().timeIntervalSince1970 * 1000))))
            guard !Task.isCancelled, let self else { return }
            var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
            self.marble?.startRace(rng: &rng)
            self.broadcastMarble()
        }
        for p in state.players where p.isRobot { startRobot(p) }
    }

    /// 로봇은 단계에 따라 몇 초마다 아직 안 나온 답을 하나씩 친다(가만히 있으면 공을 못 빼서 늘 진다).
    private func startRobot(_ p: RoomPlayer) {
        let gap = [7.0, 5.5, 4.0, 3.0, 2.2][min(4, max(0, p.robotLevel ?? 2))]
        robotTasks.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(gap * .random(in: 0.6...1.4)))
                guard !Task.isCancelled, let self, let g = self.marble, g.snapshot.phase == .playing else { return }
                var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
                guard let word = g.robotWord(rng: &rng) else { continue }
                self.marbleSubmit(word, from: p.id, target: g.robotTarget(p.id, rng: &rng))
            }
        })
    }

    private func marbleSubmit(_ text: String, from pid: PlayerID, target: PlayerID?) {
        guard marble != nil else { return }
        let word = String(text.prefix(30))
        switch marble!.submit(word, from: pid, target: target, nowMs: nowMs) {
        case .accepted: broadcastMarble()
        case .rejected(let code): deliver(.marbleReject(code: code, word: word), pid)
        case .offPrompt: deliver(.marbleReject(code: 400, word: word), pid)
        }
    }

    private func drawPenalty() {
        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        marble?.drawPenalty(among: state.settings.marble?.penalties?.count ?? 0, rng: &rng)
    }

    private func stopMarble() {
        robotTasks.forEach { $0.cancel() }
        robotTasks = []
        marble = nil
    }

    private func broadcastMarble() {
        guard let g = marble else { return }
        var s = g.snapshot
        s.remainingMs = g.remainingMs(nowMs: nowMs)
        broadcast(.marble(s))
    }

    /// 방장 화면이 굴리는 경주의 공 위치를 참가자들에게 그대로 넘긴다.
    func relayFrame(_ f: MarbleFrame) {
        for p in state.players where !p.isRobot && p.id != state.hostID { deliver(.marbleFrame(f), p.id) }
    }

    private func broadcastState() { broadcast(.roomState(state)) }
    private func broadcast(_ m: HostMessage) {
        for p in state.players where !p.isRobot { deliver(m, p.id) }
    }
}
