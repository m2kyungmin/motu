import Testing
@testable import KkutuCore

struct HostElectionTests {
    @Test func firstMatchPicksLowestGameCenterID() {
        let hellos: [String: HostElection.Hello] = ["G2": .init(player: "me", host: nil), "G1": .init(player: "you", host: nil)]
        #expect(HostElection.elect(local: "G2", peers: ["G1"], hellos: hellos) == "G1")
    }

    @Test func lateJoinerFollowsClaimedHostEvenWithLowestID() {
        // 친구 추가로 들어온 G0은 ID가 가장 작아도 기존 방장(G5, 승계로 바뀐 방장)을 따른다.
        let hellos: [String: HostElection.Hello] = [
            "G0": .init(player: "new", host: nil),
            "G3": .init(player: "old", host: "boss"),
            "G5": .init(player: "boss", host: "boss"),
        ]
        #expect(HostElection.elect(local: "G0", peers: ["G3", "G5"], hellos: hellos) == "G5")
    }

    @Test func waitsUntilEveryPeerSaidHello() {
        let hellos: [String: HostElection.Hello] = ["G0": .init(player: "new", host: nil), "G3": .init(player: "old", host: "boss")]
        #expect(HostElection.elect(local: "G0", peers: ["G3", "G5"], hellos: hellos) == nil)
        #expect(HostElection.elect(local: "G0", peers: [], hellos: hellos) == nil)
    }
}
