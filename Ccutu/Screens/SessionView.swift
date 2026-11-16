import SwiftUI
import KkutuCore

/// 방 상태에 따라 방/게임/결과 화면을 고른다. 연결 상태(방장 이탈·입장 실패·연결 중)는 여기서 그린다.
struct SessionView: View {
    let client: RoomClient
    var body: some View {
        Group {
            if client.disconnected {
                statusScreen(symbol: "wifi.slash", title: "연결이 끊겼습니다", description: client.connectionError ?? "방을 계속 진행할 수 없습니다.") {
                    Button("홈으로") { client.onLeave() }.buttonStyle(BigButtonStyle(kind: .outlined))
                }
            } else if client.room == nil && (client.connectFailed || client.errorCode == 429) {
                statusScreen(symbol: "wifi.exclamationmark", title: "방에 들어가지 못했습니다",
                             description: client.errorCode == 429 ? "방이 꽉 찼습니다." : client.connectionError ?? "연결 시간이 초과되었습니다. 방 상태를 확인한 뒤 다시 시도해 주세요.") {
                    Button("홈으로") { client.leave() }.buttonStyle(BigButtonStyle(kind: .outlined))
                }
            } else if client.room == nil {
                statusScreen(symbol: nil, title: "연결 중…", description: nil) {
                    Button { client.leave() } label: {
                        Text("취소").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
            } else if client.snapshot?.phase == .ended {
                ResultView(client: client)
            } else if client.room?.gaming == true, client.room?.settings.marble != nil {
                MarbleGameView(client: client)
            } else if client.room?.gaming == true {
                GameView(client: client)
            } else {
                RoomView(client: client)
            }
        }
        .overlay { if client.migratingFrom != nil && !client.disconnected { migrationOverlay } }
        .alert("방에서 나갈까요?", isPresented: Bindable(client).askingLeave) {
            Button("나가기", role: .destructive) { client.leaveNow() }
            Button("계속 있기", role: .cancel) {}
        } message: {
            Text("나가면 앱을 완전히 껐다 다시 켜야 인터넷 대전을 다시 할 수 있어요. 이 방에 있으면 계속 이어서 할 수 있어요.")
        }
        // 대기실·연결 화면은 로비 음악, 게임 중엔 끈다(끝말잇기는 턴 음악, 마블 룰렛은 경주 때 자기 음악).
        .onChange(of: client.room?.gaming == true, initial: true) { _, gaming in
            SoundPlayer.shared.bgm(gaming ? nil : "bgm_lobby")
        }
    }

    /// 방장이 나가 새 방장에게 다시 붙는 동안 지금 화면 위에 덮는다. 입력은 막는다.
    private var migrationOverlay: some View {
        let next = client.room.flatMap { r in r.players.first { !$0.isRobot && $0.id != client.migratingFrom } }
        return ZStack {
            Theme.ground.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView().tint(Theme.muted).controlSize(.large)
                Text("방장이 바뀌는 중…").font(Theme.display(24)).foregroundStyle(Theme.ink)
                if let next {
                    Text(next.id == client.myID ? "내가 새 방장이 됩니다" : "새 방장: \(next.name)")
                        .font(.system(size: 15)).foregroundStyle(Theme.muted)
                }
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 28).fill(Theme.card))
        }
        .contentShape(Rectangle())
        .transition(.opacity)
    }

    /// 연결 상태 화면 공통 틀: 심볼(없으면 진행 표시) → 제목 → 설명 → 버튼.
    private func statusScreen<B: View>(symbol: String?, title: String, description: String?, @ViewBuilder button: () -> B) -> some View {
        ZStack(alignment: .topLeading) {
            Theme.ground.ignoresSafeArea()
            Stripe(color: Theme.raised, width: 260).offset(x: -40, y: 90)
            Stripe(color: Theme.card, width: 220).offset(x: 230, y: 50)
            VStack(spacing: 12) {
                Spacer()
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(Theme.muted)
                } else {
                    ProgressView().tint(Theme.muted).controlSize(.large)
                }
                Text(title).font(Theme.display(24)).foregroundStyle(Theme.ink)
                if let description {
                    Text(description).font(.system(size: 15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                Spacer()
                button().padding(.top, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
    }
}
