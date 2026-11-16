import AVFoundation

/// 끄투 효과음. 턴 소리(T0~T10)는 하나만 재생하고 턴이 끝나면 멈춘다.
/// 배경음악(bgm)은 따로 한 곡만 반복한다. 효과음을 끊는 stopAll은 배경음악을 건드리지 않는다.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var players: [String: AVAudioPlayer] = [:]
    private var turnPlayer: AVAudioPlayer?
    private var bgmPlayer: AVAudioPlayer?
    private var bgmName: String?
    static let bgmVolume: Float = 0.45          // 효과음이 묻히지 않게

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(_ name: String) {
        guard let p = player(name) else { return }
        p.currentTime = 0
        p.play()
    }

    /// loop: 폭탄 돌리기처럼 턴이 곡보다 길 수 있을 때 끝없이 반복한다(끄투 턴 곡은 턴 시간 길이로 한 번 재생).
    func playTurnSound(speed: Int, loop: Bool = false) {
        stopTurnSound()
        guard let p = player("T\(min(10, max(0, speed)))") else { return }
        p.numberOfLoops = loop ? -1 : 0
        p.currentTime = 0
        p.play()
        turnPlayer = p
    }

    func stopTurnSound() { turnPlayer?.stop(); turnPlayer = nil }

    /// 방을 나갈 때: 턴 배경음과 아직 울리는 효과음을 모두 끊는다.
    func stopAll() {
        players.values.forEach { $0.stop() }
        turnPlayer = nil
    }

    /// 배경음악을 바꾼다. 같은 곡이면 그대로 두고, 다른 곡이면 앞 곡을 fade초 동안 줄이며 새 곡을 키운다. nil이면 끈다.
    func bgm(_ name: String?, fade: TimeInterval = 0.8) {
        guard name != bgmName else { return }
        if let old = bgmPlayer {
            old.setVolume(0, fadeDuration: fade)
            DispatchQueue.main.asyncAfter(deadline: .now() + fade) { old.stop() }
        }
        bgmName = name
        bgmPlayer = nil
        guard let name, let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.numberOfLoops = -1
        p.volume = 0
        p.play()
        p.setVolume(Self.bgmVolume, fadeDuration: fade)
        bgmPlayer = p
    }

    /// 앱이 백그라운드로 가면 배경음악과 반복 중인 턴 음악을 멈춘다(시뮬레이터처럼 앱이 멈추지 않는 환경에서도 소리가 새지 않게).
    func pauseForBackground() {
        bgmPlayer?.pause()
        if let t = turnPlayer, t.numberOfLoops < 0 { t.pause() }
    }

    /// 앱이 백그라운드에서 돌아오면 멈춘 배경음악·턴 음악을 이어 튼다.
    func resumeBGM() {
        if let p = bgmPlayer, !p.isPlaying { p.play() }
        if let t = turnPlayer, t.numberOfLoops < 0, !t.isPlaying { t.play() }
    }

    private func player(_ name: String) -> AVAudioPlayer? {
        if let p = players[name] { return p }
        // 끄투 소리는 mp3, 직접 만든 소리는 m4a
        guard let url = ["mp3", "m4a"].lazy.compactMap({ Bundle.main.url(forResource: name, withExtension: $0) }).first,
              let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.prepareToPlay()
        players[name] = p
        return p
    }
}
