import KkutuCore

struct RoomPlayer: Codable, Hashable, Identifiable {
    var id: PlayerID
    var name: String
    var ready: Bool
    var robotLevel: Int?
    var team: Int? = nil
    var appearance: CharacterAppearance? = nil
    var isRobot: Bool { robotLevel != nil }
}

struct RoomState: Codable, Hashable {
    var name: String
    var hostID: PlayerID
    var settings: RoomSettings
    var players: [RoomPlayer]
    var gaming: Bool
    /// 방장이 바뀌어도 같은 방을 다시 찾기 위한 짧은 ID. 빌드 2가 보낸 상태에는 없다.
    var roomID: String? = nil
    var gameID: String? = nil
    var isPractice: Bool? = nil
}

enum ClientMessage: Codable {
    case join(id: PlayerID, name: String, appearance: CharacterAppearance? = nil)
    case ready(Bool)
    case setTeam(Int)
    case setRobotTeam(id: PlayerID, team: Int)
    case updateSettings(RoomSettings)
    case addRobot(level: Int)
    case removeRobot(id: PlayerID)
    case start
    case submit(String)
    case chat(String)          // 남의 차례이거나 이을 수 없는 글. 끄투 talk(relay 아님)
    case restart
    case leave
    case marbleWord(String, target: PlayerID?)   // 마블 룰렛: 단어 하나와 공 대상(nil·나 = 내 공 빼기)
    case marbleLoser(Int)                         // 방장 화면의 경주가 정한 벌칙 공 주인. 방장 것만 받는다.
    case marbleDraw                               // 방장: 걸린 벌칙 중 하나 뽑기
}

enum HostMessage: Codable {
    case roomState(RoomState)
    case gameEvent(EngineEvent, GameSnapshot)
    case error(code: Int)      // 411 혼자 시작 불가, 412 전원 준비 필요, 429 방 가득 참
    case chat(from: PlayerID, text: String)
    case marble(MarbleSnapshot)
    case marbleFrame(MarbleFrame)                 // 비신뢰 전송. 늦거나 빠져도 다음 프레임이 덮는다.
    case marbleReject(code: Int, word: String)
}

/// 방장이 경주 물리를 굴리며 보내는 공 위치. p는 경주 순서대로 [x, y, x, y, …](코스 논리 좌표, 정수),
/// 결승선을 넘어 사라진 공은 x = -1. f는 벌칙 공 번호(정해진 뒤), s는 회전 막대 각도(밀리라디안).
struct MarbleFrame: Codable, Equatable {
    var p: [Int]
    var f: Int?
    var s: Int?
}
