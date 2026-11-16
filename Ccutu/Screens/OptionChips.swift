import SwiftUI
import KkutuCore

/// 방 설정과 연습 카드가 같이 쓰는 특수 규칙 칩. 어인정을 켜면 주제 고르기 시트가 뜨고, 켜져 있는 동안 주제 줄로 다시 연다.
struct OptionChips: View {
    @Binding var options: RoomOptions
    var editable = true
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                chip("매너", \.manner)
                chip("어인정", \.injeong) { if options.injeong { picking = true } }
                chip("미션 글자", \.mission)
            }
            HStack(spacing: 4) {
                chip("외래어 금지", \.noLoanword)
                chip("표준어만", \.strict)
                chip("복합어", \.compound)
            }
            if options.injeong { themeRow }
        }
        .sheet(isPresented: $picking) {
            InjeongThemeSheet(picked: options.injeongThemes, editable: editable) { options.injeongThemes = $0 }
        }
    }

    private func chip(_ title: String, _ key: WritableKeyPath<RoomOptions, Bool>, then: @escaping () -> Void = {}) -> some View {
        let on = options[keyPath: key]
        return Button { options[keyPath: key].toggle(); then() } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(on ? Theme.onAccent : Theme.muted)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(on ? Theme.accent : Theme.raised))
        }
            .disabled(!editable)
            .accessibilityLabel(title)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 방장이 아니어도 눌러서 고른 주제를 볼 수 있다(끄투 방 정보처럼).
    private var themeRow: some View {
        Button { picking = true } label: {
            HStack(spacing: 8) {
                Text("주제").foregroundStyle(Theme.muted)
                Text(InjeongThemeSheet.summary(options.injeongThemes)).foregroundStyle(Theme.ink).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.dim)
            }
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().strokeBorder(Theme.raised, lineWidth: 2))
        }
        .accessibilityLabel("어인정 주제, \(InjeongThemeSheet.summary(options.injeongThemes))")
    }
}

/// 끄투 InjPickDiag(주제 선택). 고치는 동안은 초안만 바꾸고 확인을 눌러야 방에 반영한다.
struct InjeongThemeSheet: View {
    static let all = WordFilter.injeongThemes
    let picked: Set<String>?
    let editable: Bool
    let onDone: (Set<String>?) -> Void
    @State private var draft: Set<String>
    @Environment(\.dismiss) private var dismiss

    init(picked: Set<String>?, editable: Bool, onDone: @escaping (Set<String>?) -> Void) {
        self.picked = picked; self.editable = editable; self.onDone = onDone
        _draft = State(initialValue: picked ?? Set(Self.all))
    }

    static func name(_ code: String) -> String { WordLabels.themeNames[code] ?? code }

    /// "전체", "유명인", "유명인 외 2개".
    static func summary(_ picked: Set<String>?) -> String {
        guard let picked else { return "전체" }
        let names = all.filter(picked.contains).map(name)
        guard let first = names.first else { return "없음" }
        return names.count == 1 ? first : "\(first) 외 \(names.count - 1)개"
    }

    var body: some View {
        let shown = editable ? draft : (picked ?? Set(Self.all))   // 참가자는 방장이 바꾸는 대로 본다
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("주제 선택").font(Theme.display(26)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(shown.count)/\(Self.all.count)").font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.accent)
            }
            Text(editable ? "어인정 단어는 고른 주제의 것만 받아요." : "방장이 고른 주제예요. 어인정 단어는 이 주제의 것만 받아요.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            if editable {
                HStack(spacing: 8) {
                    Button { draft = Set(Self.all) } label: { Chip(title: "모두 설정", on: false) }
                    Button { draft = [] } label: { Chip(title: "모두 해제", on: false) }
                }
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Self.all, id: \.self) { row($0, on: shown.contains($0)) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Button(editable ? "확인" : "닫기") {
                if editable { onDone(draft.count == Self.all.count ? nil : draft) }   // 모두 고르면 nil: 목록 밖 어인정 단어(신조어 등)까지 받는 예전 동작
                dismiss()
            }
            .buttonStyle(BigButtonStyle(height: 56, fontSize: 24))
            .disabled(editable && draft.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background(Theme.ground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: draft)
    }

    private func row(_ code: String, on: Bool) -> some View {
        Button {
            if on { draft.remove(code) } else { draft.insert(code) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(on ? Theme.accent : Theme.dim)
                Text(Self.name(code)).font(.system(size: 15, weight: .bold)).foregroundStyle(on ? Theme.ink : Theme.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        }
        .disabled(!editable)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
