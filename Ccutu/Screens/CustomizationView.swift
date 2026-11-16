import SwiftUI
import KkutuCore

struct CustomizationView: View {
    @Environment(SessionCoordinator.self) private var co
    @Binding var editingNickname: Bool
    @Binding var requestNicknameFocus: Bool
    @State private var draftNickname = ""
    @State private var nicknameSaved = false
    @State private var slot = CosmeticSlot.head
    @FocusState private var nicknameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("커스터마이징").font(Theme.display(30)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(co.customization.wins)승").font(Theme.display(24)).foregroundStyle(Theme.accent)
                }
                preview
                nicknameEditor
                wardrobe
            }
            .padding(.horizontal, 20).padding(.top, 24)
            .padding(.bottom, editingNickname ? 24 : 100)
        }
        .background(Theme.ground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .onAppear { draftNickname = co.nickname }
        .onChange(of: requestNicknameFocus, initial: true) { _, requested in
            if requested { nicknameFocused = true; requestNicknameFocus = false }
        }
        .onChange(of: nicknameFocused) { _, focused in editingNickname = focused }
        .onChange(of: draftNickname) { _, _ in if nicknameFocused { nicknameSaved = false } }
        .onDisappear { nicknameFocused = false; editingNickname = false }
    }

    private var preview: some View {
        VStack(spacing: 10) {
            Avatar(name: co.playerName, isRobot: false, size: 132, appearance: co.customization.appearance)
            Text(co.playerName).font(Theme.display(24)).foregroundStyle(Theme.ink).lineLimit(1)
            Text("방과 게임에서 이 모습으로 보여요").font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .background {
            ZStack {
                Theme.card
                Stripe(color: Theme.raised, width: 160, height: 18).offset(x: -130, y: -80)
                Stripe(color: Theme.raised, width: 140, height: 18).offset(x: 140, y: 70)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26))
        }
    }

    private var validNickname: Bool {
        let name = draftNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 20 && name.utf8.count <= 63 && !name.contains(where: \.isNewline)
    }

    private var nicknameEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "닉네임")
            HStack(spacing: 10) {
                TextField("플레이어", text: $draftNickname)
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink)
                    .focused($nicknameFocused).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .submitLabel(.done).onSubmit(saveNickname)
                Button("저장", action: saveNickname)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 18).frame(height: 40)
                    .background(Capsule().fill(Theme.accent))
                    .disabled(!validNickname || draftNickname.trimmingCharacters(in: .whitespacesAndNewlines) == co.nickname)
                    .opacity(validNickname && draftNickname.trimmingCharacters(in: .whitespacesAndNewlines) != co.nickname ? 1 : 0.4)
            }
            .padding(.leading, 18).padding(.trailing, 8).frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
            Text(nicknameSaved ? "닉네임을 저장했어요" : validNickname || draftNickname.isEmpty ? "최대 20자" : "닉네임을 조금 짧게 입력해 주세요")
                .font(.system(size: 12)).foregroundStyle(nicknameSaved ? Theme.success : Theme.muted)
        }
    }

    private func saveNickname() {
        guard validNickname else { return }
        let saved = co.saveNickname(draftNickname)
        draftNickname = co.nickname
        nicknameSaved = saved
        nicknameFocused = false
    }

    private var wardrobe: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("캐릭터 꾸미기").font(Theme.display(24)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(co.customization.unlocked.count)/\(CosmeticCatalog.items.count)")
                    .font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(Theme.accent)
            }
            Text("개인전·팀전에서 이길 때마다 하나씩 해금돼요")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            ProgressView(value: Double(co.customization.unlocked.count), total: Double(CosmeticCatalog.items.count))
                .tint(Theme.accent)
            if let next = co.customization.nextItem {
                HStack {
                    Label("다음 해금 · \(next.name)", systemImage: "lock.fill")
                    Spacer(minLength: 0)
                    Text("\(co.customization.wins + 1)승")
                }
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
            } else {
                Text("모든 꾸미기를 모았어요!").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.success)
            }
            HStack(spacing: 8) {
                ForEach(CosmeticSlot.allCases, id: \.self) { category in
                    Button { slot = category } label: {
                        Text(category.title).font(.system(size: 14, weight: .bold))
                            .foregroundStyle(slot == category ? Theme.onAccent : Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(slot == category ? Theme.accent : Theme.raised))
                    }
                    .accessibilityAddTraits(slot == category ? .isSelected : [])
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                itemTile(nil)
                ForEach(CosmeticCatalog.items.filter { $0.slot == slot }) { item in itemTile(item) }
            }
        }
        .sensoryFeedback(.selection, trigger: slot)
        .sensoryFeedback(.selection, trigger: co.customization.appearance)
    }

    private func itemTile(_ item: CosmeticItem?) -> some View {
        let owned = item.map { co.customization.unlocked.contains($0.id) } ?? true
        let equipped = co.customization.appearance.itemID(for: slot) == item?.id
        var appearance = co.customization.appearance
        appearance.set(item, for: slot)
        let unlockWin = item.flatMap { wanted in CosmeticCatalog.items.firstIndex { $0.id == wanted.id } }.map { $0 + 1 } ?? 0
        return Button {
            if let item { co.equip(item) } else { co.resetAppearance(slot) }
        } label: {
            VStack(spacing: 5) {
                Avatar(name: co.playerName, isRobot: false, size: 70, appearance: appearance)
                    .opacity(owned ? 1 : 0.4)
                Text(item?.name ?? "기본").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(owned ? Theme.ink : Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
                Text(equipped ? "장착 중" : owned ? "보유" : "\(unlockWin)승 해금")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(equipped ? Theme.accent : Theme.dim)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(equipped ? Theme.accent : Theme.raised, lineWidth: equipped ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if !owned { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.dim).padding(9) }
            }
        }
        .buttonStyle(.plain).disabled(!owned)
        .accessibilityLabel("\(item?.name ?? "기본"), \(equipped ? "장착 중" : owned ? "보유" : "\(unlockWin)승에 해금")")
        .accessibilityAddTraits(equipped ? .isSelected : [])
    }
}
