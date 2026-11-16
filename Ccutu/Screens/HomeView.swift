import SwiftUI
import KkutuCore

struct HomeView: View {
    @Environment(SessionCoordinator.self) private var co
    @State private var robotLevel = 2
    @State private var browsing = false
    @State private var matchMode: MatchMode = .individual
    @State private var bombing = false
    @State private var practicing = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Theme.ground.ignoresSafeArea()
                Stripe(color: Theme.raised, width: 260).offset(x: -40, y: 90)
                Stripe(color: Theme.card, width: 220).offset(x: 230, y: 50)

                ViewThatFits(in: .vertical) {
                    homeContent(compact: false)
                    homeContent(compact: true)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $browsing) { BrowseView(mode: matchMode) }
            .sheet(isPresented: $practicing) {
                PracticeSheet(robotLevel: $robotLevel)
            }
            .fullScreenCover(isPresented: $bombing) { if let d = co.dictionary { BombView(dictionary: d) } }
        }
        .preferredColorScheme(.dark)
        .onAppear { SoundPlayer.shared.bgm("bgm_lobby") }
        .onChange(of: bombing) { _, on in SoundPlayer.shared.bgm(on ? nil : "bgm_lobby") }   // 폭탄은 자기 턴 음악을 튼다
    }

    private func homeContent(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 20) {
            AppWordmark()
            VStack(alignment: .leading, spacing: 10) {
                homeSectionTitle("게임 모드")
                HStack(spacing: 10) {
                    Button { matchMode = .individual; browsing = true } label: {
                        modeLabel("개인전", symbol: "person.fill")
                    }
                    .buttonStyle(BigButtonStyle(height: 104, fontSize: 20, cornerRadius: 22))
                    Button { matchMode = .team; browsing = true } label: {
                        modeLabel("팀전", symbol: "person.2.fill")
                    }
                    .buttonStyle(BigButtonStyle(kind: .blue, height: 104, fontSize: 20, cornerRadius: 22))
                    Button { practicing = true } label: { modeLabel("연습전", symbol: "cpu") }
                        .buttonStyle(BigButtonStyle(kind: .red, height: 104, fontSize: 20, cornerRadius: 22))
                }
            }
            betSection(compact: compact)
        }
    }

    private func homeSectionTitle(_ title: String) -> some View {
        Text(title).font(Theme.display(22)).foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func modeLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 24, weight: .bold))
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    /// 끝말잇기로 내기·벌칙을 하는 짧은 게임들. 폰 한 대로 둘러앉아 한다.
    private func betSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            homeSectionTitle("내기 게임")
            Button { bombing = true } label: {
                betCard(symbol: "flame.fill", tint: Theme.danger, title: "폭탄 돌리기",
                        line: "폰 하나를 돌려 가며 잇다가, 터질 때 든 사람이 벌칙", compact: compact)
            }
            Button { co.createRoom(marble: true) } label: {
                betCard(symbol: "circle.hexagongrid.fill", tint: Theme.blue, title: "마블 룰렛",
                        line: "단어로 공을 빼고 넣은 뒤, 남은 공을 굴려 벌칙", compact: compact)
            }
        }
    }

    private func betCard(symbol: String, tint: Color, title: String, line: String, compact: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(tint)
                .frame(width: 48, height: 48).background(Circle().fill(Theme.raised))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.display(22)).foregroundStyle(Theme.ink)
                if !compact {
                    Text(line).font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.dim)
        }
        .padding(compact ? 12 : 16)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.card))
    }

}

private struct PracticeSheet: View {
    @Environment(SessionCoordinator.self) private var co
    @Environment(\.dismiss) private var dismiss
    @Binding var robotLevel: Int

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("연습전").font(Theme.display(26))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.raised))
                }
                .accessibilityLabel("닫기")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "난이도")
                        HStack(spacing: 8) {
                            ForEach(0..<Robot.levelNames.count) { level in
                                Button { robotLevel = level } label: {
                                    Text(Robot.levelName(level))
                                        .font(.system(size: 14, weight: .bold))
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                        .foregroundStyle(level == robotLevel ? Theme.onAccent : Theme.muted)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(Capsule().fill(level == robotLevel ? Theme.accent : Theme.raised))
                                }
                                .accessibilityLabel("\(Robot.levelName(level)) 난이도")
                                .accessibilityAddTraits(level == robotLevel ? .isSelected : [])
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "특수 규칙")
                        OptionChips(options: Bindable(co).practiceOptions)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Button("\(Robot.levelName(robotLevel)) 로봇과 시작") {
                dismiss()
                co.startPractice(level: robotLevel)
            }
            .buttonStyle(BigButtonStyle(kind: .red, height: 56, fontSize: 22))
            .disabled(co.dictionary == nil)
        }
        .foregroundStyle(Theme.ink)
        .padding(24)
        .background(Theme.ground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: robotLevel)
        .sensoryFeedback(.selection, trigger: co.practiceOptions)
    }
}
