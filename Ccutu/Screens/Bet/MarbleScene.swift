import SpriteKit

/// 마블 룰렛 장면 (lazygyu.github.io/roulette 방식). 코스는 상수로만 지어서 모든 폰에서 똑같다.
/// - 단어를 치는 동안: 출발선 위 통에 공이 떨어지고 빠진다. 폰마다 따로 굴리는 겉모습이고, 개수만 방장 기준이다.
/// - 경주: 모든 폰이 같은 순서로 공을 줄 세운다. 방장 폰은 물리를 굴리며 위치를 내보내고(onFrame),
///   참가자 폰은 받은 위치를 따라 그린다(apply). 결과는 방장 폰 하나가 정한다(onDecided).
final class MarbleScene: SKScene {
    static let width: CGFloat = 390
    static let r: CGFloat = 10
    static let finishY: CGFloat = 70
    static let gateY: CGFloat = 2400
    static let top: CGFloat = 2660
    static let timeLimit: TimeInterval = 50
    static let palette: [UIColor] = [0xFF6B6B, 0x4D8DFF, 0xFFD23F, 0x3DE0A0, 0xB77DFF, 0xFF9F43, 0xFF7EB6, 0x3CC8E0]
        .map { UIColor(red: CGFloat($0 >> 16 & 0xFF) / 255, green: CGFloat($0 >> 8 & 0xFF) / 255, blue: CGFloat($0 & 0xFF) / 255, alpha: 1) }

    var onFrame: (MarbleFrame) -> Void = { _ in }
    var onDecided: (Int) -> Void = { _ in }
    /// 순위(공 번호, 앞에서부터)와 그중 결승선을 넘은 개수. 바뀔 때만 초당 몇 번 부른다.
    var onRanking: ([Int], Int) -> Void = { _, _ in }

    private let labels: [String]          // 주인 번호마다 공에 찍을 글자
    private var gate: SKNode?
    private var spinners: [SKNode] = []   // 두 막대는 같은 빠르기로 반대로 돈다(둘째 각도 = -첫째)
    private var jar: [(owner: Int, node: SKShapeNode)] = []
    private var racing = false
    private var lastLoses = false
    private var owners: [Int] = []        // 경주 공마다 주인 번호
    private var balls: [SKShapeNode] = []
    private var targets: [CGPoint] = []
    private var best: [CGFloat] = []
    private var bestAt: [TimeInterval] = []
    private var done: [Bool] = []
    private var finished: [Int] = []
    private var running = false           // 방장 폰: 경주 물리가 도는 중
    private var mirroring = false         // 참가자 폰: 받은 위치를 따라 그리는 중
    private var focus: Int?
    private var startAt: TimeInterval?
    private var lastEmit: TimeInterval = 0
    private let cam = SKCameraNode()

    // 순위: 결승까지 남은 높이를 0.4초 지수 평균으로 다듬고, 앞 공보다 margin 이상 앞서야 자리를 바꾼다(깜빡임 방지).
    private var ema: [CGFloat] = []
    private var rank: [Int] = []
    private var sentRank: [Int] = []
    private var lastT: TimeInterval?
    private var frameNo = 0
    static let rankMargin: CGFloat = 6

    // 카메라 (lazygyu camera.ts의 방식): 벌칙 순위에 있는 공(target)과 바로 옆 순위 공(rival)을 한 화면에 담고,
    // 결승이 가까워지면 슬로모션과 함께 크게 확대한다. 위치·배율은 매 프레임 남은 차이의 1/10씩 따라간다.
    private var zoom: CGFloat = 1                 // 1 = 코스 폭 390이 화면 폭, 2 = 두 배 확대
    private var pair: (Int, Int?)?
    private var pending: (Int, Int?)?
    private var pendingFrames = 0
    /// 결승 직전 슬로모션이 시작될 때 한 번. 모든 폰이 같은 위치로 계산하므로 같은 때 부른다.
    var onClimax: () -> Void = {}
    private var climaxed = false
    static let zoomThreshold: CGFloat = 260       // 결승선에서 이 높이 안이면 확대·감속을 시작한다
    static let switchFrames = 20                  // 순위 짝이 이만큼 버텨야 카메라가 옮겨 간다

