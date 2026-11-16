import UIKit
import AVFoundation

/// 게임 순간의 진동. 시스템 설정(진동 끔)을 그대로 따른다.
@MainActor
enum Haptics {
    private static let notice = UINotificationFeedbackGenerator()
    private static let impact = UIImpactFeedbackGenerator(style: .medium)

    static func myTurn() { impact.impactOccurred() }
    static func accepted() { notice.notificationOccurred(.success) }
    static func rejected() { notice.notificationOccurred(.error) }
    static func timedOut() { notice.notificationOccurred(.warning) }

    // 내기 게임
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    /// 폭탄 초침. 점점 잦아진다.
    static func tick() { light.impactOccurred(intensity: 0.7) }
    /// 폭발: 무겁게 네 번 두드린 뒤 오류 진동.
    static func explode() {
        Task {
            for _ in 0..<4 {
                heavy.impactOccurred(intensity: 1)
                try? await Task.sleep(for: .milliseconds(90))
            }
            notice.notificationOccurred(.error)
        }
    }
}

/// 폭발 때 뒷면 플래시를 깜빡인다. 플래시가 없는 기기(시뮬레이터 등)는 아무것도 안 한다.
@MainActor
enum Flashlight {
    static func strobe(times: Int = 4) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        Task {
            for i in 0..<(times * 2) {
                set(device, on: i % 2 == 0)
                try? await Task.sleep(for: .milliseconds(90))
            }
            set(device, on: false)
        }
    }

    private static func set(_ device: AVCaptureDevice, on: Bool) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}
