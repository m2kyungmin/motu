import Foundation
import Testing
@testable import KkutuCore

@Suite struct CustomizationTests {
    func result(team: Bool = false) -> GameSnapshot {
        var snapshot = GameSnapshot(totalRounds: 1)
        snapshot.phase = .ended; snapshot.round = 2
        snapshot.seats = team
            ? [Player(id: "A", name: "에이", team: 1), Player(id: "B", name: "비", team: 1),
               Player(id: "C", name: "씨", team: 2), Player(id: "D", name: "디", team: 2)]
            : [Player(id: "A", name: "에이"), Player(id: "B", name: "비")]
        snapshot.scores = team ? ["A": 40, "B": 20, "C": 30, "D": 10] : ["A": 20, "B": 10]
        return snapshot
    }

    @Test func oneNewItemPerWinAndDuplicateResultsAreIgnored() {
        var progress = CustomizationProgress()
        let first = progress.recordResult(gameID: "match-1", snapshot: result(), mode: .individual, playerID: "A", isPractice: false)
        #expect(first == CosmeticCatalog.items[0])
        #expect(progress.wins == 1)
        #expect(progress.unlocked == [CosmeticCatalog.items[0].id])
        let duplicate = progress.recordResult(gameID: "match-1", snapshot: result(), mode: .individual, playerID: "A", isPractice: false)
        #expect(duplicate == nil)
        #expect(progress.wins == 1)
        let second = progress.recordResult(gameID: "match-2", snapshot: result(), mode: .individual, playerID: "A", isPractice: false)
        #expect(second == CosmeticCatalog.items[1])
        #expect(progress.wins == 2)
    }

    @Test func practiceMarbleLossTieAndEarlyExitDoNotUnlock() {
        var progress = CustomizationProgress()
        let practice = progress.recordResult(gameID: "practice", snapshot: result(), mode: .individual, playerID: "A", isPractice: true)
        let marble = progress.recordResult(gameID: "marble", snapshot: result(), mode: .individual, playerID: "A", isPractice: false, isMarble: true)
        let loss = progress.recordResult(gameID: "loss", snapshot: result(), mode: .individual, playerID: "B", isPractice: false)
        #expect(practice == nil && marble == nil && loss == nil)
        var tie = result(); tie.scores["B"] = 20
        let shared = progress.recordResult(gameID: "tie", snapshot: tie, mode: .individual, playerID: "A", isPractice: false)
        #expect(shared == nil)
        var early = result(); early.round = 1
        let abandoned = progress.recordResult(gameID: "early", snapshot: early, mode: .individual, playerID: "A", isPractice: false)
        let emptyID = progress.recordResult(gameID: "", snapshot: result(), mode: .individual, playerID: "A", isPractice: false)
        #expect(abandoned == nil && emptyID == nil)
        #expect(progress.wins == 0)
        #expect(progress.unlocked.isEmpty)
    }

    @Test func allWinningTeamMembersGetOneRewardAndTeamTieGetsNone() {
        for id in ["A", "B"] {
            var progress = CustomizationProgress()
            let reward = progress.recordResult(gameID: "teams", snapshot: result(team: true), mode: .team, playerID: id, isPractice: false)
            #expect(reward != nil)
            #expect(progress.wins == 1)
        }
        var progress = CustomizationProgress()
        let loss = progress.recordResult(gameID: "teams", snapshot: result(team: true), mode: .team, playerID: "C", isPractice: false)
        #expect(loss == nil)
        var tie = result(team: true); tie.scores["D"] = 30
        let shared = progress.recordResult(gameID: "tied-teams", snapshot: tie, mode: .team, playerID: "A", isPractice: false)
        #expect(shared == nil)
        #expect(progress.wins == 0)
    }

    @Test func lockedItemsCannotBeEquippedAndProgressSurvivesEncoding() throws {
        var progress = CustomizationProgress()
        let first = CosmeticCatalog.items[0]
        let locked = progress.equip(first.id)
        #expect(!locked)
        _ = progress.recordResult(gameID: "saved-match", snapshot: result(), mode: .individual, playerID: "A", isPractice: false)
        let equipped = progress.equip(first.id)
        #expect(equipped)
        #expect(progress.appearance.head == first.id)
        var restored = try JSONDecoder().decode(CustomizationProgress.self, from: JSONEncoder().encode(progress))
        #expect(restored == progress)
        let duplicate = restored.recordResult(gameID: "saved-match", snapshot: result(), mode: .individual, playerID: "A", isPractice: false)
        #expect(duplicate == nil)
        #expect(restored.wins == 1)
        restored.reset(.head)
        #expect(restored.appearance.head == nil)
        #expect(restored.unlocked == [first.id])
    }

    @Test func remoteAppearanceOnlyUsesKnownItemsInCorrectSlots() throws {
        var appearance = CharacterAppearance()
        appearance.head = "../unknown"; appearance.eyes = CosmeticCatalog.items[0].id
        #expect(appearance.sanitized == CharacterAppearance())
        appearance.set(CosmeticCatalog.items[1], for: .eyes)
        #expect(appearance.sanitized.eyes == CosmeticCatalog.items[1].id)
        let player = Player(id: "A", name: "에이", appearance: appearance.sanitized)
        #expect(try JSONDecoder().decode(Player.self, from: JSONEncoder().encode(player)) == player)
        let old = #"{"id":"A","name":"에이"}"#
        #expect(try JSONDecoder().decode(Player.self, from: Data(old.utf8)).appearance == nil)
    }

    @Test func completeCollectionNeverRepeatsAnItem() {
        var progress = CustomizationProgress()
        for index in CosmeticCatalog.items.indices {
            let reward = progress.recordResult(gameID: "win-\(index)", snapshot: result(), mode: .individual, playerID: "A", isPractice: false)
            #expect(reward == CosmeticCatalog.items[index])
        }
        #expect(progress.nextItem == nil)
        #expect(Set(progress.unlocked).count == CosmeticCatalog.items.count)
        let complete = progress.recordResult(gameID: "extra-win", snapshot: result(), mode: .individual, playerID: "A", isPractice: false)
        #expect(complete == nil)
        #expect(progress.wins == CosmeticCatalog.items.count + 1)
    }

    @Test func actualEngineCompletionQualifiesForReward() {
        var settings = RoomSettings(); settings.rounds = 1
        let engine = GameEngine(settings: settings, dictionary: fixtureIndex(), rng: ZeroRNG(), titleOverride: "사")
        _ = engine.handle(.start(players: result().seats), nowMs: 0)
        _ = engine.handle(.deadline, nowMs: 2000)
        _ = engine.handle(.deadline, nowMs: 4400)
        _ = engine.handle(.submit(player: "A", text: "사과"), nowMs: 5400)
        _ = engine.handle(.deadline, nowMs: 7200)
        _ = engine.handle(.deadline, nowMs: 18100)
        _ = engine.handle(.deadline, nowMs: 21100)
        var progress = CustomizationProgress()
        #expect(engine.snapshot.phase == .ended)
        let reward = progress.recordResult(gameID: "real-engine", snapshot: engine.snapshot, mode: .individual, playerID: "A", isPractice: false)
        #expect(reward != nil)
    }
}