    init(labels: [String]) {
        self.labels = labels
        super.init(size: CGSize(width: Self.width, height: 600))
        scaleMode = .aspectFit
        backgroundColor = .clear              // 뒤의 SwiftUI 카드 색이 보인다
        physicsWorld.gravity = CGVector(dx: 0, dy: -3.2)
        addChild(cam)
        camera = cam
        build()
        cam.position = CGPoint(x: Self.width / 2, y: jarCameraY)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 뷰 크기가 바뀌면(키보드, 경주 전환) 보이는 높이만 바꾼다. 폭은 늘 390이라 코스는 그대로다.
    func setViewport(_ s: CGSize) {
        guard s.width > 0, s.height > 0 else { return }
        size = CGSize(width: Self.width, height: Self.width * s.height / s.width)
    }

    // MARK: 코스

    private func build() {
        let w = Self.width, r = Self.r, finishY = Self.finishY
        physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(x: 0, y: -400, width: w, height: Self.top + 800))

        let g = line(CGPoint(x: 0, y: Self.gateY), CGPoint(x: w, y: Self.gateY), color: UIColor(red: 1, green: 0.82, blue: 0.25, alpha: 1))
        gate = g

        // 아래로 내려가며: 핀 → 회전 막대 → 지그재그 비탈 → 촘촘한 핀 → 깔때기 → 결승선
        let span = Self.gateY - finishY - 200
        var y = Self.gateY - 40
        let pegs1 = span * 0.24, spin = span * 0.14, ramps = span * 0.30, pegs2 = span * 0.20
        addPegs(from: y, to: y - pegs1, spacing: 2 * r * 1.9 + 8); y -= pegs1
        addSpinner(at: CGPoint(x: w * 0.28, y: y - spin / 2), length: w * 0.42, clockwise: true)
        addSpinner(at: CGPoint(x: w * 0.72, y: y - spin / 2), length: w * 0.42, clockwise: false)
        y -= spin
        for k in 0..<4 { addRamp(fromLeft: k % 2 == 0, y: y - ramps * (CGFloat(k) + 0.5) / 4) }
        y -= ramps
        addPegs(from: y, to: y - pegs2, spacing: 2 * r * 1.7 + 8)
        let funnelGap = r * 5
        line(CGPoint(x: 0, y: finishY + 120), CGPoint(x: w / 2 - funnelGap / 2, y: finishY + 30))
        line(CGPoint(x: w, y: finishY + 120), CGPoint(x: w / 2 + funnelGap / 2, y: finishY + 30))

        let finish = SKShapeNode(rect: CGRect(x: 0, y: finishY - 3, width: w, height: 6))
        finish.fillColor = .white.withAlphaComponent(0.85)
        finish.strokeColor = .clear
        addChild(finish)
        let goal = SKLabelNode(text: "결승")
        goal.fontName = "AppleSDGothicNeo-Heavy"
        goal.fontSize = 14
        goal.fontColor = .white.withAlphaComponent(0.6)
        goal.position = CGPoint(x: w / 2, y: finishY - 26)
        addChild(goal)
    }

    private func addPegs(from yTop: CGFloat, to yBottom: CGFloat, spacing: CGFloat) {
        let pegR = max(3, Self.r * 0.35)
        var y = yTop - spacing / 2, row = 0
        while y > yBottom {
            var x = 14 + (row % 2 == 0 ? spacing / 2 : 0)
            while x < Self.width - 14 {
                let p = SKShapeNode(circleOfRadius: pegR)
                p.fillColor = UIColor(white: 0.75, alpha: 1)
                p.strokeColor = .clear
                p.position = CGPoint(x: x, y: y)
                let body = SKPhysicsBody(circleOfRadius: pegR)
                body.isDynamic = false
                body.restitution = 0.5
                p.physicsBody = body
                addChild(p)
                x += spacing
            }
            y -= spacing * 0.8
            row += 1
        }
    }

