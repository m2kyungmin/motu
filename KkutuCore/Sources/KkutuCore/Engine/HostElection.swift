/// 인터넷 대전에서 방장을 고른다. 상대 모두의 인사를 받은 뒤에만 답한다.
/// 이미 방에 있던 사람이 방장을 알려 왔으면(친구 추가로 늦게 들어옴) 그 사람, 아니면 Game Center ID가 가장 작은 사람.
public enum HostElection {
    public struct Hello: Sendable, Equatable {
        public let player: PlayerID
        /// 보낸 사람이 이미 방에 있으면 지금 방장의 플레이어 ID.
        public let host: PlayerID?
        public init(player: PlayerID, host: PlayerID?) { self.player = player; self.host = host }
    }

    /// 키는 Game Center 플레이어 ID. 돌려주는 값도 방장의 Game Center ID다.
    public static func elect(local: String, peers: [String], hellos: [String: Hello]) -> String? {
        guard !peers.isEmpty, peers.allSatisfy({ hellos[$0] != nil }) else { return nil }
        if let claimed = peers.lazy.compactMap({ hellos[$0]?.host }).first {
            return hellos.first { $0.value.player == claimed }?.key
        }
        return (peers + [local]).min()
    }
}
