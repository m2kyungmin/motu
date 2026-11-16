import Foundation
import GameKit
import KkutuCore

@MainActor @Observable
final class SessionCoordinator {
    private(set) var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: "nickname") }
    }
    private(set) var nicknameWasChanged: Bool
    private(set) var customization: CustomizationProgress {
        didSet {
            if let data = try? JSONEncoder().encode(customization) {
                UserDefaults.standard.set(data, forKey: "customization.v1")
            }
        }
    }
    var shouldSuggestNickname: Bool { !nicknameWasChanged && playerName == "플레이어" }
    let myID: PlayerID = UUID().uuidString
    /// 로봇과 연습의 특수 규칙. 홈 화면은 게임을 마치고 돌아올 때마다 새로 만들어지므로 여기 둔다.
    var practiceOptions = RoomOptions()
    private(set) var dictionary: WordIndex?
    private(set) var dictionaryError: String?
    private var isLoadingDictionary = false
    private(set) var client: RoomClient?
    private var host: HostCore?
    private var hostTransport: (any HostTransport)?
    private(set) var nearbyPeer: NearbyPeer?
    private(set) var nearbyCode: String?
    let gameCenter = GameCenterService()
    private var internet: GameCenterTransport?
    var pendingInvite: GKInvite?
    var networkError: String?

    var isInternetRoom: Bool { internet != nil }

    func activateGameCenter() {
        gameCenter.onMatch = { [weak self] match, mode in self?.connectInternet(match: match, mode: mode) }
        gameCenter.onInvite = { [weak self] invite in
            // 막힐 초대면 "방에서 나가고 수락" 확인을 띄우지 않는다.
            guard let self, !self.gameCenter.blocksAnotherMatch() else { return }
            if self.client != nil || self.dictionary == nil { self.pendingInvite = invite }
            else { self.gameCenter.accept(invite) }
        }
        gameCenter.activate()
    }

    func acceptPendingInvite() {
        guard let invite = pendingInvite, dictionary != nil else { return }
        pendingInvite = nil
        guard !gameCenter.blocksAnotherMatch() else { return }   // 지금 방을 나가기 전에 확인
        teardown()
        gameCenter.accept(invite)
    }

    init() {
        let storedNickname = UserDefaults.standard.string(forKey: "nickname") ?? "플레이어"
        nickname = storedNickname
        let existingName = storedNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        nicknameWasChanged = UserDefaults.standard.object(forKey: "nicknameWasChanged") as? Bool
            ?? (!existingName.isEmpty && existingName != "플레이어")
        customization = UserDefaults.standard.data(forKey: "customization.v1")
            .flatMap { try? JSONDecoder().decode(CustomizationProgress.self, from: $0) } ?? CustomizationProgress()
        loadDictionary()
    }

    func loadDictionary() {
        guard dictionary == nil, !isLoadingDictionary else { return }
        isLoadingDictionary = true
        dictionaryError = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let url = Bundle.main.url(forResource: "words", withExtension: "tsv") else {
                await MainActor.run {
                    self?.dictionaryError = "사전 파일(words.tsv)이 번들에 없습니다."
                    self?.isLoadingDictionary = false
                }
                return
            }
            let t = Date()
            let idx = try? WordIndex.load(url: url)
            let elapsed = Date().timeIntervalSince(t)
            await MainActor.run {
                self?.dictionary = idx
                self?.isLoadingDictionary = false
                if idx == nil { self?.dictionaryError = "사전을 읽지 못했습니다." }
                print("[Ccutu] dictionary \(idx?.count ?? 0) words in \(elapsed)s")
            }
        }
    }

    /// 화면과 근처 방 목록에 쓸 이름. Bonjour TXT 레코드 크기도 제한한다.
    var playerName: String {
        var s = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = "플레이어" }
        while s.utf8.count > 63 { s.removeLast() }
        return s
    }

    @discardableResult func saveNickname(_ value: String) -> Bool {
        var clean = String(value.filter { !$0.isNewline }.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        while clean.utf8.count > 63 { clean.removeLast() }
        guard !clean.isEmpty, clean != nickname else { return false }
        nickname = clean
        nicknameWasChanged = true
        UserDefaults.standard.set(true, forKey: "nicknameWasChanged")
        return true
    }

    func equip(_ item: CosmeticItem) {
        var progress = customization
        if progress.equip(item.id) { customization = progress }
    }

    func resetAppearance(_ slot: CosmeticSlot) { customization.reset(slot) }

    private func makeClient(isHost: Bool) -> RoomClient {
        let client = RoomClient(myID: myID, isHost: isHost)
        client.onGameEnd = { [weak self, weak client] snapshot in
            guard let self, let client, let room = client.room, let gameID = room.gameID else { return }
            var progress = self.customization
            let reward = progress.recordResult(gameID: gameID, snapshot: snapshot, mode: room.settings.matchMode,
                                               playerID: self.myID, isPractice: room.isPractice != false,
                                               isMarble: room.settings.marble != nil)
            guard progress.wins > self.customization.wins else { return }
            self.customization = progress
            client.unlockedReward = reward
            client.earnedWin = true
        }
        return client
    }

    /// 호스트 코어 + 호스트 자신의 클라이언트를 인프로세스로 연결한다. 연습 모드는 withNetwork: false.
    /// marble이면 마블 룰렛 방(다른 사람은 방 찾기로 들어온다).
    @discardableResult
    func createRoom(withNetwork: Bool = true, marble: Bool = false, mode: MatchMode = .individual) -> HostCore? {
        guard let dictionary else { return nil }
        stopBrowsing()
        let name = playerName
        let me = RoomPlayer(id: myID, name: name, ready: true, robotLevel: nil, team: mode == .team ? 1 : nil,
                            appearance: customization.appearance.sanitized)
        var settings = RoomSettings(); settings.mode = mode
        let host = HostCore(roomName: marble ? "\(name)의 마블 룰렛" : "\(name)의 \(mode.title)", host: me,
                            dictionary: dictionary, settings: settings, isPractice: !withNetwork)
        let client = makeClient(isHost: true)
        let transport: NearbyHost?
        if withNetwork {
            let code = String(format: "%06d", Int.random(in: 0...999999))
            do {
                transport = try NearbyHost(displayName: name, roomName: host.state.name,
                    roomID: host.state.roomID ?? "", hostID: myID, mode: mode, code: code)
                nearbyCode = code
                transport?.onError = { [weak self] error in self?.networkError = error }
            } catch {
                networkError = "근처 방을 열지 못했습니다. 잠시 후 다시 시도해 주세요."
                return nil
            }
        } else { transport = nil }
        wire(host: host, client: client, transport: transport)
        host.receive(.join(id: me.id, name: name), from: me.id)   // 첫 roomState 전송
        if marble {
            var m = MarbleSettings(); m.penalties = PenaltyStore.stake
            var s = RoomSettings(); s.marble = m
            host.receive(.updateSettings(s), from: myID)
        }
        return host
    }

    /// 방장 기기에서 HostCore·자기 RoomClient·전송 경로를 잇는다. 방을 만들 때와 방장을 이어받을 때 같이 쓴다.
    private func wire(host: HostCore, client: RoomClient, transport: (any HostTransport)?) {
        let me = myID
        host.deliver = { [weak client, weak transport] msg, pid in
            if pid == me {
                client?.apply(msg)
                if case .roomState(let s) = msg { transport?.updateCount(s.players.count, max: s.settings.maxPlayers, mode: s.settings.matchMode) }
            } else {
                transport?.send(msg, to: pid)
            }
        }
        transport?.onMessage = { [weak host] msg, pid in if pid != me { host?.receive(msg, from: pid) } }
        transport?.onPeerLost = { [weak host] pid in host?.remove(pid) }
        transport?.shouldAccept = { [weak host] pid in host?.canAdmit(pid) ?? false }
        client.send = { [weak host] msg in host?.receive(msg, from: me) }
        client.sendFrame = { [weak host] f in host?.relayFrame(f) }
        client.onLeave = { [weak self] in self?.teardown() }
        self.host = host
        self.hostTransport = transport
        self.client = client
    }

    func startPractice(level: Int) {
        guard let host = createRoom(withNetwork: false) else { return }
        var s = RoomSettings(); s.maxPlayers = 2; s.options = practiceOptions
        host.receive(.updateSettings(s), from: myID)
        host.receive(.addRobot(level: level), from: myID)
        host.receive(.start, from: myID)
    }

    func startBrowsing() {
        // 방에 들어가는 중이거나 들어가 있으면 그 연결을 쥔 peer를 바꾸지 않는다.
        // (코드 입력창이 닫히며 방 찾기 화면의 onAppear가 다시 불려, 맺던 연결을 끊고 있었다)
        guard client == nil else { return }
        nearbyPeer?.stop()
        nearbyPeer = NearbyPeer()
    }

    func stopBrowsing() {
        nearbyPeer?.stop()
        nearbyPeer = nil
    }

    func join(_ room: NearbyPeer.FoundRoom, code: String) {
        guard let peer = nearbyPeer else { return }
        let client = makeClient(isHost: false)
        connect(peer, client: client)
        self.client = client
        nearbyCode = code
        peer.invite(room, code: code)
        // 스펙 §8.2: 10초 안에 방 상태를 못 받으면 연결 실패로 알린다.
        Task { [weak client] in
            try? await Task.sleep(for: .seconds(10))
            if let client, client.room == nil { client.connectFailed = true }
        }
    }

    private func connect(_ peer: NearbyPeer, client: RoomClient) {
        let id = myID, name = playerName
        let appearance = customization.appearance.sanitized
        peer.onConnected = { [weak peer] in peer?.send(.join(id: id, name: name, appearance: appearance)) }
        peer.onMessage = { [weak client] m in client?.apply(m) }
        peer.onDisconnected = { [weak self, weak client] in
            if let client, client.room == nil {
                client.connectionError = "방 코드가 맞는지, 방이 아직 열려 있는지 확인해 주세요."
                client.connectFailed = true
            } else { self?.hostLost() }
        }
        client.send = { [weak peer] m in peer?.send(m) }
        client.onLeave = { [weak self] in self?.teardown() }
    }

    private func connectInternet(match: GKMatch, mode: MatchMode) {
        // 친구 추가로 지금 방의 매치에 사람만 늘었다. 새 사람은 transport가 연결 상태 변화로 받는다.
        guard match !== internet?.match else { return }
        guard let dictionary else { match.disconnect(); return }
        teardown()
        let transport = GameCenterTransport(match: match, myID: myID, mode: mode)
        internet = transport
        let client = makeClient(isHost: false)
        client.confirmsLeave = gameCenter.oneMatchPerLaunch
        self.client = client
        transport.onHostMessage = { [weak client] message in client?.apply(message) }
        transport.onHostLost = { [weak self] in self?.hostLost() }
        transport.onError = { [weak self, weak client] error in
            self?.networkError = error
            client?.connectionError = error
            if client?.room == nil { client?.connectFailed = true }
            else { client?.disconnected = true }
        }
        transport.onHostReady = { [weak self, weak transport] in
            guard let self else { return }
            transport?.sendClient(.join(id: self.myID, name: self.playerName, appearance: self.customization.appearance.sanitized))
        }
        transport.onReady = { [weak self, weak client, weak transport] isHost in
            guard let self, let client, let transport else { return }
            if isHost {
                let me = RoomPlayer(id: self.myID, name: self.playerName, ready: true, robotLevel: nil,
                    team: mode == .team ? 1 : nil, appearance: self.customization.appearance.sanitized)
                var settings = RoomSettings(); settings.mode = mode
                let host = HostCore(roomName: "\(self.playerName)의 \(mode.title)", host: me,
                                    dictionary: dictionary, settings: settings)
                client.promoteToHost()
                self.wire(host: host, client: client, transport: transport)
                host.receive(.join(id: me.id, name: me.name), from: me.id)
            } else {
                client.send = { [weak transport] message in transport?.sendClient(message) }
                client.onLeave = { [weak self] in self?.teardown() }
                transport.sendClient(.join(id: self.myID, name: self.playerName, appearance: self.customization.appearance.sanitized))
            }
        }
        client.onLeave = { [weak self] in self?.teardown() }
        transport.start()
        Task { [weak client] in
            try? await Task.sleep(for: .seconds(20))
            if let client, client.room == nil { client.connectFailed = true }
        }
    }

    /// 인터넷 방 대기실에서 방장만, 자리가 남았을 때 친구를 더 부를 수 있다.
    var canInviteMore: Bool {
        guard let internet, let client, client.isHost, let room = client.room, !room.gaming else { return false }
        return room.players.count < room.settings.maxPlayers && internet.match.players.count + 1 < GameCenterService.matchCap
    }

    func inviteMoreFriends() {
        guard canInviteMore, let internet, let settings = client?.room?.settings else { return }
        gameCenter.inviteMore(to: internet.match, mode: settings.matchMode, maxPlayers: settings.maxPlayers)
    }

    // MARK: 방장 승계

    /// 방장과의 연결이 끊겼다. 방 입장 순서상 다음 사람(로봇 제외)이 방장을 이어받는다.
    /// 모든 기기가 같은 방 정보로 같은 답을 낸다(나가던 방장이 스스로를 뺀 상태를 받았든 못 받았든).
    private func hostLost() {
        guard let client else { return }
        guard client.migratingFrom == nil, let room = client.room,
              let next = room.players.first(where: { !$0.isRobot && $0.id != room.hostID }) else {
            client.disconnected = true                      // 승계 중에 또 끊겼거나 이어받을 사람이 없다
            return
        }
        client.migratingFrom = room.hostID
        if let internet {
            guard internet.selectHost(next.id) else { client.disconnected = true; return }
            if next.id == myID {
                guard let dictionary else { client.disconnected = true; return }
                let host = HostCore(resuming: room, snapshot: client.snapshot, me: myID,
                                    oldHost: room.hostID, dictionary: dictionary)
                client.promoteToHost()
                wire(host: host, client: client, transport: internet)
                host.beginMigration()
                internet.announceHost()
            } else {
                internet.sendClient(.join(id: myID, name: playerName, appearance: customization.appearance.sanitized))
                migrationTimeout(client)
            }
        } else if next.id == myID {
            becomeHost(room: room, snapshot: client.snapshot, oldHost: room.hostID, client: client)
        } else {
            rejoin(room: room, newHost: next.id, client: client)
        }
    }

    private func becomeHost(room: RoomState, snapshot: GameSnapshot?, oldHost: PlayerID, client: RoomClient) {
        guard let dictionary else { client.disconnected = true; return }
        nearbyPeer?.stop(); nearbyPeer = nil
        let host = HostCore(resuming: room, snapshot: snapshot, me: myID, oldHost: oldHost, dictionary: dictionary)
        guard let code = nearbyCode,
              let transport = try? NearbyHost(displayName: playerName, roomName: room.name,
                roomID: host.state.roomID ?? "", hostID: myID, mode: room.settings.matchMode, code: code) else {
            client.disconnected = true; return
        }
        transport.onError = { [weak self] error in self?.networkError = error }
        client.promoteToHost()
        wire(host: host, client: client, transport: transport)
        host.beginMigration()
    }

    private func rejoin(room: RoomState, newHost: PlayerID, client: RoomClient) {
        guard let roomID = room.roomID, let code = nearbyCode else { client.disconnected = true; return }   // 빌드 2 방장이 만든 방
        nearbyPeer?.stop()
        let peer = NearbyPeer()
        connect(peer, client: client)
        peer.autoJoin = (roomID, newHost, myID, code)
        nearbyPeer = peer
        // 새 방장이 기다리는 시간보다 조금 더 기다린 뒤에도 못 붙었으면 지금처럼 "방장이 나갔습니다".
        migrationTimeout(client)
    }

    private func migrationTimeout(_ client: RoomClient) {
        Task { [weak client] in
            try? await Task.sleep(for: .seconds(HostCore.rejoinWaitSeconds + 4))
            if let client, client.migratingFrom != nil { client.disconnected = true }
        }
    }

    func teardown() {
        SoundPlayer.shared.stopAll()                         // 엔진은 바로 서지만 턴 배경음은 곡이 끝날 때까지 남는다
        host?.stop(); host = nil
        hostTransport?.stop(); hostTransport = nil
        internet?.stop(); internet = nil
        nearbyCode = nil
        nearbyPeer?.stop(); nearbyPeer = nil
        client = nil
    }
}
