import SwiftUI
import GameKit
import KkutuCore

struct GameCenterPresentation: Identifiable {
    let id = UUID()
    let controller: UIViewController
}

struct GameCenterSheet: UIViewControllerRepresentable {
    let presentation: GameCenterPresentation
    func makeUIViewController(context: Context) -> UIViewController { presentation.controller }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

/// 인증과 Apple의 초대 화면만 맡는다. 실제 게임 데이터는 GameCenterTransport가 운반한다.
@MainActor @Observable final class GameCenterService: NSObject, GKLocalPlayerListener, GKMatchmakerViewControllerDelegate {
    var presentation: GameCenterPresentation?
    var errorMessage: String?
    private(set) var authenticating = false
    private(set) var authenticated = false
    var onMatch: (GKMatch, MatchMode) -> Void = { _, _ in }
    var onInvite: (GKInvite) -> Void = { _ in }
    private var started = false
    private var pendingMode: MatchMode?
    private var pendingInvite: GKInvite?
    private var currentMode: MatchMode = .individual
    private var registered = false
    private var presentingAuthentication = false
    private var waitingForDismissal = false
    private var queuedPresentation: GameCenterPresentation?
    private var matchedThisLaunch = false
    static let individualGroup = 0x4D540201
    static let teamGroup = 0x4D540202

    /// iOS 27 GameKit은 끝난 실시간 대전의 연결을 치우지 않아, 같은 실행에서 두 번째 대전을 맺으면
    /// 15~20초 뒤 GameKitServices 안에서 튕긴다(FB24789094, developer.apple.com/forums/thread/845898).
    /// ponytail: 실행당 한 판으로 막는다. 애플이 고친 iOS가 나오면 그 버전부터 풀 것.
    /// 인터넷 방을 나갈 때 확인창도 이 조건을 쓴다.
    var oneMatchPerLaunch: Bool { if #available(iOS 27, *) { true } else { false } }

    /// 새 대전을 맺기 전에 부르고, 막혔으면 재시작 안내를 띄운 뒤 true를 돌려준다.
    func blocksAnotherMatch() -> Bool {
        guard oneMatchPerLaunch, matchedThisLaunch else { return false }
        errorMessage = "iOS 27의 Game Center 문제로 인터넷 대전은 앱을 켤 때마다 한 번만 열 수 있어요. 앱 전환 화면에서 모투를 위로 밀어 끈 뒤 다시 열어 주세요."
        return true
    }

    func activate() {
        guard !started else { return }
        started = true
        authenticating = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, error in
            Task { @MainActor in
                guard let self else { return }
                if let controller {
                    self.presentingAuthentication = true
                    self.show(controller)
                    self.authenticating = false
                    return
                }
                if self.presentingAuthentication {
                    self.presentingAuthentication = false
                    self.dismissPresentation()
                }
                self.authenticating = false
                self.authenticated = GKLocalPlayer.local.isAuthenticated
                if self.authenticated {
                    if !self.registered { GKLocalPlayer.local.register(self); self.registered = true }
                    if let invite = self.pendingInvite {
                        self.pendingInvite = nil
                        self.accept(invite)
                    } else if let mode = self.pendingMode {
                        self.pendingMode = nil
                        self.inviteFriends(mode: mode)
                    }
                } else if self.pendingMode != nil || self.pendingInvite != nil {
                    self.pendingMode = nil; self.pendingInvite = nil
                    self.errorMessage = error?.localizedDescription ?? "Game Center에 로그인한 뒤 다시 초대해 주세요."
                }
            }
        }
    }

    func inviteFriends(mode: MatchMode) {
        guard !blocksAnotherMatch() else { return }
        guard GKLocalPlayer.local.isAuthenticated else {
            pendingMode = mode
            if !started { activate() }
            else if !authenticating && presentation == nil {
                started = false; activate()
            }
            return
        }
        guard !GKLocalPlayer.local.isMultiplayerGamingRestricted else {
            errorMessage = "이 Game Center 계정은 멀티플레이가 제한되어 있습니다."
            return
        }
        presentInvite(mode: mode, maxPlayers: Self.matchCap, adding: nil)
    }

    /// 지금 방의 매치에 친구를 더 부른다. 새 매치가 아니므로 iOS 27 한 판 제한을 받지 않는다.
    /// Apple 안내대로 방장 한 기기에서만 부른다.
    func inviteMore(to match: GKMatch, mode: MatchMode, maxPlayers: Int) {
        presentInvite(mode: mode, maxPlayers: min(maxPlayers, Self.matchCap), adding: match)
    }

    static var matchCap: Int { min(8, GKMatchRequest.maxPlayersAllowedForMatch(of: .peerToPeer)) }

    private func presentInvite(mode: MatchMode, maxPlayers: Int, adding match: GKMatch?) {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = maxPlayers
        if match == nil { request.defaultNumberOfPlayers = 2 }
        request.playerGroup = mode == .team ? Self.teamGroup : Self.individualGroup
        request.inviteMessage = "모투에서 \(mode.title) 한 판!"
        guard let controller = GKMatchmakerViewController(matchRequest: request) else {
            errorMessage = "친구 초대 화면을 열지 못했습니다. 잠시 후 다시 시도해 주세요."
            return
        }
        currentMode = mode
        controller.matchmakerDelegate = self
        controller.matchmakingMode = .inviteOnly
        if let match { controller.addPlayers(to: match) }
        show(controller)
    }

    func accept(_ invite: GKInvite) {
        guard !blocksAnotherMatch() else { return }
        guard GKLocalPlayer.local.isAuthenticated else { pendingInvite = invite; activate(); return }
        guard invite.playerGroup == Self.individualGroup || invite.playerGroup == Self.teamGroup,
              let controller = GKMatchmakerViewController(invite: invite) else {
            errorMessage = "이 초대는 호환되지 않습니다. 친구와 같은 버전의 모투를 사용해 주세요."
            return
        }
        currentMode = invite.playerGroup == Self.teamGroup ? .team : .individual
        controller.matchmakerDelegate = self
        show(controller)
    }

    /// 인증 화면에서 초대 화면으로 넘어갈 때 SwiftUI의 dismiss 완료를 기다린다.
    private func show(_ controller: UIViewController) {
        let next = GameCenterPresentation(controller: controller)
        if presentation != nil || waitingForDismissal {
            queuedPresentation = next
            dismissPresentation()
        } else { presentation = next }
    }

    private func dismissPresentation() {
        waitingForDismissal = waitingForDismissal || presentation != nil
        presentation = nil
    }

    func presentationDismissed() {
        waitingForDismissal = false
        if let queued = queuedPresentation {
            queuedPresentation = nil
            presentation = queued
        }
    }

    nonisolated func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        Task { @MainActor in self.onInvite(invite) }
    }

    nonisolated func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        Task { @MainActor in
            self.dismissPresentation()
            self.pendingMode = nil
            GKMatchmaker.shared().cancel()
        }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        Task { @MainActor in self.dismissPresentation(); self.errorMessage = error.localizedDescription }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        Task { @MainActor in
            self.dismissPresentation()
            self.matchedThisLaunch = true
            GKMatchmaker.shared().finishMatchmaking(for: match)
            self.onMatch(match, self.currentMode)
        }
    }
}
