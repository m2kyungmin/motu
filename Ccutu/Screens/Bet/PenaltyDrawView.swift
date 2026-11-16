import SwiftUI

/// 내기 게임 공통 벌칙. 뽑기 목록과 "하나로 정해 둔 벌칙"이 이 기기에 남는다.
enum PenaltyStore {
    static let defaults = [
        "딱밤 한 대", "애교 한 번", "노래 한 소절", "다음 음료 쏘기",
        "성대모사 하나", "칭찬 세 개 하기", "10초 동안 웃지 않기", "이긴 사람 소원 하나",
    ]
    private static let key = "penalties", fixedKey = "penalty.fixed"

    static var list: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? defaults }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// 하나로 정해 둔 벌칙. nil이면 끝나고 목록에서 뽑는다.
    static var fixed: String? {
        get { UserDefaults.standard.string(forKey: fixedKey) }
        set { UserDefaults.standard.set(newValue, forKey: fixedKey) }
    }

    /// 이번 판에 걸 것: 정해 둔 하나, 아니면 뽑기 목록 전체.
    static var stake: [String] {
        if let f = fixed, !f.isEmpty { return [f] }
        return list.isEmpty ? defaults : list
    }

    static func summary(_ stake: [String]) -> String {
        stake.count == 1 ? stake[0] : "\(stake.count)개 중에서 뽑기"
    }
}

/// 시작 전 화면에 두는 "걸린 벌칙" 줄. 누르면(고칠 수 있을 때) 정하는 시트가 뜬다.
struct StakeRow: View {
    let stake: [String]
    var editable = true
    var onChange: ([String]) -> Void = { _ in }
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill").foregroundStyle(Theme.danger)
                Text("벌칙·내기").foregroundStyle(Theme.muted)
                Text(PenaltyStore.summary(stake)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: 0)
                if editable { Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.dim) }
            }
            .font(.system(size: 15, weight: .bold))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        }
        .disabled(!editable)
        .accessibilityLabel("벌칙·내기, \(PenaltyStore.summary(stake))")
        .sheet(isPresented: $editing) { StakeSheet { onChange($0) } }
    }
}

/// 벌칙 정하기: 하나로 정해 두거나, 끝나고 뽑을 목록을 고친다.
struct StakeSheet: View {
    var onDone: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PenaltyStore.fixed == nil
    @State private var fixed = PenaltyStore.fixed ?? ""
    @State private var items = PenaltyStore.list
    @State private var newItem = ""

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("벌칙·내기 정하기").font(Theme.display(26)).foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    Button { drawing = false } label: { Chip(title: "하나로 정하기", on: !drawing) }
                    Button { drawing = true } label: { Chip(title: "끝나고 뽑기", on: drawing) }
                }
                if drawing { poolEditor } else { fixedPicker }
                Button("다 됐어요") { done() }.buttonStyle(BigButtonStyle())
                    .disabled(drawing ? items.isEmpty : fixed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }

    private var fixedPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: $fixed, prompt: Text("직접 쓰기 (예: 커피 쏘기)").foregroundStyle(Theme.dim))
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 18).frame(height: 54)
                .background(Capsule().fill(Theme.card))
            SectionLabel(text: "목록에서 고르기")
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        Button { fixed = item } label: {
                            HStack {
                                Text(item).foregroundStyle(Theme.ink)
                                Spacer()
                                if fixed == item { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                            .font(.system(size: 16, weight: .bold))
                            .padding(.horizontal, 16).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                        }
                    }
                }
            }
        }
    }

    private var poolEditor: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        HStack {
                            Text(item).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Button { items.remove(at: i) } label: {
                                Image(systemName: "minus").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.danger)
                                    .frame(width: 34, height: 34).background(Circle().fill(Theme.dangerBG))
                            }
                            .accessibilityLabel("\(item) 지우기")
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                    }
                }
            }
            HStack(spacing: 10) {
                TextField("", text: $newItem, prompt: Text("벌칙 추가").foregroundStyle(Theme.dim))
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18).frame(height: 50)
                    .background(Capsule().fill(Theme.card))
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus").font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.onAccent)
                        .frame(width: 50, height: 50).background(Circle().fill(Theme.accent))
                }
                .accessibilityLabel("추가")
            }
            Button("기본 벌칙으로") { items = PenaltyStore.defaults }
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.dim)
        }
    }

    private func add() {
        let t = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.append(String(t.prefix(30)))
        newItem = ""
    }

    private func done() {
        PenaltyStore.list = items
        let f = String(fixed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        PenaltyStore.fixed = drawing || f.isEmpty ? nil : f
        onDone(PenaltyStore.stake)
        dismiss()
    }
}

