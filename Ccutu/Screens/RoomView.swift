import SwiftUI
import KkutuCore

struct RoomView: View {
    @Environment(SessionCoordinator.self) private var co
    let client: RoomClient
    @State private var settings = RoomSettings()
    @State private var pickingRobot = false

    private var room: RoomState? { client.room }
    private var isHost: Bool { client.isHost }
    private var players: [RoomPlayer] { room?.players ?? [] }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(spacing: 18) {
                topBar
                connectionSection
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        playerSection
                        settingsSection
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                bottom
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .onAppear { if let s = room?.settings { settings = s } }
        .onChange(of: room?.settings) { _, s in if let s, !isHost { settings = s } }
        .onChange(of: settings) { _, s in if isHost, s != room?.settings { client.send(.updateSettings(s)) } }
        .sensoryFeedback(.selection, trigger: settings) { _, _ in isHost }   // 방장이 직접 바꿀 때만
        .confirmationDialog("로봇 난이도", isPresented: $pickingRobot, titleVisibility: .visible) {
            ForEach(0..<Robot.levelNames.count) { level in
                Button(Robot.levelName(level)) { client.send(.addRobot(level: level)) }
            }
        }
        .alert("시작할 수 없습니다", isPresented: Binding(get: { client.errorCode != nil }, set: { if !$0 { client.errorCode = nil } })) {
            Button("확인") {}
        } message: {
            Text(errorText(client.errorCode))
        }
    }

    // MARK: 위

    private var topBar: some View {
        HStack {
            Button { client.leave() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44).background(Circle().fill(Theme.card))
            }
            .accessibilityLabel("나가기")
            Spacer()
            VStack(spacing: 2) {
                Text(room?.name ?? "방").font(Theme.display(24)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("\(room?.settings.matchMode.title ?? "개인전") · \(isHost ? "참가자를 기다리는 중" : "방장이 시작하길 기다리는 중")")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text("\(players.count)/\(room?.settings.maxPlayers ?? 0)")
                .font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44).background(Circle().fill(Theme.card))
                .accessibilityLabel("인원 \(players.count)명, 최대 \(room?.settings.maxPlayers ?? 0)명")
        }
    }

