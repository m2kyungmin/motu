import SwiftUI
import KkutuCore

struct BrowseView: View {
    var mode: MatchMode = .individual
    @Environment(SessionCoordinator.self) private var co
    @Environment(\.dismiss) private var dismiss

    @State private var internet = false
    @State private var selectedRoom: NearbyPeer.FoundRoom?
    @State private var roomCode = ""

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44).background(Circle().fill(Theme.card))
                    }
                    .accessibilityLabel("뒤로")
                    Spacer()
                    Text(mode.title).font(Theme.display(24)).foregroundStyle(Theme.ink)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                Picker("연결 방식", selection: $internet) {
                    Text("근처 플레이").tag(false)
                    Text("인터넷 플레이").tag(true)
                }
                .pickerStyle(.segmented)
                if internet {
                    VStack(spacing: 18) {
                        Image(systemName: "person.2.wave.2.fill")
                            .font(.system(size: 40)).foregroundStyle(Theme.blue)
                        Text("어디서든 친구와 한 판")
                            .font(Theme.display(26)).foregroundStyle(Theme.ink)
                        Text("Game Center로 친구를 초대하면 인터넷으로 함께 플레이할 수 있어요.")
                            .font(.system(size: 14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        Button { co.gameCenter.inviteFriends(mode: mode) } label: {
                            Label("친구 초대", systemImage: "envelope.fill")
                        }
                        .buttonStyle(BigButtonStyle(kind: mode == .team ? .blue : .filled, height: 56, fontSize: 22))
                        .disabled(co.gameCenter.authenticating)
                        if co.gameCenter.authenticating {
                            ProgressView("Game Center 연결 중…").tint(Theme.accent).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Theme.card))
                    Spacer(minLength: 0)
                } else {
                    Button {
                        if co.createRoom(mode: mode) != nil { dismiss() }
                    } label: { Label("\(mode.title) 방 만들기", systemImage: "plus") }
                        .buttonStyle(BigButtonStyle(kind: mode == .team ? .blue : .filled, height: 56, fontSize: 22))
                    ScrollView {
                        VStack(spacing: 8) {
                            if let error = co.nearbyPeer?.errorMessage {
                                Text(error).font(.system(size: 14)).foregroundStyle(Theme.muted).padding(16)
                            } else if let rooms = co.nearbyPeer?.rooms.filter({ $0.mode == mode }), !rooms.isEmpty {
                                ForEach(rooms) { room in
                                    Button { roomCode = ""; selectedRoom = room } label: { row(room) }
                                }
                            } else {
                                HStack(spacing: 10) {
                                    ProgressView().tint(Theme.muted)
                                    Text("\(mode.title) 방을 찾는 중…").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                                }
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if !internet { co.startBrowsing() } }
        .onChange(of: internet) { _, online in
            if online { co.stopBrowsing() } else { co.startBrowsing() }
        }
        .alert("방 코드", isPresented: Binding(get: { selectedRoom != nil }, set: { if !$0 { selectedRoom = nil } })) {
            TextField("6자리 숫자", text: $roomCode).keyboardType(.numberPad)
            Button("입장") {
                guard let room = selectedRoom else { return }
                co.join(room, code: roomCode)
                selectedRoom = nil
                dismiss()
            }
            .disabled(roomCode.count != 6 || !roomCode.utf8.allSatisfy { (48...57).contains($0) })
            Button("취소", role: .cancel) { selectedRoom = nil }
        } message: { Text("방장 화면에 표시된 6자리 코드를 입력해 주세요.") }
        .onDisappear { if co.client == nil { co.stopBrowsing() } }
    }

    private func row(_ room: NearbyPeer.FoundRoom) -> some View {
        HStack(spacing: 12) {
            Avatar(name: room.hostName, isRobot: false, tint: Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(room.roomName).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                Text("방장 \(room.hostName)").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(room.count).font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.accent)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
    }
}