/// 벌칙 원판 룰렛: result가 오면 몇 바퀴 돌다 점점 느려져 그 칸에 멈춘다. 칸 경계를 지날 때마다 틱(소리·진동),
/// 마지막엔 다음 칸 경계 바로 앞까지 기어가다 선다. 회전량·시간이 결과 번호로만 정해져서
/// 마블 룰렛에선 방장이 정한 번호를 받은 모든 폰이 같은 모양으로 돈다.
struct PenaltyWheel: View {
    let items: [String]
    let result: Int?
    var size: CGFloat = 260
    @State private var angle: Double = 0          // 시계 방향 회전(도)
    @State private var spinning = false
    @State private var landed: Int?

    static let duration: TimeInterval = 6
    static let turns: Double = 5
    static let colors: [Color] = MarbleScene.palette.map { Color(uiColor: $0) }

    private var slice: Double { 360 / Double(max(1, items.count)) }

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .top) {
                wheel.rotationEffect(.degrees(angle))
                Image(systemName: "arrowtriangle.down.fill")       // 바늘
                    .font(.system(size: 28)).foregroundStyle(Theme.ink)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .offset(y: -12)
            }
            .frame(width: size, height: size)
            Text(landed.map { items[$0] } ?? (spinning ? "…" : "?"))
                .font(Theme.display(landed == nil ? 26 : 30))
                .foregroundStyle(landed == nil ? Theme.muted : Theme.accent)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .onAppear { if let result { spin(to: result) } }
        .onChange(of: result) { _, r in if let r { spin(to: r) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(landed.map { "벌칙: \(items[$0])" } ?? "벌칙 원판")
    }

    private var wheel: some View {
        let r = size / 2
        return ZStack {
            ForEach(items.indices, id: \.self) { i in
                Path { p in
                    let c = CGPoint(x: r, y: r)
                    p.move(to: c)
                    p.addArc(center: c, radius: r, startAngle: .degrees(-90 + Double(i) * slice),
                             endAngle: .degrees(-90 + Double(i + 1) * slice), clockwise: false)
                    p.closeSubpath()
                }
                .fill(Self.colors[i % Self.colors.count].opacity(landed == nil || landed == i ? 1 : 0.35))
                // 칸 이름: 반지름을 따라 테두리 쪽에 붙인다. 왼쪽 절반은 뒤집어 거꾸로 읽히지 않게.
                let mid = Double(i) * slice + slice / 2
                let right = mid < 180
                Text(items[i])
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(.black.opacity(0.8))
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: r * 0.7, alignment: right ? .trailing : .leading)
                    .offset(x: (right ? 1 : -1) * r * 0.56)
                    .rotationEffect(.degrees(right ? mid - 90 : mid + 90))
            }
            Circle().strokeBorder(Theme.ink.opacity(0.9), lineWidth: 4)
            Circle().fill(Theme.ground).frame(width: r * 0.22, height: r * 0.22)
        }
        .frame(width: size, height: size)
    }

    /// 바늘(위) 아래에 있는 칸. 원판이 시계 방향으로 θ만큼 돌면 바늘은 원판 기준 -θ 자리를 가리킨다.
    private func sliceIndex(_ theta: Double) -> Int {
        let phi = (360 - theta.truncatingRemainder(dividingBy: 360)).truncatingRemainder(dividingBy: 360)
        return min(items.count - 1, Int(phi / slice))
    }

    private func spin(to r: Int) {
        guard items.indices.contains(r), !spinning, landed == nil else { return }
        spinning = true
        // 바늘이 결과 칸을 지나가는 방향으로 거의 다 지난 자리(경계 직전)에 선다
        let stop = Double(r) * slice + 0.1 * slice
        let target = 360 * Self.turns + (360 - stop)
        let start = Date()
        Task {
            var last = sliceIndex(0)
            while true {
                let t = min(1, Date().timeIntervalSince(start) / Self.duration)
                angle = target * (1 - pow(1 - t, 4))            // 빠르게 시작해 끝에서 기어간다
                let i = sliceIndex(angle)
                if i != last {
                    last = i
                    Haptics.tick()
                    SoundPlayer.shared.play("k")
                }
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            spinning = false
            landed = r
            Haptics.accepted()
            SoundPlayer.shared.play("mission")
        }
    }
}

/// 한 폰으로 하는 내기(폭탄 돌리기)의 벌칙 뽑기 시트.
struct PenaltyDrawView: View {
    let items: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var result: Int?
    @State private var round = 0
    @State private var spinning = false

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Text("벌칙 뽑기").font(Theme.display(24)).foregroundStyle(Theme.ink)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                            .frame(width: 32, height: 32).background(Circle().fill(Theme.card))
                    }
                    .accessibilityLabel("닫기")
                }
                Spacer()
                PenaltyWheel(items: items, result: result, size: 300).id(round)
                Spacer()
                Button(result == nil ? "뽑기" : "다시 뽑기") {
                    round += 1
                    result = Int.random(in: 0..<max(1, items.count))
                    spinning = true
                    Task {
                        try? await Task.sleep(for: .seconds(PenaltyWheel.duration + 0.3))
                        spinning = false
                    }
                }
                .buttonStyle(BigButtonStyle())
                .disabled(items.isEmpty || spinning)              // 도는 중에 눌러 처음부터 다시 돌지 않게
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
    }
}