    @ViewBuilder private var connectionSection: some View {
        if let code = co.nearbyCode {
            HStack(spacing: 12) {
                Image(systemName: "wifi").foregroundStyle(Theme.blue)
                Text("방 코드").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                Spacer()
                Text(code).font(.system(size: 22, weight: .bold, design: .monospaced))
                    .tracking(4).foregroundStyle(Theme.accent).textSelection(.enabled)
                    .accessibilityLabel("방 코드 \(code.map(String.init).joined(separator: " "))")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        } else if co.isInternetRoom {
            HStack {
                Label("Game Center · 인터넷 플레이", systemImage: "person.2.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                Spacer()
                if co.canInviteMore {
                    Button { co.inviteMoreFriends() } label: {
                        Label("친구 더 초대", systemImage: "person.badge.plus")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(Capsule().fill(Theme.card))
                    }
                }
            }
        }
    }

    // MARK: 플레이어

    private var playerSection: some View {
        VStack(spacing: 10) {
            HStack {
                SectionLabel(text: "플레이어")
                Spacer()
                let readyCount = players.filter { $0.id != room?.hostID && $0.ready }.count
                Text("\(readyCount)명 준비됨").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            if settings.matchMode == .team {
                Text("팀마다 같은 인원으로 두 팀 이상 골라 주세요. 팀을 바꾸면 준비가 해제돼요.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            VStack(spacing: 8) {
                ForEach(players) { playerRow($0) }
                if isHost && players.count < (room?.settings.maxPlayers ?? 8) {
                    Button { pickingRobot = true } label: {
                        Label("로봇 추가", systemImage: "plus")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.raised, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                    }
                }
            }
        }
    }

    private func playerRow(_ p: RoomPlayer) -> some View {
        let isRoomHost = p.id == room?.hostID
        return HStack(spacing: 12) {
            Avatar(name: p.name, isRobot: p.isRobot, tint: p.team.map(TeamPalette.color) ?? (isRoomHost ? Theme.accent : Theme.blue), size: 56, appearance: p.appearance)
            VStack(alignment: .leading, spacing: 0) {
                Text(p.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(isRoomHost ? "방장" : p.isRobot ? "항상 준비됨" : p.id == client.myID ? "나" : "참가자")
                    .font(.system(size: 12)).foregroundStyle(isRoomHost ? Theme.accent : Theme.muted)
            }
            Spacer(minLength: 0)
            if settings.matchMode == .team { teamPicker(p) }
            if p.isRobot {
                if isHost {
                    Button { client.send(.removeRobot(id: p.id)) } label: {
                        Image(systemName: "minus").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.danger)
                            .frame(width: 34, height: 34).background(Circle().fill(Theme.dangerBG))
                    }
                    .accessibilityLabel("\(p.name) 제거")
                }
            } else if isRoomHost {
                pill("시작 대기", fg: Theme.muted, bg: Theme.raised)
            } else if p.ready {
                pill("준비", fg: Theme.success, bg: Theme.successBG, icon: "checkmark")
            } else {
                pill("대기 중", fg: Theme.muted, bg: Theme.raised)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 76)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        .overlay { if isRoomHost { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accent, lineWidth: 2) } }
    }

    private func teamPicker(_ player: RoomPlayer) -> some View {
        let team = player.team ?? 1
        return Menu {
            ForEach(1...4, id: \.self) { choice in
                Button(TeamPalette.name(choice)) {
                    if player.isRobot { client.send(.setRobotTeam(id: player.id, team: choice)) }
                    else { client.send(.setTeam(choice)) }
                }
            }
        } label: {
            Text(TeamPalette.name(team))
                .font(.system(size: 11, weight: .bold)).foregroundStyle(TeamPalette.color(team))
                .padding(.horizontal, 8).frame(height: 32)
                .background(Capsule().fill(TeamPalette.color(team).opacity(0.15)))
        }
        .disabled(player.id != client.myID && !(isHost && player.isRobot))
        .accessibilityLabel("\(player.name), \(TeamPalette.name(team))")
    }

    private func pill(_ text: String, fg: Color, bg: Color, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .heavy)) }
            Text(text)
        }
        .font(.system(size: 12, weight: .bold)).foregroundStyle(fg)
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(bg))
    }

    // MARK: 설정

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: settings.marble == nil ? "설정" : "마블 룰렛 설정")
            if settings.marble != nil {
                marbleSettings
            } else {
                HStack(spacing: 8) {
                    tile("\(settings.rounds)", "라운드") {
                        Picker("라운드", selection: $settings.rounds) { ForEach(1...10, id: \.self) { Text("\($0)라운드").tag($0) } }
                    }
                    tile("\(settings.roundSeconds)", "초") {
                        Picker("라운드 시간", selection: $settings.roundSeconds) {
                            ForEach(RoomSettings.roundSecondsChoices, id: \.self) { Text("\($0)초").tag($0) }
                        }
                    }
                    maxPlayersTile
                }
            }
            OptionChips(options: $settings.options, editable: isHost)
        }
    }

    private var maxPlayersTile: some View {
        tile("\(settings.maxPlayers)", "최대 인원") {
            Picker("최대 인원", selection: $settings.maxPlayers) {
                ForEach(max(2, players.count)...8, id: \.self) { Text("\($0)명").tag($0) }
            }
        }
    }

    /// 마블 룰렛 방: 문제 종류·시간·처음 공·벌칙 공.
    private var marbleSettings: some View {
        let m = Binding(get: { settings.marble ?? MarbleSettings() }, set: { settings.marble = $0 })
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                tile("\(m.wrappedValue.seconds)", "초") {
                    Picker("제한 시간", selection: m.seconds) {
                        ForEach(MarbleSettings.secondsChoices, id: \.self) { Text("\($0)초").tag($0) }
                    }
                }
                tile("\(m.wrappedValue.startBalls)", "처음 공") {
                    Picker("처음 공", selection: m.startBalls) {
                        ForEach(MarbleSettings.startChoices, id: \.self) { Text("\($0)개씩").tag($0) }
                    }
                }
                maxPlayersTile
            }
            HStack(spacing: 8) {
                modeChip("초성", m.wrappedValue.initials) { m.wrappedValue.initials = true }
                modeChip("시작 글자", !m.wrappedValue.initials) { m.wrappedValue.initials = false }
            }
            HStack(spacing: 8) {
                modeChip("먼저 도착한 공이 벌칙", !m.wrappedValue.lastLoses) { m.wrappedValue.lastLoses = false }
                modeChip("마지막 공이 벌칙", m.wrappedValue.lastLoses) { m.wrappedValue.lastLoses = true }
            }
            StakeRow(stake: m.wrappedValue.penalties ?? PenaltyStore.defaults, editable: isHost) { m.wrappedValue.penalties = $0 }
        }
    }

    private func modeChip(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Chip(title: title, on: on) }
            .disabled(!isHost)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 숫자 타일. 방장이 누르면 메뉴로 값을 고른다.
    @ViewBuilder
    private func tile<P: View>(_ value: String, _ label: String, @ViewBuilder picker: () -> P) -> some View {
        let face = VStack(spacing: 2) {
            Text(value).font(Theme.display(28)).foregroundStyle(Theme.accent)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        if isHost {
            Menu { picker() } label: { face }.accessibilityLabel("\(label) \(value)")
        } else {
            face.accessibilityElement(children: .combine)
        }
    }

    // MARK: 아래

    @ViewBuilder private var bottom: some View {
        VStack(spacing: 10) {
            if isHost {
                Button("시작") { client.send(.start) }.buttonStyle(BigButtonStyle(fontSize: 28))
                Text("참가자가 모두 준비되면 시작할 수 있어요").font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                let ready = client.me?.ready == true
                Button(ready ? "준비 해제" : "준비") { client.send(.ready(!ready)) }
                    .buttonStyle(BigButtonStyle(kind: ready ? .outlined : .filled, fontSize: 28))
                Text(ready ? "방장이 시작하면 게임이 시작돼요" : "준비를 누르면 방장이 시작할 수 있어요")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func errorText(_ code: Int?) -> String {
        switch code {
        case 411: return "혼자서는 게임을 시작할 수 없습니다. 로봇을 추가하거나 친구를 기다리세요."
        case 412: return "모든 플레이어가 준비 상태여야 합니다."
        case 418: return "두 팀 이상이 필요하며, 각 팀의 인원수가 같아야 합니다."
        case 429: return "방이 꽉 찼습니다."
        default: return "오류 \(code ?? 0)"
        }
    }
}
