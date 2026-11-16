import Foundation
import Testing
@testable import KkutuCore

@Suite struct TeamPlayTests {
    let players = [Player(id: "A", name: "에이", team: 1), Player(id: "B", name: "비", team: 1),
                   Player(id: "C", name: "씨", team: 2), Player(id: "D", name: "디", team: 2)]

    @Test func equalTeamsAndNoUnassignedPlayers() {
        #expect(TeamPlay.isBalanced(players))
        #expect(TeamPlay.isBalanced([players[0], players[2]]))
        #expect(!TeamPlay.isBalanced([]))
        #expect(!TeamPlay.isBalanced(Array(players.prefix(2))))
        #expect(!TeamPlay.isBalanced(Array(players.prefix(3))))
        #expect(!TeamPlay.isBalanced([players[0], Player(id: "X", name: "미정")]))
        #expect(!TeamPlay.isBalanced([players[0], Player(id: "X", name: "잘못된 팀", team: 5)]))
    }

    @Test func interleavesAllMembersInTeamOrder() {
        #expect(TeamPlay.turnOrder(players, teams: [2, 1]).map(\.id) == ["C", "A", "D", "B"])
        let three = [players[0], players[2], Player(id: "E", name: "이", team: 3)]
        #expect(TeamPlay.isBalanced(three))
        #expect(TeamPlay.turnOrder(three, teams: [3, 1, 2]).map(\.id) == ["E", "A", "C"])
    }

    @Test func approvedWordScoresForTeamAndNextTurnChangesTeam() {
        var settings = RoomSettings(); settings.mode = .team; settings.rounds = 1
        let engine = GameEngine(settings: settings, dictionary: fixtureIndex(), rng: ZeroRNG(), titleOverride: "사")
        _ = engine.handle(.start(players: players), nowMs: 0)
        let seats = engine.snapshot.seats
        #expect(Set(seats.map(\.id)) == Set(players.map(\.id)))
        for i in seats.indices { #expect(seats[i].team != seats[(i + 1) % seats.count].team) }
        _ = engine.handle(.deadline, nowMs: 2000)
        _ = engine.handle(.deadline, nowMs: 4400)
        let first = engine.snapshot.currentPlayer!
        _ = engine.handle(.submit(player: first.id, text: "사과"), nowMs: 5400)
        #expect(engine.snapshot.chain == ["사과"])
        #expect(engine.snapshot.teamScores[first.team!] == 17)
        _ = engine.handle(.deadline, nowMs: 7200)
        #expect(engine.snapshot.currentPlayer?.team != first.team)
        _ = engine.handle(.submit(player: engine.snapshot.currentPlayer!.id, text: "과자"), nowMs: 7700)
        #expect(engine.snapshot.teamScores.values.sorted() == [17, 19])
    }

    @Test func finalRankingUsesCombinedTeamScoreAfterMigration() {
        var settings = RoomSettings(); settings.mode = .team; settings.rounds = 1
        var snapshot = GameSnapshot(totalRounds: 1)
        snapshot.seats = players; snapshot.scores = ["A": 10, "B": 20, "C": 15, "D": 5]
        snapshot.round = 1; snapshot.title = "사"; snapshot.phase = .turnResult; snapshot.roundOver = true
        let engine = GameEngine(resuming: snapshot, settings: settings, dictionary: fixtureIndex(), rng: ZeroRNG())
        _ = engine.resume(dropping: [], nowMs: 0)
        let result = engine.handle(.deadline, nowMs: 1000)
        guard case .gameEnd(let ranking) = result.events.first else { Issue.record("팀 결과 없음"); return }
        for entry in ranking {
            let winning = entry.player == "A" || entry.player == "B"
            #expect(entry.score == (winning ? 30 : 20))
            #expect(entry.rank == (winning ? 1 : 3))
        }
    }

    @Test func cannotStartUnbalancedTeamsAndEndsWhenOnlyOneTeamRemains() {
        var settings = RoomSettings(); settings.mode = .team
        let engine = GameEngine(settings: settings, dictionary: fixtureIndex(), rng: ZeroRNG(), titleOverride: "사")
        #expect(engine.handle(.start(players: Array(players.prefix(3))), nowMs: 0).events.isEmpty)
        #expect(engine.snapshot.phase == .idle)
        _ = engine.handle(.start(players: [players[0], players[2]]), nowMs: 0)
        _ = engine.handle(.playerLeft("C"), nowMs: 100)
        #expect(engine.snapshot.phase == .ended)
    }

    @Test func oldRoomsDecodeAsIndividualAndNewTeamsRoundTrip() throws {
        let oldPlayer = #"{"id":"A","name":"에이"}"#
        #expect(try JSONDecoder().decode(Player.self, from: Data(oldPlayer.utf8)).team == nil)
        let oldSettings = #"{"rounds":5,"roundSeconds":60,"maxPlayers":8,"options":{"manner":false,"injeong":false,"mission":false,"noLoanword":false,"strict":false}}"#
        #expect(try JSONDecoder().decode(RoomSettings.self, from: Data(oldSettings.utf8)).matchMode == .individual)
        var settings = RoomSettings(); settings.mode = .team
        #expect(try JSONDecoder().decode(RoomSettings.self, from: JSONEncoder().encode(settings)) == settings)
        #expect(try JSONDecoder().decode([Player].self, from: JSONEncoder().encode(players)) == players)
    }
}
