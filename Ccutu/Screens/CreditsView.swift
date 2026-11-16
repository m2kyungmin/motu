import SwiftUI

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("함께 만든 모투").font(Theme.display(30)).foregroundStyle(Theme.accent)
                    Text("끄투온라인의 한국어 끝말잇기를 iPhone에서 즐길 수 있도록 옮겼습니다.")
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                    credit("원작 · 코드", name: "KKuTu · JJoriping", detail: "GPL-3.0 · 이 앱의 변경분 포함",
                           url: "https://github.com/JJoriping/KKuTu")
                    credit("캐릭터 · 효과음", name: "끄투온라인 · 모레미", detail: "CC BY 4.0",
                           url: "https://github.com/JJoriping/KKuTu")
                    credit("단어 사전", name: "KKuTu · kkutu_ko", detail: "원작의 한국어 단어 데이터에서 추출",
                           url: "https://github.com/JJoriping/KKuTu")
                    credit("단어 사전 보강", name: "국립국어원 · 우리말샘", detail: "2026년 10월 전체 자료에서 끄투에 없는 단어를 끄투 형식으로 바꿔 추가 · CC BY-SA 2.0 KR",
                           url: "https://opendict.korean.go.kr")
                    credit("글꼴", name: "Black Han Sans · 검은고딕", detail: "The Black Han Sans Project Authors · SIL OFL 1.1",
                           url: "https://github.com/google/fonts/tree/main/ofl/blackhansans")
                    credit("로비 음악", name: "Sunny City · MintoDog", detail: "CC0",
                           url: "https://opengameart.org/content/sunny-city")
                    credit("경주 음악", name: "Fever Stadium · MintoDog", detail: "기본판 · 막판판 · CC0",
                           url: "https://opengameart.org/node/162191")
                    credit("폭발 효과음", name: "Light explosion near in forest · wyskoj", detail: "일부 구간 편집 · CC0",
                           url: "https://freesound.org/people/wyskoj/sounds/530162/")
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("크레딧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private func credit(_ category: String, name: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            Link(destination: URL(string: url)!) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name).font(.system(size: 16, weight: .semibold))
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.ink)
            }
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
    }
}
