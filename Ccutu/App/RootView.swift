import SwiftUI

struct RootView: View {
    @Environment(SessionCoordinator.self) private var co
    @State private var selectedTab = MainTab.play
    @State private var editingNickname = false
    @State private var requestNicknameFocus = false
    @State private var showingCredits = false
    var body: some View {
        Group {
            if co.dictionary == nil {
                DictionarySplashView()
            } else if let client = co.client {
                SessionView(client: client)
            } else {
                mainTabs
            }
        }
        .task { co.activateGameCenter() }
        .sheet(item: Bindable(co.gameCenter).presentation, onDismiss: { co.gameCenter.presentationDismissed() }) {
            GameCenterSheet(presentation: $0).ignoresSafeArea().interactiveDismissDisabled()
        }
        .alert("연결 안내", isPresented: Binding(
            get: { co.networkError != nil || co.gameCenter.errorMessage != nil },
            set: { if !$0 { co.networkError = nil; co.gameCenter.errorMessage = nil } }
        )) {
            Button("확인") { co.networkError = nil; co.gameCenter.errorMessage = nil }
        } message: { Text(co.networkError ?? co.gameCenter.errorMessage ?? "") }
        .confirmationDialog("초대받은 방으로 이동할까요?", isPresented: Binding(
            get: { co.pendingInvite != nil && co.dictionary != nil && co.client != nil },
            set: { if !$0 { co.pendingInvite = nil } }
        ), titleVisibility: .visible) {
            Button("현재 방에서 나가고 초대 수락") { co.acceptPendingInvite() }
            Button("취소", role: .cancel) { co.pendingInvite = nil }
        }
        .onChange(of: co.dictionary != nil) { _, ready in
            if ready && co.client == nil { co.acceptPendingInvite() }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label(MainTab.play.title, systemImage: MainTab.play.symbol) }
                .tag(MainTab.play)
                .toolbar(.hidden, for: .tabBar)
            CustomizationView(editingNickname: $editingNickname, requestNicknameFocus: $requestNicknameFocus)
                .tabItem { Label(MainTab.customization.title, systemImage: MainTab.customization.symbol) }
                .tag(MainTab.customization)
                .toolbar(.hidden, for: .tabBar)
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selectedTab == .play && !editingNickname {
                VStack(spacing: 10) {
                    if co.shouldSuggestNickname { nicknamePrompt }
                    credits
                    tabBar
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
                .background(Theme.ground.ignoresSafeArea(edges: .bottom))
            }
        }
        .overlay(alignment: .bottom) {
            if selectedTab == .customization && !editingNickname {
                tabBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showingCredits) { CreditsView() }
    }

    private var credits: some View {
        Button { showingCredits = true } label: {
            HStack(spacing: 6) {
                Text("원작 KKuTu · JJoriping")
                Text("·")
                Text("크레딧")
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("원작 KKuTu, JJoriping. 크레딧 및 라이선스 보기")
    }

    private var nicknamePrompt: some View {
        Button {
            requestNicknameFocus = true
            selectedTab = .customization
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "pencil.line").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("닉네임을 바꿔 보세요").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                    Text("커스터마이징에서 나만의 이름을 정할 수 있어요")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.system(size: 21, weight: .bold))
                        Text(tab.title).font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(selectedTab == tab ? Theme.onAccent : Theme.muted)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 18).fill(selectedTab == tab ? Theme.accent : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.raised, lineWidth: 2))
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}

private enum MainTab: Hashable, CaseIterable {
    case play, customization
    var title: String { self == .play ? "플레이" : "커스터마이징" }
    var symbol: String { self == .play ? "gamecontroller.fill" : "tshirt.fill" }
}
