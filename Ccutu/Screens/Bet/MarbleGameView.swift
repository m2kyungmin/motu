import SwiftUI
import SpriteKit
import KkutuCore

/// 마블 룰렛 방의 게임 화면. 모두에게 같은 문제가 뜨고 시간 안에 동시에 친다.
/// 맞힌 단어 하나마다 고른 대상(내 공 빼기 / 남에게 넣기)으로 공이 움직이고, 통에서 실시간으로 보인다.
/// 시간이 끝나면 방장 폰이 굴리는 경주를 모든 폰이 같이 본다.
struct MarbleGameView: View {
    let client: RoomClient
    @State private var scene: MarbleScene?
    @State private var target: PlayerID?          // nil = 내 공 빼기
    @State private var input = ""
    @State private var focused = true
    @State private var field = WordFieldProxy()
    @State private var shake = 0
    @State private var errorText: String?
    @State private var countdown: Int?
    @State private var ranking: [Int] = []          // 경주 공 번호, 지금 순위대로
    @State private var finishedCount = 0

    private var m: MarbleSnapshot? { client.marble }
    private var playing: Bool { m?.phase == .playing }
    private var me: Int? { m?.players.firstIndex(of: client.myID) }
    private var lastLoses: Bool { client.room?.settings.marble?.lastLoses ?? false }
    private var stake: [String] { client.room?.settings.marble?.penalties ?? PenaltyStore.defaults }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            if let m {
                VStack(spacing: 10) {
                    if playing { header(m) }
                    sceneView
                        .clipShape(RoundedRectangle(cornerRadius: playing ? 24 : 0))
                        .ignoresSafeArea(edges: playing ? [] : .all)
                    if playing {
                        targetChips(m)
                        inputArea
                    }
                }
                .padding(.horizontal, playing ? 16 : 0)
                .padding(.top, playing ? 8 : 0)
                .padding(.bottom, playing ? 10 : 0)
                if !playing { raceOverlay(m) }
            } else {
                ProgressView().tint(Theme.muted).controlSize(.large)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { makeScene() }
        .onChange(of: m == nil) { makeScene() }
        .onChange(of: m?.counts) { _, c in
            if let c { scene?.setCounts(c) }
            if let me, let c, target == nil, c[me] <= 1 { target = firstOther }   // 더 못 빼면 넣기로
        }
        .onChange(of: m?.moves.count) { _, _ in feedback() }
        .onChange(of: m?.phase) { _, p in phaseChanged(p) }
        .onChange(of: client.marbleReject) { _, r in if let r { reject(message(r.code)) } }
        .task(id: client.marbleDeadline) { await lastSecondsTicks() }
    }

    // MARK: 조각

    private func name(_ i: Int) -> String {
        guard let pid = m?.players[safe: i] else { return "?" }
        return client.room?.players.first { $0.id == pid }?.name ?? "나간 사람"
    }

    private func color(_ i: Int) -> Color { Color(uiColor: MarbleScene.palette[i % MarbleScene.palette.count]) }

    private var firstOther: PlayerID? {
        guard let m else { return nil }
        return m.players.first { $0 != client.myID }
    }

    private func header(_ m: MarbleSnapshot) -> some View {
        HStack(spacing: 12) {
            Button { client.leave() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                    .frame(width: 32, height: 32).background(Circle().fill(Theme.card))
            }
            .accessibilityLabel("나가기")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(m.prompt.initialsLabel).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                Text(m.prompt.text).font(Theme.display(40)).tracking(4).foregroundStyle(Theme.accent)
                if let sub = m.prompt.subChar { Text("(\(sub))").font(Theme.display(20)).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let left = max(0, client.marbleDeadline.timeIntervalSince(ctx.date))
                Text("\(Int(left.rounded(.up)))").font(Theme.display(30)).monospacedDigit()
                    .foregroundStyle(left <= 5 ? Theme.danger : Theme.ink)
            }
        }
    }

