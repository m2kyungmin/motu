import SwiftUI
import KkutuCore

struct GameView: View {
    let client: RoomClient
    @Environment(SessionCoordinator.self) private var co
    @State private var input = ""
    @State private var errorText: String?
    @State private var shake = 0
    @State private var hint: String?
    @State private var floats: [PlayerID: String] = [:]     // "+17" / "-5" / "+18+17"
    @State private var bubbles: [PlayerID: RoomClient.ChatLine] = [:]   // 플레이어 카드의 말풍선
    @State private var wrongs: [PlayerID: WrongAnswer] = [:]            // 방금 틀린 단어(카드가 빨개진다)
    @State private var cardShakes: [PlayerID: Int] = [:]
    @State private var wrongSeq = 0
    @State private var focused = false
    @State private var field = WordFieldProxy()

    private var snap: GameSnapshot? { client.snapshot }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(spacing: compact ? 8 : 14) {
                VStack(spacing: compact ? 8 : 14) {
                    header
                    teamScoreboard
                    charDisplay
                    historyStrip
                    timerBars
                    playerList
                }
                .contentShape(Rectangle())
                .onTapGesture { focused = false }      // 입력줄 밖을 누르면 키보드를 내린다
                Spacer(minLength: 0)
                inputArea
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .onChange(of: client.eventSeq, initial: true) { _, _ in react(to: client.lastEvent) }   // 방장은 .starting을 GameView가 생기기 전에 받는다
        .onChange(of: client.isMyTurn) { _, mine in if mine { focused = true } }   // 내 차례면 올리기만 하고, 내리는 건 사용자가
        .onAppear { if client.isMyTurn { focused = true } }
        .onChange(of: client.lastChat) { _, line in showChat(line) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { client.leave() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                    .frame(width: 32, height: 32).background(Circle().fill(Theme.card))
            }
            .accessibilityLabel("나가기")
            Text("라운드 \(snap?.round ?? 0)").font(Theme.display(22)).foregroundStyle(Theme.ink)
            Text("/ \(snap?.totalRounds ?? 0)").font(.system(size: 14)).monospacedDigit().foregroundStyle(Theme.muted)
            Spacer()
            if let m = snap?.mission {
                Label("미션 \(m)", systemImage: "star.fill")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.mission)
                    .padding(.horizontal, 12).frame(height: 32).background(Capsule().fill(Theme.missionBG))
            }
            Text("체인 \(snap?.chain.count ?? 0)")
                .font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.muted)
                .padding(.horizontal, 12).frame(height: 32).background(Capsule().fill(Theme.card))
        }
    }

    /// 키보드가 떠 있으면 제시 글자 카드를 줄여 플레이어 카드가 보이게 한다.
    private var compact: Bool { focused }

    @ViewBuilder private var teamScoreboard: some View {
        if client.room?.settings.matchMode == .team, let snap {
            HStack(spacing: 8) {
                ForEach(snap.teamScores.keys.sorted(), id: \.self) { team in
                    let layout = compact ? AnyLayout(HStackLayout(spacing: 4)) : AnyLayout(VStackLayout(spacing: 4))
                    layout {
                        Text(TeamPalette.name(team)).font(.system(size: compact ? 10 : 11, weight: .bold))
                        Text("\(snap.teamScores[team, default: 0])").font(Theme.display(compact ? 16 : 22)).monospacedDigit()
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(TeamPalette.color(team))
                    .frame(maxWidth: .infinity).padding(.vertical, compact ? 6 : 10)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                }
            }
        }
    }

    private var charDisplay: some View {
        let size: CGFloat = compact ? 40 : 112      // 키보드 위에 가로 플레이어 줄과 단어 기록을 남긴다
        return VStack(spacing: 6) {
            Text(hint == nil ? "이을 글자" : "이을 수 있던 단어")
                .font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(Theme.muted)
            if let hint {
                (Text(hint.prefix(1)).foregroundStyle(Theme.accent) + Text(hint.dropFirst()).foregroundStyle(Theme.dim))
                    .font(Theme.display(size)).lineLimit(1).minimumScaleFactor(0.3)
                    .frame(height: size)
            } else if let s = snap {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(s.char).font(Theme.display(size)).foregroundStyle(Theme.accent)
                    if let sub = s.subChar { Text("(\(sub))").font(Theme.display(compact ? 24 : 40)).foregroundStyle(Theme.muted) }
                }
                .frame(height: size)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, compact ? 5 : 22).padding(.bottom, compact ? 5 : 18).padding(.horizontal, 16)
        .animation(.easeOut(duration: 0.2), value: compact)
        .background {
            ZStack {
                Theme.card
                Stripe(color: Theme.raised, width: 200, height: 18).offset(x: -110, y: -60)
                Stripe(color: Theme.raised, width: 180, height: 18).offset(x: 120, y: 60)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
        }
    }

    /// 끄투 단어 기록(pushHistory): 이어진 단어가 최신부터 왼쪽에 쌓이고, 칸마다 단어·품사 배지와 한 줄 설명.
    /// 사전은 기기마다 같아 각자 찾는다.
    private var historyStrip: some View {
        let words = Array((snap?.chain ?? []).suffix(10).reversed())
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if words.isEmpty {
                    Text("이은 단어가 여기에 쌓여요").font(.system(size: 12)).foregroundStyle(Theme.dim)
                        .padding(.horizontal, 12).frame(height: compact ? 32 : 44)
                }
                ForEach(Array(words.enumerated()), id: \.element) { i, w in
                    historyItem(w, latest: i == 0)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: words)
        }
        .frame(height: compact ? 32 : 44)
        .scrollDisabled(words.count < 3)
    }

    private func historyItem(_ word: String, latest: Bool) -> some View {
        let d = co.dictionary?.lookup(word).map(WordLabels.describe)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(word).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(latest ? Theme.ink : Theme.muted).lineLimit(1)
                ForEach(d?.classes ?? [], id: \.self) { c in
                    Text(c).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 4).frame(height: 15)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.blue))
                        .fixedSize()
                }
            }
            Text(detailLine(d)).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(width: 160, height: compact ? 32 : 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay { if latest { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.raised, lineWidth: 2) } }
    }

    /// 칸의 둘째 줄. 끄투는 여기에 뜻을 보이고 분야를 〈〉로 앞에 붙인다. 공개 사전에 뜻이 없어
    /// 지금은 분야만, 분야가 없으면 외래어·방언 같은 표시를 넣는다.
    private func detailLine(_ d: WordLabels.Description?) -> String {
        guard let d else { return "" }
        return d.themes.isEmpty ? d.marks.joined(separator: " · ") : WordLabels.themeLine(d.themes)
    }

    private var timerBars: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { ctx in
            let elapsed = Int(ctx.date.timeIntervalSince(client.turnReceivedAt) * 1000)
            let active = snap?.phase == .turn
            let turnTotal = max(1, snap?.turnTimeMs ?? 1)
            let roundTotal = max(1, (client.room?.settings.roundSeconds ?? 60) * 1000)
            let turnLeft = active ? max(0, turnTotal - elapsed) : 0
            let roundLeft = max(0, active ? (snap?.roundTimeMs ?? 0) - elapsed : (snap?.roundTimeMs ?? 0))
            let turnTint = active ? turnColor(Double(turnLeft) / Double(turnTotal)) : Theme.muted   // 턴 사이엔 빨간 0.0초 대신 흐리게
            VStack(spacing: compact ? 4 : 8) {
                bar(label: "턴", left: turnLeft, total: turnTotal, color: turnTint, height: 18) {
                    Text(seconds(turnLeft)).font(Theme.display(18)).foregroundStyle(turnTint)
                }
                bar(label: "라운드", left: roundLeft, total: roundTotal, color: roundLeft <= 5000 ? Theme.danger : Theme.blue, height: 10) {
                    Text(seconds(roundLeft)).font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func seconds(_ ms: Int) -> String { String(format: "%.1f초", Double(ms) / 1000) }

    private func bar<T: View>(label: String, left: Int, total: Int, color: Color, height: CGFloat, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted).frame(width: 48, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.raised)
                    Capsule().fill(color).frame(width: g.size.width * min(1, CGFloat(left) / CGFloat(total)))
                }
            }
            .frame(height: height)
            trailing().monospacedDigit().frame(width: 56, alignment: .trailing)
        }
    }

    private func turnColor(_ ratio: Double) -> Color { ratio > 0.5 ? Theme.success : ratio > 0.25 ? Theme.accent : Theme.danger }

    private var playerList: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(snap?.seats ?? [], id: \.id) { player in
                        playerCard(player).id(player.id)
                    }
                }
                .padding(2)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: snap?.phase == .turn ? snap?.currentPlayer?.id : nil, initial: true) { _, player in
                if let player {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(player, anchor: .center) }
                }
            }
            .onChange(of: focused) { _, typing in
                if typing, let player = snap?.currentPlayer?.id {
                    proxy.scrollTo(player, anchor: .center)
                }
            }
        }
        .frame(height: compact ? 114 : 130)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .animation(.easeOut(duration: 0.3), value: floats)
        .animation(.spring(duration: 0.25), value: bubbles)
        .animation(.easeOut(duration: 0.2), value: wrongs)
    }

    private func playerCard(_ player: Player) -> some View {
        let current = player.id == snap?.currentPlayer?.id && snap?.phase == .turn
        let mine = player.id == client.myID
        return VStack(spacing: compact ? 3 : 5) {
            HStack(spacing: 4) {
                Avatar(name: player.name, isRobot: player.isRobot, size: compact ? 32 : 40, appearance: player.appearance)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    if current {
                        Text(mine ? "내 차례" : "차례").foregroundStyle(Theme.accent)
                    }
                    if let team = player.team {
                        Text(TeamPalette.name(team)).foregroundStyle(TeamPalette.color(team))
                    }
                }
                .font(.system(size: 9, weight: .bold)).lineLimit(1)
            }
            Text(player.name).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Text("\(snap?.scores[player.id] ?? 0)").font(Theme.display(compact ? 20 : 22))
                    .foregroundStyle(mine ? Theme.ink : Theme.muted)
                Spacer(minLength: 0)
                if let value = floats[player.id] {
                    Text(value).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(value.hasPrefix("−") ? Theme.danger : value == "0" ? Theme.muted : Theme.success)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Group {
                if let wrong = wrongs[player.id] {
                    (Text(wrong.word).strikethrough() + Text(wrong.label.map { " · \($0)" } ?? ""))
                        .foregroundStyle(Theme.danger)
                } else if let line = bubbles[player.id] {
                    Text(line.text).foregroundStyle(Theme.ink)
                } else {
                    Text(" ")
                }
            }
            .font(.system(size: 10)).lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
        }
        .padding(8)
        .frame(width: 104, height: compact ? 110 : 126)
        .background(RoundedRectangle(cornerRadius: 18).fill(wrongs[player.id] != nil ? Theme.dangerBG : current ? Theme.turnBG : Theme.card))
        .overlay {
            if wrongs[player.id] != nil { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.danger, lineWidth: 2) }
            else if current { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accent, lineWidth: 2) }
        }
        .modifier(ShakeEffect(shakes: CGFloat(cardShakes[player.id] ?? 0)))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    @ViewBuilder private var inputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.danger)
                    .padding(.leading, 8)
            }
            HStack(spacing: 10) {
                WordField(text: $input, focused: $focused, placeholder: client.isMyTurn ? "단어 입력" : "채팅",
                          proxy: field, onSubmit: submit)
                    .padding(.horizontal, 20)
                    .frame(height: compact ? 52 : 60)
                    .background(Capsule().fill(Theme.card))
                    .overlay(Capsule().strokeBorder(client.isMyTurn ? Theme.accent : Theme.raised, lineWidth: 2))
                    .modifier(ShakeEffect(shakes: CGFloat(shake)))
                    .onTapGesture { focused = true }
                Button { field.submit() } label: {
                    let mine = client.isMyTurn
                    Image(systemName: "arrow.right").font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(mine ? Theme.onAccent : Theme.ink)
                        .frame(width: compact ? 52 : 60, height: compact ? 52 : 60)
                        .background {
                            ZStack {
                                Circle().fill(mine ? Theme.accentShadow : Color.clear).offset(y: 5)
                                Circle().fill(mine ? Theme.accent : Theme.raised)
                            }
                        }
                }
                .accessibilityLabel(client.isMyTurn ? "보내기" : "채팅 보내기")
            }
        }
    }

    private func submit(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // 끄투 classic.submit: 내 차례에 이을 수 있는 글만 답이 되고, 남의 차례 글이나 이을 수 없는 글은 채팅이 된다.
        if client.isMyTurn, let s = snap, GameEngine.isChainable(t, char: s.char, subChar: s.subChar) {
            client.send(.submit(t))
        } else {
            client.send(.chat(t))
        }
    }

    /// 끄투 chatBalloon: 2.5초 보이고 0.5초에 걸쳐 사라진다. 같은 사람이 다시 말하면 바꿔 단다.
    private func showChat(_ line: RoomClient.ChatLine?) {
        guard let line else { return }
        bubbles[line.player] = line
        SoundPlayer.shared.play("k")
        Task {
            try? await Task.sleep(for: .seconds(3))
            if bubbles[line.player]?.seq == line.seq { bubbles[line.player] = nil }
        }
    }

    private func react(to e: EngineEvent?) {
        guard let e else { return }
        let sound = SoundPlayer.shared
        switch e {
        case .starting:
            sound.play("game_start")
        case .roundReady:
            hint = nil
            sound.play("round_start")
        case .turnStart(_, let player, _, _, let speed, _, _, _):
            hint = nil
            errorText = nil
            sound.playTurnSound(speed: speed)
            if player == client.myID { Haptics.myTurn() }
        case .turnEnd(let player, let ok, _, let score, let bonus, let h):
            sound.stopTurnSound()
            if ok {
                sound.play("success")
                if player == client.myID { Haptics.accepted() }
                if bonus > 0 { sound.play("mission") }
                floats[player] = bonus > 0 ? "+\(score - bonus)+\(bonus)" : "+\(score)"
            } else {
                sound.play("timeout")
                if player == client.myID { Haptics.timedOut() }
                floats[player] = score < 0 ? "−\(-score)" : "\(score)"
                hint = h
            }
            Task { try? await Task.sleep(for: .seconds(1)); floats[player] = nil }
        case .turnError(let player, let code, let value):
            // 끄투 turnError: 모두에게 fail 소리와 함께 1.8초 보인다. 여기선 그 사람 카드를 흔들고 빨갛게.
            sound.play("fail")
            wrongSeq += 1
            let w = WrongAnswer(seq: wrongSeq, word: String(value.prefix(20)), label: Self.errorLabels[code])
            wrongs[player] = w
            withAnimation(.default) { cardShakes[player, default: 0] += 1 }
            Task { try? await Task.sleep(for: .seconds(1.8)); if wrongs[player]?.seq == w.seq { wrongs[player] = nil } }
            guard player == client.myID else { return }
            Haptics.rejected()
            errorText = Self.errorMessages[code] ?? "오류 \(code)"
            withAnimation(.default) { shake += 1 }
            Task { try? await Task.sleep(for: .seconds(1.5)); errorText = nil }
        case .gameEnd:
            sound.stopTurnSound()
        }
    }

    /// 남의 카드에 붙는 짧은 이유. 끄투 ko_KR turnError_* 그대로, 404는 끄투에 없어 따로 둔다.
    static let errorLabels: [Int: String] = [
        402: "첫 턴 한방 금지",
        403: "한방 단어",
        404: "사전에 없음",
        405: "외래어",
        406: "깐깐!",
        409: "이미 쓰인 단어",
    ]

    static let errorMessages: [Int: String] = [
        402: "한방 단어는 첫 번째 턴에 쓸 수 없습니다",
        403: "매너 모드: 이을 수 없는 단어입니다",
        404: "사전에 없는 단어입니다",
        405: "외래어는 쓸 수 없습니다",
        406: "표준어가 아닙니다",
        409: "이미 사용한 단어입니다",
    ]
}

/// 입력창 좌우 흔들기.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat               // Int면 보간값이 버려져 sin(정수·6π)=0, 즉 안 흔들린다
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 6), y: 0))
    }
}

/// 플레이어 카드 안 말풍선. 흰 캡슐에 어두운 글자, 한 줄.
struct ChatBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.ground)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(Theme.ink))
            .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
    }
}

struct WrongAnswer: Equatable {
    let seq: Int
    let word: String
    let label: String?
}