    private func addSpinner(at p: CGPoint, length: CGFloat, clockwise: Bool) {
        let bar = SKShapeNode(rectOf: CGSize(width: length, height: 8), cornerRadius: 4)
        bar.fillColor = UIColor(red: 1, green: 0.82, blue: 0.25, alpha: 1)
        bar.strokeColor = .clear
        bar.position = p
        let body = SKPhysicsBody(rectangleOf: CGSize(width: length, height: 8))
        body.isDynamic = false
        bar.physicsBody = body
        bar.run(.repeatForever(.rotate(byAngle: clockwise ? -.pi : .pi, duration: 1.6)), withKey: "spin")
        addChild(bar)
        spinners.append(bar)
    }

    /// 한쪽 벽에서 반대쪽으로 내려가는 비탈. 낮은 끝 쪽에 공이 빠질 틈이 남는다.
    private func addRamp(fromLeft: Bool, y: CGFloat) {
        let w = Self.width, len = w * 0.74, drop = len * 0.2
        let hi = CGPoint(x: fromLeft ? 0 : w, y: y + drop / 2)
        let lo = CGPoint(x: fromLeft ? len : w - len, y: y - drop / 2)
        line(hi, lo)
    }

    @discardableResult
    private func line(_ a: CGPoint, _ b: CGPoint, color: UIColor = UIColor(red: 0.3, green: 0.55, blue: 1, alpha: 1)) -> SKNode {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        let node = SKShapeNode(path: path)
        node.strokeColor = color
        node.lineWidth = 6
        node.lineCap = .round
        node.physicsBody = SKPhysicsBody(edgeFrom: a, to: b)
        node.physicsBody?.restitution = 0.2
        addChild(node)
        return node
    }

    private func makeBall(owner: Int, at p: CGPoint, physics: Bool) -> SKShapeNode {
        let b = SKShapeNode(circleOfRadius: Self.r)
        b.fillColor = Self.palette[owner % Self.palette.count]
        b.strokeColor = .black.withAlphaComponent(0.35)
        b.lineWidth = 1.5
        b.position = p
        b.zPosition = 2
        let label = SKLabelNode(text: labels.indices.contains(owner) ? labels[owner] : "")
        label.fontName = "AppleSDGothicNeo-Heavy"
        label.fontSize = Self.r * 1.05
        label.fontColor = .black.withAlphaComponent(0.75)
        label.verticalAlignmentMode = .center
        b.addChild(label)
        if physics {
            let body = SKPhysicsBody(circleOfRadius: Self.r)
            body.restitution = 0.35
            body.friction = 0.05
            body.linearDamping = 0.15
            body.usesPreciseCollisionDetection = true
            body.allowsRotation = false            // 이름 글자가 뒤집히지 않게
            b.physicsBody = body
        }
        addChild(b)
        return b
    }

    // MARK: 통 (단어를 치는 동안)