    private var sceneView: some View {
        GeometryReader { g in
            ZStack(alignment: .top) {
                Theme.card
                if let scene {
                    SpriteView(scene: scene, options: [.allowsTransparency])   // 첫 프레임 전 회색 판을 안 보이게
                        .onAppear { scene.setViewport(g.size) }
                        .onChange(of: g.size) { _, s in scene.setViewport(s) }
                }
                if playing {
                    VStack(spacing: 6) {
                        Label("벌칙: \(PenaltyStore.summary(stake))", systemImage: "flame.fill")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted).lineLimit(1)
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(Capsule().fill(Theme.ground.opacity(0.85)))
                        if let last = m?.moves.last { moveTicker(last) }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    private func moveTicker(_ mv: MarbleSnapshot.Move) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color(mv.player)).frame(width: 10, height: 10)
            Text(name(mv.player)).foregroundStyle(Theme.ink)
            Text(mv.word).foregroundStyle(Theme.accent)
            Image(systemName: "arrow.right").foregroundStyle(Theme.muted)
            Text(mv.target == mv.player ? "−1" : "\(name(mv.target)) +1")
                .foregroundStyle(mv.target == mv.player ? Theme.success : Theme.danger)
        }
        .font(.system(size: 14, weight: .bold))
        .lineLimit(1)
        .padding(.horizontal, 14).frame(height: 34)
        .background(Capsule().fill(Theme.ground.opacity(0.85)))
        .id(m?.moves.count)
        .transition(.opacity)
    }

    private func targetChips(_ m: MarbleSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let me {
                    chip(dot: color(me), title: "내 공 빼기", count: m.counts[me], on: target == nil || target == client.myID,
                         enabled: m.counts[me] > 1) { target = nil }
                }
                ForEach(m.players.indices.filter { $0 != me }, id: \.self) { i in
                    chip(dot: color(i), title: "\(name(i))에게", count: m.counts[i], on: target == m.players[i], enabled: true) {
                        target = m.players[i]
                    }
                }
            }
        }
    }

    private func chip(dot: Color, title: String, count: Int, on: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 10, height: 10)
                Text(title).lineLimit(1)
                Text("\(count)").monospacedDigit().foregroundStyle(on ? Theme.onAccent.opacity(0.6) : Theme.dim)
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(on ? Theme.onAccent : enabled ? Theme.ink : Theme.dim)
            .padding(.horizontal, 14).frame(height: 38)
            .background(Capsule().fill(on ? Theme.accent : Theme.raised))
        }
        .disabled(!enabled)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.danger)
                    .padding(.leading, 8)
            }
            HStack(spacing: 10) {
                WordField(text: $input, focused: $focused, placeholder: "단어 입력", proxy: field, onSubmit: submit)
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                    .background(Capsule().fill(Theme.card))
                    .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 2))
                    .modifier(ShakeEffect(shakes: CGFloat(shake)))
                    .onTapGesture { focused = true }
                Button { field.submit() } label: {
                    Image(systemName: "arrow.right").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.onAccent)
                        .frame(width: 56, height: 56)
                        .background {
                            ZStack {
                                Circle().fill(Theme.accentShadow).offset(y: 5)
                                Circle().fill(Theme.accent)
                            }
                        }
                }
                .accessibilityLabel("보내기")
            }
        }
    }

    private func raceOverlay(_ m: MarbleSnapshot) -> some View {
        ZStack {
            VStack {
                HStack(alignment: .top) {                      // 순위표가 길어져도 닫기 버튼은 위에
                    Button { client.leave() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                            .frame(width: 32, height: 32).background(Circle().fill(Theme.card))
                    }
                    .accessibilityLabel("나가기")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(lastLoses ? "마지막으로 도착한 공이 벌칙" : "먼저 도착한 공이 벌칙")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 12).frame(height: 32).background(Capsule().fill(Theme.card))
                        if m.phase == .racing, countdown == nil, let order = m.order { rankingPanel(order) }
                    }
                }
                if m.phase == .done, let loser = m.loser { resultCard(loser).padding(.top, 8) }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            if let countdown {
                Text("\(countdown)").font(Theme.display(140)).foregroundStyle(Theme.accent)
                    .shadow(color: .black.opacity(0.5), radius: 12)
            }
        }
        .animation(.spring(duration: 0.35), value: m.phase)
    }

    /// 오른쪽 위 실시간 순위. 벌칙이 걸린 쪽(먼저 도착 규칙은 앞, 마지막 공 규칙은 뒤) 8줄만 보인다.
    private func rankingPanel(_ order: [Int]) -> some View {
        let n = ranking.count
        let shown = lastLoses ? Array(max(0, n - 8)..<n) : Array(0..<min(8, n))
        let danger = lastLoses ? n - 1 : 0
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(shown, id: \.self) { k in
                let ball = ranking[k]
                let owner = order.indices.contains(ball) ? order[ball] : 0
                HStack(spacing: 6) {
                    Text("\(k + 1)").font(.system(size: 12, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(k == danger ? Theme.ink : Theme.dim).frame(width: 20, alignment: .trailing)
                    Circle().fill(color(owner)).frame(width: 10, height: 10)
                    Text(name(owner)).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    if k < finishedCount { Image(systemName: "flag.checkered").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                }
                .padding(.horizontal, 8)
                .frame(width: 150, height: 22)
                .background(RoundedRectangle(cornerRadius: 8).fill(k == danger ? Theme.danger.opacity(0.55) : .clear))
                .id(ball)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.ground.opacity(0.75)))
        .animation(.spring(duration: 0.3), value: ranking)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("순위")
    }

    private func resultCard(_ i: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(color(i)).frame(width: 24, height: 24)
                Text("\(name(i)) 벌칙!").font(Theme.display(38)).foregroundStyle(Theme.danger)
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            if stake.count == 1 {
                Text(stake[0]).font(Theme.display(30)).foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 80)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Theme.raised))
            } else {
                PenaltyWheel(items: stake, result: m?.penalty, size: 240)
                if m?.penalty == nil {
                    if client.isHost {
                        Button { client.send(.marbleDraw) } label: { Label("벌칙 뽑기", systemImage: "die.face.5") }
                            .buttonStyle(BigButtonStyle())
                    } else {
                        Text("방장이 벌칙을 뽑아요").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                    }
                }
            }
            if client.isHost {
                Button("다시 하기") { client.send(.restart) }.buttonStyle(BigButtonStyle(kind: .outlined))
            } else {
                Text("방장이 다시 시작하면 대기실로 돌아가요").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28).fill(Theme.card))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: 진행

    private func makeScene() {
        guard scene == nil, let m else { return }
        let labels = m.players.indices.map { String(name($0).prefix(1)) }
        let s = MarbleScene(labels: labels)
        s.setCounts(m.counts)
        s.onFrame = { [client] f in client.sendFrame(f) }
        s.onDecided = { [client] i in
            Task {
                try? await Task.sleep(for: .seconds(1.2))          // 공이 결승선을 넘는 걸 보고 나서
                client.send(.marbleLoser(i))
            }
        }
        client.onFrame = { [weak s] f in s?.apply(f) }
        s.onRanking = { order, fin in ranking = order; finishedCount = fin }
        s.onClimax = { SoundPlayer.shared.bgm("bgm_race_climax", fade: 0.4) }    // 결승 직전엔 빠른 판으로
        scene = s
        if me.map({ m.counts[$0] <= 1 }) == true { target = firstOther }
        SoundPlayer.shared.play("game_start")
        if m.phase != .playing { phaseChanged(m.phase) }          // 경주 중에 다시 들어온 경우
    }

    private func phaseChanged(_ p: MarbleSnapshot.Phase?) {
        switch p {
        case .racing:
            guard let m, let order = m.order, let scene else { return }
            focused = false
            SoundPlayer.shared.play("timeout")
            Haptics.timedOut()
            scene.layoutRace(order: order, lastLoses: lastLoses, physics: client.isHost)
            Task {
                for n in [3, 2, 1] {
                    countdown = n
                    Haptics.tick()
                    try? await Task.sleep(for: .seconds(0.8))
                }
                countdown = nil
                SoundPlayer.shared.play("game_start")
                SoundPlayer.shared.bgm("bgm_race", fade: 0.3)
                if client.isHost { scene.start() }
            }
        case .done:
            SoundPlayer.shared.bgm(nil, fade: 1.2)
            SoundPlayer.shared.play("horr")
            Haptics.explode()
            if m?.loser == me { Flashlight.strobe() }
        default: break
        }
    }

    private func submit(_ raw: String) {
        guard let m, m.phase == .playing else { return }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // 보낼 필요 없는 건 여기서 거른다(방장 왕복 없이 바로 흔든다).
        guard WordDash.fits(t, m.prompt) else { reject(message(400)); return }
        if m.moves.contains(where: { $0.word == t }) { reject(message(409)); return }
        client.send(.marbleWord(t, target: target))
    }

    /// 내가 친 단어가 들어가면 성공음, 남이 나에게 공을 넣으면 짧은 경고.
    private func feedback() {
        guard let m, let mv = m.moves.last, let me else { return }
        if mv.player == me {
            errorText = nil
            SoundPlayer.shared.play("success")
            Haptics.accepted()
        } else if mv.target == me {
            SoundPlayer.shared.play("fail")
            Haptics.rejected()
        } else {
            SoundPlayer.shared.play("k")
        }
    }

    private func message(_ code: Int) -> String {
        switch code {
        case 400: return m?.prompt.isInitials == true ? "초성이 달라요" : "첫 글자가 달라요"
        case 409: return "이미 나온 단어예요"
        case 431: return "내 공이 하나뿐이라 더 못 빼요"
        case 432: return "공이 가득 찼어요"
        case 433: return "시간이 끝났어요"
        default: return GameView.errorMessages[code] ?? "오류 \(code)"
        }
    }

    private func reject(_ text: String) {
        Haptics.rejected()
        SoundPlayer.shared.play("fail")
        withAnimation(.default) { shake += 1 }
        errorText = text
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if errorText == text { errorText = nil }
        }
    }

    /// 마지막 5초는 1초마다 진동.
    private func lastSecondsTicks() async {
        while !Task.isCancelled, playing {
            let left = client.marbleDeadline.timeIntervalSinceNow
            if left <= 0 { return }
            if left <= 5.05 { Haptics.tick() }
            try? await Task.sleep(for: .seconds(min(1, left)))
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

private extension WordDash.Prompt {
    var isInitials: Bool { if case .initials = self { return true } else { return false } }
    var initialsLabel: String { isInitials ? "초성" : "첫 글자" }
}
