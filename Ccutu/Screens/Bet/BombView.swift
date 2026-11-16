import SwiftUI
import KkutuCore

/// 내기 게임: 끝말잇기 폭탄 돌리기. 폰 한 대를 손에서 손으로 넘기며 잇다가, 터질 때 들고 있던 사람이 진다.
/// 도화선 길이는 무작위이고 보여 주지 않는다. 초침 진동·배경음·고리 색만 점점 급해진다.
struct BombView: View {
    let dictionary: WordIndex
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case ready, live, exploded }
    @State private var phase: Phase = .ready
    @State private var round: BombRound?
    // 도화선은 "탄 시간"으로 잰다. 틀릴 때마다 타는 속도(fuseRate)가 올라가고, 바뀐 순간(fuseMark)까지 탄 만큼을 쌓아 둔다.
    @State private var fuseMark = Date()
    @State private var burnedAtMark: TimeInterval = 0
    @State private var fuseRate: Double = 1
    @State private var wrongs = 0
    @State private var bgmLevel = 0
    @State private var fuseLength: TimeInterval = 30
    @State private var fuse: Task<Void, Never>?
    @State private var input = ""
    @State private var focused = false
    @State private var field = WordFieldProxy()
    @State private var shake = 0
    @State private var errorText: String?
    @State private var passCue = 0            // 넘길 때마다 +1, "넘겨!"를 잠깐 띄운다
    @State private var showPass = false
    @State private var flashRed = false
    @State private var hint: String?
    @State private var drawing = false
    @State private var stake = PenaltyStore.stake

    static let fuseRange: ClosedRange<TimeInterval> = 25...50
    static let speedUpPerWrong = 0.25, maxRate = 3.0

    private func burned(_ d: Date) -> TimeInterval { burnedAtMark + d.timeIntervalSince(fuseMark) * fuseRate }

    var body: some View {
        ZStack {
            (flashRed ? Theme.danger : Theme.ground).ignoresSafeArea()
            switch phase {
            case .ready: readyView
            case .live: liveView
            case .exploded: explodedView
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { fuse?.cancel(); SoundPlayer.shared.stopAll() }
        .sheet(isPresented: $drawing) { PenaltyDrawView(items: stake) }
    }

    // MARK: 화면

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                .frame(width: 32, height: 32).background(Circle().fill(Theme.card))
        }
        .accessibilityLabel("나가기")
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 22) {
            closeButton
            Spacer()
            Image(systemName: "flame.fill").font(.system(size: 56)).foregroundStyle(Theme.danger)
            Text("폭탄 돌리기").font(Theme.display(48)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 10) {
                rule("1", "화면의 글자로 이어지는 단어를 치면 폭탄이 넘어가요.")
                rule("2", "폰을 바로 옆 사람에게 넘기세요.")
                rule("3", "언제 터질지는 아무도 몰라요. 터질 때 들고 있던 사람이 벌칙!")
            }
            Spacer()
            StakeRow(stake: stake) { stake = $0 }
            Button("시작") { start() }.buttonStyle(BigButtonStyle(fontSize: 28))
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func rule(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(n).font(Theme.display(18)).foregroundStyle(Theme.accent)
            Text(text).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
        }
    }

    private var liveView: some View {
        VStack(spacing: 14) {
            VStack(spacing: 14) {
                HStack {
                    closeButton
                    Spacer()
                    if fuseRate > 1 {
                        Label("×\(fuseRate, format: .number.precision(.fractionLength(0...2)))", systemImage: "hare.fill")
                            .font(.system(size: 14, weight: .heavy)).monospacedDigit().foregroundStyle(Theme.danger)
                            .padding(.horizontal, 12).frame(height: 32).background(Capsule().fill(Theme.dangerBG))
                            .accessibilityLabel("도화선 \(fuseRate, format: .number.precision(.fractionLength(0...2)))배 빠르게 타는 중")
                    }
                    Text("넘긴 횟수 \(round?.chain.count ?? 0)")
                        .font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.muted)
                        .padding(.horizontal, 12).frame(height: 32).background(Capsule().fill(Theme.card))
                }
                Spacer(minLength: 0)
                bomb
                if let last = round?.chain.last {
                    Text("방금: \(last)").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = false }
            inputArea
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// 맥박이 점점 빨라지는 폭탄. 빠르기는 남은 시간이 아니라 지난 시간 비율로만 정해서 끝을 짐작하기 어렵게 한다.
    private var bomb: some View {
        TimelineView(.animation) { ctx in
            let t = burned(ctx.date)                                       // 빨라지면 박동도 같이 빨라진다
            let p = min(1, t / fuseLength)
            // 초당 박동 1.2 → 7.2. 박동 위상은 그 적분(1.2t + 3t²/L)이라 끊기지 않는다.
            let phaseAngle = 2 * Double.pi * (1.2 * t + 3 * t * t / fuseLength)
            let beat = (sin(phaseAngle) + 1) / 2
            let size: CGFloat = focused ? 170 : 230
            ZStack {
                Circle().fill(ringColor(p)).opacity(0.22 + 0.2 * beat)
                    .frame(width: size + 40, height: size + 40)
                    .scaleEffect(1 + 0.06 * beat)
                Circle().fill(Theme.card).frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(ringColor(p), lineWidth: 4))
                VStack(spacing: 2) {
                    Text("이을 글자").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(round?.char ?? "").font(Theme.display(focused ? 72 : 96)).foregroundStyle(Theme.accent)
                        if let sub = round?.subChar { Text("(\(sub))").font(Theme.display(28)).foregroundStyle(Theme.muted) }
                    }
                }
                if showPass {
                    Text("넘겨!").font(Theme.display(56)).foregroundStyle(Theme.success)
                        .padding(.horizontal, 24).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.successBG))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: focused)
        }
    }

    private func ringColor(_ p: Double) -> Color { p < 0.5 ? Theme.accent : p < 0.8 ? Theme.mission : Theme.danger }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.danger)
                    .padding(.leading, 8)
            }
            HStack(spacing: 10) {
                WordField(text: $input, focused: $focused, placeholder: "단어 입력", proxy: field, onSubmit: submit)
                    .padding(.horizontal, 20)
                    .frame(height: 60)
                    .background(Capsule().fill(Theme.card))
                    .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 2))
                    .modifier(ShakeEffect(shakes: CGFloat(shake)))
                    .onTapGesture { focused = true }
                Button { field.submit() } label: {
                    Image(systemName: "arrow.right").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.onAccent)
                        .frame(width: 60, height: 60)
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

    private var explodedView: some View {
        VStack(spacing: 18) {
            HStack { closeButton; Spacer() }
            Spacer()
            Text("펑!").font(Theme.display(110)).foregroundStyle(Theme.danger)
            Text("폭탄을 들고 있던 사람이 졌어요").font(Theme.display(22)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            VStack(spacing: 6) {
                Text("넘긴 횟수 \(round?.chain.count ?? 0)번 · 마지막 글자 '\(round?.char ?? "")'")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                if let hint {
                    Text("이을 수 있던 단어: \(hint)").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            Spacer()
            if stake.count == 1 {
                Text("벌칙: \(stake[0])").font(Theme.display(28)).foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 64)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Theme.card))
            } else {
                Button { drawing = true } label: { Label("벌칙 뽑기", systemImage: "die.face.5") }
                    .buttonStyle(BigButtonStyle())
            }
            Button("한 판 더") { start() }.buttonStyle(BigButtonStyle(kind: .outlined))
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: 진행

    private func start() {
        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        round = BombRound(start: BombRound.randomStart(dictionary: dictionary, rng: &rng), dictionary: dictionary)
        fuseLength = .random(in: Self.fuseRange)
        fuseMark = Date(); burnedAtMark = 0; fuseRate = 1; wrongs = 0
        hint = nil; errorText = nil; input = ""
        phase = .live
        focused = true
        SoundPlayer.shared.play("game_start")
        bgmLevel = 0
        SoundPlayer.shared.playTurnSound(speed: 0, loop: true)
        fuse?.cancel()
        fuse = Task {
            while !Task.isCancelled {
                let b = burned(Date())
                if b >= fuseLength { explode(); return }
                let p = b / fuseLength
                updateMusic(p)
                Haptics.tick()
                // 초침 0.9초 → 0.15초(탄 시간 기준). 터질 시각을 넘겨 자지 않는다.
                let tick = (0.9 - 0.75 * p) / fuseRate, left = (fuseLength - b) / fuseRate
                try? await Task.sleep(for: .seconds(min(tick, left)))
            }
        }
    }

    /// 배경음은 반복 재생하고, 도화선이 탄 정도와 틀린 횟수만큼 끄투의 더 빠른 턴 곡으로 바꾼다.
    private func updateMusic(_ p: Double) {
        let level = min(10, Int(p * 11) + wrongs)
        guard level != bgmLevel else { return }
        bgmLevel = level
        SoundPlayer.shared.playTurnSound(speed: level, loop: true)
    }

    /// 틀렸다: 지금까지 탄 만큼을 묶어 두고 타는 속도를 올린다.
    private func speedUp() {
        let now = Date()
        burnedAtMark = burned(now)
        fuseMark = now
        wrongs += 1
        fuseRate = min(Self.maxRate, 1 + Self.speedUpPerWrong * Double(wrongs))
        updateMusic(burnedAtMark / fuseLength)
    }

    private func submit(_ raw: String) {
        guard phase == .live, var r = round else { return }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        switch r.submit(t) {
        case .accepted:
            round = r
            errorText = nil
            SoundPlayer.shared.play("success")
            SoundPlayer.shared.playTurnSound(speed: bgmLevel, loop: true)   // 넘길 때마다 턴 곡을 처음부터
            Haptics.accepted()
            passCue += 1
            let cue = passCue
            withAnimation(.spring(duration: 0.25)) { showPass = true }
            Task {
                try? await Task.sleep(for: .seconds(0.7))
                if passCue == cue { withAnimation { showPass = false } }
            }
        case .rejected(let code):
            reject(GameView.errorMessages[code] ?? "오류 \(code)")
        case .notChainable:
            reject(nil)
        }
    }

    private func reject(_ message: String?) {
        speedUp()
        Haptics.rejected()
        SoundPlayer.shared.play("fail")
        withAnimation(.default) { shake += 1 }
        guard let message else { return }
        errorText = message
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if errorText == message { errorText = nil }
        }
    }

    private func explode() {
        guard phase == .live else { return }
        fuse?.cancel()
        phase = .exploded
        focused = false
        showPass = false
        SoundPlayer.shared.stopTurnSound()
        SoundPlayer.shared.play("boom")                // 실제 폭약 녹음(CC0)
        Haptics.explode()
        Flashlight.strobe()
        if let r = round, let c = r.char.first {
            hint = dictionary.candidates(first: c, sub: r.subChar?.first, options: RoomOptions(), excluding: Set(r.chain))
                .randomElement()?.text
        }
        Task {
            for i in 0..<6 {
                flashRed = i % 2 == 0
                try? await Task.sleep(for: .milliseconds(90))
            }
            flashRed = false
        }
    }
}
