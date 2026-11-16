import SwiftUI

struct DictionarySplashView: View {
    @Environment(SessionCoordinator.self) private var co

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            AppWordmark()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 16) {
                if let error = co.dictionaryError {
                    Text(error)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    Button("다시 불러오기") { co.loadDictionary() }
                        .buttonStyle(BigButtonStyle(height: 52, fontSize: 20, cornerRadius: 18))
                        .frame(maxWidth: 220)
                } else {
                    ProgressView().tint(Theme.accent)
                        .accessibilityLabel("사전 불러오는 중")
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .preferredColorScheme(.dark)
    }
}
