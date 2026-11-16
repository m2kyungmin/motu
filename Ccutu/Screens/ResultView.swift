import SwiftUI
import KkutuCore

struct ResultView: View {
    let client: RoomClient

    private var ranking: [ScoreEntry] { Array((client.ranking ?? []).prefix(8)) }   // 방은 최대 8명

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.ground.ignoresSafeArea()
            Stripe(color: Theme.raised, width: 300, height: 22).offset(x: -60, y: 0)
            Stripe(color: Theme.card, width: 260, height: 22).offset(x: 210, y: 50)

            VStack(spacing: 22) {
                VStack(spacing: 4) {
                    Text("\(client.snapshot?.totalRounds ?? 0)라운드 종료")
                        .font(.system(size: 13, weight: .bold)).tracking(2).foregroundStyle(Theme.muted)
                    Text("게임 끝").font(Theme.display(56)).foregroundStyle(Theme.accent)
                }
                ScrollView {
                    VStack(spacing: 22) {
                        rewardBanner
                        if client.room?.settings.matchMode == .team {
                            teamResults
                        } else {
                            if let first = ranking.first { spotlight(first) }
                            VStack(spacing: 8) { ForEach(ranking.dropFirst(), id: \.player) { row($0) } }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                VStack(spacing: 10) {
                    if client.isHost {
                        Button { client.send(.restart) } label: { Label("다시 하기", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(BigButtonStyle())
                    } else {
                        Text("방장이 다시 시작하면 대기실로 돌아가요").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
                    }
                    Button { client.leave() } label: {
                        Text("나가기").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var rewardBanner: some View {
        if client.earnedWin {
            HStack(spacing: 12) {
                if let item = client.unlockedReward {
                    Image(item.assetName).resizable().interpolation(.none).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("새로운 꾸미기를 해금했어요!").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
                        Text(item.name).font(Theme.display(22)).foregroundStyle(Theme.ink)
                        Text("커스터마이징에서 장착할 수 있어요").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                } else {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundStyle(Theme.success)
                    Text("승리! 모든 꾸미기를 모았어요").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.raised))
        }
    }

    @ViewBuilder private var teamResults: some View {
        if let snapshot = client.snapshot {
            let totals = snapshot.teamScores
            let teams = totals.keys.sorted { totals[$0, default: 0] == totals[$1, default: 0] ? $0 < $1 : totals[$0, default: 0] > totals[$1, default: 0] }
            ForEach(teams, id: \.self) { team in
                let score = totals[team, default: 0]
                let rank = totals.values.filter { $0 > score }.count + 1
                VStack(spacing: 12) {
                    HStack {
                        Text("\(rank)위 · \(TeamPalette.name(team))").font(Theme.display(24))
                        Spacer()
                        Text("\(score)점").font(Theme.display(26)).monospacedDigit()
                    }
                    .foregroundStyle(TeamPalette.color(team))
                    ForEach(snapshot.seats.filter { $0.team == team }, id: \.id) { player in
                        HStack(spacing: 10) {
                            Avatar(name: player.name, isRobot: player.isRobot, tint: TeamPalette.color(team), size: 40, appearance: player.appearance)
                            Text(player.name).font(.system(size: 16, weight: .bold)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(snapshot.scores[player.id, default: 0])점").font(.system(size: 14)).monospacedDigit()
                        }
                        .foregroundStyle(Theme.ink)
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 24).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(TeamPalette.color(team), lineWidth: rank == 1 ? 2 : 1))
            }
        }
    }

    private func spotlight(_ e: ScoreEntry) -> some View {
        let p = player(e.player)
        return VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach([54, 28, 14], id: \.self) { Capsule().fill(Theme.accent).frame(width: CGFloat($0), height: 12) }
            }
            Avatar(name: p.name, isRobot: p.isRobot, tint: Theme.accent, size: 84, appearance: p.appearance)
                .frame(width: 84, height: 92, alignment: .top)
            VStack(spacing: 2) {
                Text("\(e.rank)위").font(Theme.display(20)).tracking(2).foregroundStyle(Theme.accent)
                Text(p.name).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
            }
            (Text("\(e.score)").font(Theme.display(48)).foregroundStyle(Theme.ink)
             + Text("점").font(Theme.display(22)).foregroundStyle(Theme.muted))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26).padding(.bottom, 22).padding(.horizontal, 20)
        .background(RoundedRectangle(cornerRadius: 28).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.accent, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }

    private func row(_ e: ScoreEntry) -> some View {
        let p = player(e.player)
        return HStack(spacing: 12) {
            Text("\(e.rank)위").font(Theme.display(20)).foregroundStyle(Theme.muted).frame(width: 40, alignment: .leading)
            Avatar(name: p.name, isRobot: p.isRobot, tint: Theme.blue, size: 34, appearance: p.appearance)
            Text(p.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 0)
            (Text("\(e.score)").font(Theme.display(22)).foregroundStyle(Theme.ink)
             + Text("점").font(.system(size: 13)).foregroundStyle(Theme.muted))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        .accessibilityElement(children: .combine)
    }

    /// 순위의 플레이어. 게임 뒤에 나간 사람도 좌석 정보로 이름을 찾는다.
    private func player(_ id: PlayerID) -> (name: String, isRobot: Bool, appearance: CharacterAppearance?) {
        if let p = client.snapshot?.seats.first(where: { $0.id == id }) { return (p.name, p.isRobot, p.appearance) }
        if let p = client.room?.players.first(where: { $0.id == id }) { return (p.name, p.isRobot, p.appearance) }
        return (String(id.prefix(8)), false, nil)
    }
}
