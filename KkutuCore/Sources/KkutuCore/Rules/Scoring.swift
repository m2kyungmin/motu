import Foundation

/// 끄투 const.js getPreScore/getPenalty, kkutu.js getTurnSpeed, classic.js turnStart의 수식.
public enum Scoring {
    public static let missionChars: [Character] = Array("가나다라마바사아자차카타파하")

    public static func preScore(length: Int, chainCount: Int, tr: Double) -> Double {
        2 * (pow(5 + 7 * Double(length), 0.74) + 0.88 * Double(chainCount)) * (0.5 + 0.5 * tr)
    }

    public static func penalty(chainCount: Int, score: Int) -> Int {
        -Int(min(10 + Double(chainCount) * 2.1 + Double(score) * 0.15, Double(score)).rounded())
    }

    public static func turnSpeed(roundTimeMs rt: Int) -> Int {
        let steps = [5000, 11000, 18000, 26000, 35000, 45000, 56000, 68000, 81000, 95000]
        for (i, limit) in steps.enumerated() where rt < limit { return 10 - i }
        return 0
    }

    public static func turnTimeMs(speed: Int) -> Int { 15000 - 1400 * speed }
}
