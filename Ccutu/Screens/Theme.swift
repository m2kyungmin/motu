import SwiftUI
import KkutuCore

/// 디자인 시안(다크 한 팔레트)의 토큰과 화면들이 같이 쓰는 작은 조각.
enum Theme {
    static let ground = Color(hex: 0x141A2E)
    static let card = Color(hex: 0x1E2742)
    static let raised = Color(hex: 0x273253)
    static let ink = Color.white
    static let muted = Color(hex: 0xA9B3D1)
    static let dim = Color(hex: 0x6F7BA0)
    static let accent = Color(hex: 0xFFD23F)
    static let onAccent = Color(hex: 0x1B1500)
    static let accentShadow = Color(hex: 0xC9A000)
    static let blue = Color(hex: 0x4D8DFF)
    static let success = Color(hex: 0x3DE0A0)
    static let danger = Color(hex: 0xFF6B6B)
    static let mission = Color(hex: 0xFF9F43)
    // 시안의 배경 틴트(뱃지·칩 바탕)
    static let successBG = Color(hex: 0x163D33)
    static let dangerBG = Color(hex: 0x3A1F2B)
    static let missionBG = Color(hex: 0x3A2A14)
    static let turnBG = Color(hex: 0x2A2A1C)

    /// 제시 글자·점수·제목·큰 버튼용. 번들 폰트가 없으면 시스템 black으로 떨어진다.
    static func display(_ size: CGFloat) -> Font { .custom("BlackHanSans-Regular", size: size) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// 홈과 사전 준비 화면에서 같은 워드마크를 쓴다.
struct AppWordmark: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Text("모투").font(Theme.display(84)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Theme.accent).frame(width: 72, height: 12)
                Capsule().fill(Theme.blue).frame(width: 48, height: 12)
                Capsule().fill(Theme.danger).frame(width: 26, height: 12)
            }
            .padding(.bottom, 18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("모투")
    }
}

/// 노랑·파랑·빨강 채움 큰 버튼(아래 단색 그림자) / 파랑 테두리 큰 버튼.
struct BigButtonStyle: ButtonStyle {
    enum Kind { case filled, outlined, blue, red }
    var kind: Kind = .filled
    var height: CGFloat = 64
    var fontSize: CGFloat = 26
    var cornerRadius: CGFloat? = nil
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill = kind == .red ? Theme.danger : kind == .blue ? Theme.blue : Theme.accent
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? height / 2)
        return configuration.label
            .font(Theme.display(fontSize))
            .tracking(1)
            .foregroundStyle(kind == .outlined ? Theme.blue : Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background {
                if kind != .outlined {
                    ZStack {
                        shape.fill(kind == .filled ? Theme.accentShadow : fill)
                            .brightness(kind == .filled ? 0 : -0.2)
                            .offset(y: pressed ? 2 : 6)
                        shape.fill(fill)
                    }
                } else {
                    shape.strokeBorder(Theme.blue, lineWidth: 3)
                }
            }
            .offset(y: kind != .outlined && pressed ? 4 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(shape)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, down in down }   // 누르는 순간 톡
    }
}

/// 원작 끄투의 기본 모레미. 몸·눈·입은 같은 120×120 캔버스의 원본 레이어다.
struct Avatar: View {
    let name: String
    let isRobot: Bool
    var tint: Color = Theme.blue
    var size: CGFloat = 38
    var appearance: CharacterAppearance? = nil

    var body: some View {
        let outfit = appearance?.sanitized ?? CharacterAppearance()
        ZStack {
            Image(isRobot ? "MoremiRobot" : "MoremiBody").resizable().interpolation(.none)
            Image(CosmeticCatalog.item(outfit.eyes)?.assetName ?? "MoremiEyes").resizable().interpolation(.none)
            Image(CosmeticCatalog.item(outfit.mouth)?.assetName ?? "MoremiMouth").resizable().interpolation(.none)
            if let head = CosmeticCatalog.item(outfit.head) {
                Image(head.assetName).resizable().interpolation(.none)
            }
        }
        .padding(size * 0.04)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum TeamPalette {
    static func name(_ team: Int) -> String {
        switch team { case 1: return "빨강 팀"; case 2: return "파랑 팀"; case 3: return "초록 팀"; default: return "노랑 팀" }
    }
    static func color(_ team: Int) -> Color {
        switch team { case 1: return Theme.danger; case 2: return Theme.blue; case 3: return Theme.success; default: return Theme.accent }
    }
}

/// 배경 장식: -12도로 기운 캡슐 띠.
struct Stripe: View {
    let color: Color
    var width: CGFloat = 260
    var height: CGFloat = 26
    var body: some View {
        Capsule().fill(color).frame(width: width, height: height).rotationEffect(.degrees(-12))
    }
}

/// 노랑(켜짐) / raised(꺼짐) 캡슐 칩.
struct Chip: View {
    let title: String
    let on: Bool
    var height: CGFloat = 36
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(on ? Theme.onAccent : Theme.muted)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(Capsule().fill(on ? Theme.accent : Theme.raised))
    }
}

/// 섹션 머리글(작고 굵은 muted, 자간 1).
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13, weight: .bold)).tracking(1).foregroundStyle(Theme.muted)
    }
}