    /// 사람마다 공 개수를 맞춘다. 늘면 위에서 떨어뜨리고, 줄면 그 사람 공 하나를 터뜨린다.
    func setCounts(_ counts: [Int]) {
        guard !racing else { return }
        for (owner, n) in counts.enumerated() {
            var have = jar.filter { $0.owner == owner }.count
            while have < n {
                let p = CGPoint(x: .random(in: 30...(Self.width - 30)), y: Self.top - 20 - .random(in: 0...120))
                jar.append((owner, makeBall(owner: owner, at: p, physics: true)))
                have += 1
            }
            while have > n, let i = jar.lastIndex(where: { $0.owner == owner }) {
                let b = jar.remove(at: i).node
                b.physicsBody = nil
                b.zPosition = 6
                b.run(.sequence([.group([.scale(to: 2.2, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
                have -= 1
            }
        }
    }

    private var jarCameraY: CGFloat { Self.gateY - 50 + size.height / 2 }

    // MARK: 경주

    /// 모든 폰이 같은 순서·같은 자리로 공을 줄 세운다. physics는 방장 폰만.
    func layoutRace(order: [Int], lastLoses: Bool, physics: Bool) {
        guard !racing else { return }
        racing = true
        self.lastLoses = lastLoses
        jar.forEach { $0.node.removeFromParent() }
        jar = []
        physicsWorld.speed = 0
        let r = Self.r, gap = 2 * r + 4
        let cols = Int((Self.width - 32) / gap)
        for (i, owner) in order.enumerated() {
            let row = i / cols, col = i % cols
            let x = min(Self.width - 16 - r, 16 + r + CGFloat(col) * gap + (row % 2 == 0 ? 0 : gap / 2))
            let y = Self.gateY + r + 6 + CGFloat(row) * gap
            balls.append(makeBall(owner: owner, at: CGPoint(x: x, y: y), physics: physics))
        }
        owners = order
        targets = balls.map(\.position)
        ema = balls.map(\.position.y)
        rank = balls.indices.sorted { balls[$0].position.y < balls[$1].position.y }
        if !physics { spinners.forEach { $0.removeAction(forKey: "spin") } }   // 참가자 폰은 방장 각도를 따른다
        best = balls.map(\.position.y)
        bestAt = Array(repeating: 0, count: balls.count)
        done = Array(repeating: false, count: balls.count)
        mirroring = !physics
    }

    /// 방장 폰: 출발선을 치우고 굴린다.
    func start() {
        guard racing, !mirroring, !running else { return }
        running = true
        gate?.removeFromParent()
        physicsWorld.speed = 1
        for b in balls { b.physicsBody?.velocity = CGVector(dx: .random(in: -40...40), dy: 0) }
    }

    /// 참가자 폰: 방장이 보낸 위치를 받는다.
    func apply(_ f: MarbleFrame) {
        guard mirroring, f.p.count == balls.count * 2 else { return }
        gate?.removeFromParent()
        for i in balls.indices {
            let x = f.p[2 * i], y = f.p[2 * i + 1]
            if x < 0 {
                if !done[i] { done[i] = true; finished.append(i); burst(i, big: false); fade(i) }
                continue
            }
            if y < Int(Self.finishY), !done[i] {               // 결승선에 세워 둔 벌칙 공
                done[i] = true; finished.append(i); burst(i, big: true)
            }
            targets[i] = CGPoint(x: x, y: y)
        }
        if let k = f.f, focus == nil, balls.indices.contains(k) { mark(k) }
        if let s = f.s, spinners.count == 2 {
            spinners[0].zRotation = CGFloat(s) / 1000
            spinners[1].zRotation = -CGFloat(s) / 1000
        }
    }

    override func update(_ t: TimeInterval) {
        let dt = min(0.1, t - (lastT ?? t)); lastT = t
        if mirroring {
            for i in balls.indices where !done[i] {
                let p = balls[i].position, q = targets[i]
                balls[i].position = CGPoint(x: p.x + (q.x - p.x) * 0.35, y: p.y + (q.y - p.y) * 0.35)
            }
        } else if running {
            step(t)
        }
        if racing { updateRanking(dt) }
        followCamera()
    }

    // MARK: 순위

    private func updateRanking(_ dt: TimeInterval) {
        let a = CGFloat(min(1, dt / 0.4))
        for i in balls.indices where !done[i] { ema[i] += (balls[i].position.y - ema[i]) * a }
        var live = rank.filter { !done[$0] }
        for _ in 0..<3 {                               // 한 프레임에 몇 번만 이웃끼리 바꾼다
            var swapped = false
            for k in 0..<max(0, live.count - 1) where ema[live[k + 1]] < ema[live[k]] - Self.rankMargin {
                live.swapAt(k, k + 1); swapped = true
            }
            if !swapped { break }
        }
        rank = finished + live
        frameNo += 1
        if frameNo % 6 == 0, rank != sentRank {
            sentRank = rank
            onRanking(rank, finished.count)
        }
    }

    private func step(_ t: TimeInterval) {
        if startAt == nil { startAt = t; for i in bestAt.indices { bestAt[i] = t } }
        for i in balls.indices where !done[i] {
            let b = balls[i]
            if b.position.y < Self.finishY {
                done[i] = true
                finished.append(i)
                // 벌칙 공(먼저 도착 규칙의 1등, 마지막 규칙의 꼴찌)은 결승선에 세워 보여 준다
                let decisive = i == focus || (!lastLoses && finished.count == 1)
                burst(i, big: decisive)
                if decisive { park(i) } else { fade(i) }
                continue
            }
            if b.position.y < best[i] - 3 {
                best[i] = b.position.y
                bestAt[i] = t
            } else if t - bestAt[i] > 1.5 {
                b.physicsBody?.velocity = CGVector(dx: .random(in: -140...140), dy: 120)   // 끼었으면 튕겨 준다
                bestAt[i] = t
            }
        }
        let left = balls.indices.filter { !done[$0] }
        if focus == nil {
            if !lastLoses, let first = finished.first {
                decide(first)
            } else if lastLoses, left.count == 1 {
                decide(left[0])
            } else if lastLoses, left.isEmpty, let last = finished.last {
                decide(last)
            } else if let s = startAt, t - s > Self.timeLimit, !left.isEmpty {
                let byHeight = left.sorted { balls[$0].position.y < balls[$1].position.y }
                decide(lastLoses ? byHeight.last! : byHeight.first!)
            } else {
                // 판가름이 가까울수록 느리게(최저 0.25배). 원작처럼 결승까지 남은 높이에 비례.
                physicsWorld.speed = max(0.25, 1 - intensity)
            }
        }
        if t - lastEmit >= 1.0 / 15 {
            lastEmit = t
            var p: [Int] = []
            p.reserveCapacity(balls.count * 2)
            for i in balls.indices {
                if done[i] && i != focus { p += [-1, -1] } else { p += [Int(balls[i].position.x.rounded()), Int(balls[i].position.y.rounded())] }
            }
            onFrame(MarbleFrame(p: p, f: focus, s: spinners.first.map { Int(($0.zRotation * 1000).rounded()) }))
        }
    }

    private func park(_ i: Int) {
        let b = balls[i]
        b.physicsBody = nil
        b.run(.move(to: CGPoint(x: b.position.x, y: Self.finishY - Self.r - 8), duration: 0.15))
    }

    private func fade(_ i: Int) {
        let b = balls[i]
        b.physicsBody = nil
        b.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func mark(_ i: Int) {
        focus = i
        let b = balls[i]
        b.zPosition = 5
        b.alpha = 1
        let ring = SKShapeNode(circleOfRadius: Self.r + 6)
        ring.strokeColor = .white
        ring.lineWidth = 3
        ring.fillColor = .clear
        ring.run(.repeatForever(.sequence([.scale(to: 1.4, duration: 0.35), .scale(to: 1, duration: 0.35)])))
        b.addChild(ring)
    }

    private func decide(_ i: Int) {
        mark(i)
        physicsWorld.speed = 0.6
        onDecided(owners[i])
    }

    /// 결승선 근처 공이 펑 하고 튀는 작은 조각들. 벌칙 공은 더 크게.
    private func burst(_ i: Int, big: Bool) {
        let at = CGPoint(x: balls[i].position.x, y: Self.finishY)
        let color = Self.palette[owners[i] % Self.palette.count]
        for k in 0..<(big ? 18 : 7) {
            let dot = SKShapeNode(circleOfRadius: big ? 4 : 2.5)
            dot.fillColor = big && k % 3 == 0 ? .white : color
            dot.strokeColor = .clear
            dot.position = at
            dot.zPosition = 4
            addChild(dot)
            let ang = CGFloat.random(in: 0.15...(.pi - 0.15)), dist = CGFloat.random(in: big ? 40...110 : 18...45)
            dot.run(.sequence([
                .group([.move(by: CGVector(dx: cos(ang) * dist, dy: sin(ang) * dist), duration: big ? 0.7 : 0.45),
                        .fadeOut(withDuration: big ? 0.7 : 0.45)]),
                .removeFromParent()]))
        }
    }

    // MARK: 카메라

    /// 지금 판가름에 걸린 공. 먼저 도착 규칙은 1등, 마지막 규칙은 아무도 안 들어왔을 땐 1등을 따라가다 이후엔 꼴찌.
    private func desiredPair() -> (Int, Int?)? {
        guard !rank.isEmpty else { return nil }
        if let f = focus { return (f, nil) }
        let k = (!lastLoses || finished.isEmpty) ? finished.count : rank.count - 1
        guard rank.indices.contains(k) else { return nil }
        let behind = k + 1 < rank.count && !done[rank[k + 1]] ? rank[k + 1] : nil
        let ahead = k - 1 >= 0 && !done[rank[k - 1]] ? rank[k - 1] : nil
        return (rank[k], behind ?? ahead)
    }

    /// 0~1. 판가름이 걸린 두 공 중 결승선에 더 가까운 쪽이 zoomThreshold 안으로 들어오면 커진다.
    /// 마지막 공 규칙은 두 공만 남았을 때(마지막 승부)만.
    private var intensity: CGFloat {
        guard racing, focus == nil, let p = pair else { return 0 }
        if lastLoses && balls.indices.filter({ !done[$0] }).count > 2 { return 0 }
        if !lastLoses && !finished.isEmpty { return 0 }
        let ys = [p.0] + (p.1.map { [$0] } ?? [])
        let gap = ys.map { balls[$0].position.y - Self.finishY }.min() ?? .infinity
        return max(0, min(1, 1 - gap / Self.zoomThreshold))
    }

    private func followCamera() {
        let vw = size.width, vh = size.height
        var center = CGPoint(x: vw / 2, y: jarCameraY)
        var want: CGFloat = 1
        if racing {
            // 짝이 바뀌어도 20프레임은 버텨야 옮겨 간다. 보던 공이 들어왔거나 벌칙 공이 정해지면 바로.
            if let d = desiredPair() {
                if pair == nil || (pair!.0 == d.0 && pair!.1 == d.1) || focus != nil || done[pair!.0] {
                    pair = d; pending = nil; pendingFrames = 0
                } else if let p = pending, p.0 == d.0, p.1 == d.1 {
                    pendingFrames += 1
                    if pendingFrames >= Self.switchFrames { pair = d; pending = nil; pendingFrames = 0 }
                } else {
                    pending = d; pendingFrames = 0
                }
            }
            if let p = pair {
                let a = balls[p.0].position
                center = a
                if let rv = p.1 {
                    // 두 공을 함께 담는 배율. 너무 멀면(0.45 미만) 짝은 버리고 target만 본다.
                    let b = balls[rv].position, pad = Self.r * 8
                    let fit = min(vw / (abs(b.x - a.x) + pad), vh / (abs(b.y - a.y) + pad))
                    let w = smoothstep((fit - 0.45) / (0.7 - 0.45))
                    center = CGPoint(x: a.x + ((a.x + b.x) / 2 - a.x) * w, y: a.y + ((a.y + b.y) / 2 - a.y) * w)
                    want = 1 + (min(1.6, max(0.7, fit)) - 1) * w
                }
                let i = intensity
                if i > 0.15, !climaxed { climaxed = true; onClimax() }
                if i > 0 {
                    // 결승이 가까우면 크게 확대하고 결승선이 화면에 들어오게 아래로 당긴다
                    want = max(want, 1 + 1.4 * i)
                    let pull = min(1, i * 4)
                    let lowY = min(a.y, p.1.map { balls[$0].position.y } ?? a.y)
                    center.y += ((lowY + Self.finishY) / 2 - center.y) * pull
                }
                if focus != nil { want = 2.2 }
            }
        }
        zoom += (want - zoom) * (racing ? 0.08 : 0.3)
        cam.setScale(1 / zoom)
        let hw = vw / (2 * zoom), hh = vh / (2 * zoom)
        let x = zoom > 1 ? min(vw - hw, max(hw, center.x)) : vw / 2
        let y = racing ? min(Self.top - hh, max(hh - 30, center.y)) : center.y
        cam.position.x += (x - cam.position.x) * (racing ? 0.1 : 0.3)
        cam.position.y += (y - cam.position.y) * (racing ? 0.1 : 0.3)
    }

    private func smoothstep(_ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, x))
        return t * t * (3 - 2 * t)
    }
}
