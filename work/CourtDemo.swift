import AppKit

enum ShotGauge {
    static func width(distance:CGFloat)->Double {
        if distance<=200 { return 0.32 }
        if distance<=450 { return 0.32-Double((distance-200)/250)*0.16 }
        return max(0.06,0.16-Double((distance-450)/200)*0.10)
    }
    static func marker(time:Double)->Double {
        let phase=time.truncatingRemainder(dividingBy:2.2)/1.1
        return phase<=1 ? phase : 2-phase
    }
    static func isGreen(marker:Double,width:Double)->Bool {
        marker.isFinite && width.isFinite && width>=0 && width<=1 &&
        marker>=0.5-width/2 && marker<=0.5+width/2
    }
}

struct Clip {
    var frames: [NSImage]
    var width: CGFloat
    var height: CGFloat
    var foot: CGFloat
}

enum Facing: CaseIterable {
    case up, upRight, right, downRight, down, downLeft, left, upLeft
    static func from(dx: CGFloat, dy: CGFloat) -> Facing {
        if dy < 0 { return dx < 0 ? .upLeft : dx > 0 ? .upRight : .up }
        if dy > 0 { return dx < 0 ? .downLeft : dx > 0 ? .downRight : .down }
        return dx < 0 ? .left : .right
    }
    var head: String {
        switch self {
        case .up, .upLeft, .upRight: return "back"
        case .left, .downLeft: return "left"
        case .right, .downRight: return "right"
        case .down: return "front"
        }
    }
    var bodyWidth: CGFloat { self == .left || self == .right ? 0.65 : self == .down ? 1 : 0.85 }
    var handSide: CGFloat { self == .left || self == .downLeft || self == .upLeft ? -1 : 1 }
    var vector: CGPoint {
        let d:CGFloat=1/sqrt(2)
        switch self {
        case .up: return CGPoint(x:0,y:-1)
        case .upRight: return CGPoint(x:d,y:-d)
        case .right: return CGPoint(x:1,y:0)
        case .downRight: return CGPoint(x:d,y:d)
        case .down: return CGPoint(x:0,y:1)
        case .downLeft: return CGPoint(x:-d,y:d)
        case .left: return CGPoint(x:-1,y:0)
        case .upLeft: return CGPoint(x:-d,y:-d)
        }
    }
}

final class CourtView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    let resources = Bundle.main.resourceURL!
    var court: NSImage!
    var clips: [String: Clip] = [:]
    var heads: [String:NSImage] = [:]
    var facing: Facing = .down
    var keys = Set<UInt16>()
    var running = false
    var movementSpeed: CGFloat { running ? 5.6 : 3.5 }
    var player = CGPoint(x: 550, y: 530)
    var ball = CGPoint(x: 836, y: 570)
    var ownsBall = false
    var action = ""
    var elapsed: Double = 0
    var airborne: Double? = nil
    let jumpDuration = 0.9
    var airDuration = 0.9
    var actionDurationOverride: Double? = nil
    var releaseTimeOverride: Double? = nil
    var pose = CharacterPose.target(action:"",progress:0,airProgress:nil,walking:false,clock:0)
    var carriedBall: CGPoint? = nil
    var lastTick = ProcessInfo.processInfo.systemUptime
    var clock: Double = 0
    var score = 0
    var charging = false
    var chargeTime:Double = 0
    var gaugeWidth:Double = 0.32
    var gaugeMarker:Double = 0
    var gaugeFeedback:Double = 0
    var accurateShot = false
    // Frozen at release; a later lucky bank cannot change a failed timing.
    var shotCanScore = false
    var flight: ShotFlight?
    var rebound: LooseBall?
    var shotPointsByHoop = [2,2]
    var goalBall: (body:LooseBall,time:Double)?
    var takeoffFeet: [CGPoint]?
    var shotGroundStart: CGPoint? = nil
    var shotGroundEnd: CGPoint? = nil
    var shotDirection: CGPoint = .zero
    var timer: Timer?
    var message = "가운데 공에 가까이 가면 집습니다"
    var updateStatus = "업데이트 확인 중…"
    let world = CGSize(width: 1672, height: 1040)

    override init(frame: NSRect) {
        super.init(frame: frame)
        court = NSImage(contentsOf: resources.appendingPathComponent("basketball-court-v1.png"))
        load("idle", "character-idle-sheet-v1.png", 512, 768, 691)
        load("walk", "character-walk-sheet-v1.png", 512, 768, 691)
        load("shot", "character-standing-shot-sheet-v2.png", 512, 768, 691)
        load("jump", "character-jump-sheet-v2.png", 512, 948, 871)
        load("jumpShot", "character-jump-shot-sheet-v1.png", 512, 948, 871)
        load("block", "character-jump-block-sheet-v1.png", 512, 948, 871)
        load("dunk", "character-dunk-sheet-v1.png", 512, 948, 871)
        load("defense", "character-defense-sheet-v1.png", 640, 948, 871)
        for name in ["front","left","right","back"] {
            heads[name]=NSImage(contentsOf:resources.appendingPathComponent("head-\(name)-v2.png"))
        }
        timer = Timer(timeInterval:1/60,repeats:true) { [weak self] _ in
            guard let self else { return }
            let now=ProcessInfo.processInfo.systemUptime
            self.tick(dt:min(0.05,max(0.001,now-self.lastTick)))
            self.lastTick=now
        }
        RunLoop.main.add(timer!,forMode:.common)
    }
    required init?(coder: NSCoder) { fatalError() }
    func load(_ name: String, _ file: String, _ w: Int, _ h: Int, _ foot: Int) {
        guard let image = NSImage(contentsOf: resources.appendingPathComponent("body-v2/\(file)")),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        var frames: [NSImage] = []
        for i in 0..<(cg.width/w) {
            if let crop = cg.cropping(to: CGRect(x: i*w, y: 0, width: w, height: h)) {
                frames.append(NSImage(cgImage: crop, size: NSSize(width: w, height: h)))
            }
        }
        clips[name] = Clip(frames: frames, width: CGFloat(w), height: CGFloat(h), foot: CGFloat(foot))
    }
    override func keyDown(with event: NSEvent) {
        keys.insert(event.keyCode)
        if event.isARepeat { return }
        switch event.keyCode {
        case 49: if action.isEmpty && airborne == nil { takeoffFeet=groundedFeet(); airborne=0; airDuration=jumpDuration; begin("jump") }
        case 7:
            if ownsBall && (action.isEmpty || action == "jump") {
                startCharge()
            }
        case 6:
            if ownsBall && action.isEmpty {
                if let aim=aimedHoop(), aim.distance<=220 { takeoffFeet=groundedFeet(); airborne=0; airDuration=2.16; begin("dunk"); message = "덩크!" }
                else { message = "덩크는 가까운 골대를 바라볼 때 가능합니다" }
            }
        case 8:
            if airborne != nil && ["jump","block"].contains(action) {
                if action != "block" { begin("block") }; message = "점프 블로킹"
            }
            else if action.isEmpty { begin("defense"); message = "수비 자세" }
        case 15: reset()
        default: break
        }
    }
    override func keyUp(with event: NSEvent) {
        keys.remove(event.keyCode)
        if event.keyCode == 7 && charging { releaseCharge() }
    }
    func startCharge() {
        charging=true; chargeTime=0; gaugeMarker=0; accurateShot=false
        begin("charge"); updateGauge(); message="X를 놓아 초록 구간에 맞추세요"
    }
    func releaseCharge() {
        guard charging && ownsBall else { return }
        updateGauge()
        charging=false; accurateShot=ShotGauge.isGreen(marker:gaugeMarker,width:gaugeWidth)
        gaugeFeedback=0.8
        begin(airborne != nil ? "jumpShot" : "shot")
        elapsed=duration(action)*0.4
        let start=carriedBall ?? heldPosition()
        ownsBall=false; launchShot(from:start)
        message=aimedHoop() == nil ? "조준 방향이 골대를 벗어났습니다" : accurateShot ? "초록 타이밍 · 링 통과를 확인 중입니다" : gaugeMarker<0.5 ? "너무 빠름 · 짧은 슛" : "너무 늦음 · 긴 슛"
    }
    func cancelCharge() {
        if charging { charging=false; action=""; elapsed=0 }
    }
    override func flagsChanged(with event: NSEvent) {
        running = event.modifierFlags.contains(.shift)
    }
    override func resignFirstResponder() -> Bool { clearInput(); return true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self,name:NSWindow.didResignKeyNotification,object:nil)
        if let window {
            NotificationCenter.default.addObserver(self,selector:#selector(clearInput),name:NSWindow.didResignKeyNotification,object:window)
        }
    }
    @objc private func clearInput() { keys.removeAll(); running=false; cancelCharge() }
    func begin(_ name: String) {
        action=name; elapsed=0; actionDurationOverride=nil; releaseTimeOverride=nil
        if ["jumpShot","block"].contains(name), let air=airborne {
            actionDurationOverride=0.75
            releaseTimeOverride=max(0.015,min(0.30,(airDuration*0.8-air)*0.45))
        }
    }
    func reset() {
        player=CGPoint(x:550,y:530); ball=CGPoint(x:836,y:570)
        facing = .down
        ownsBall=false; action=""; actionDurationOverride=nil; airborne=nil; flight=nil; rebound=nil; score=0
        airDuration=jumpDuration
        releaseTimeOverride=nil; carriedBall=nil
        charging=false; chargeTime=0; gaugeFeedback=0; accurateShot=false; elapsed=0
        shotCanScore=false
        shotGroundStart=nil; shotGroundEnd=nil
        goalBall=nil; takeoffFeet=nil; shotPointsByHoop=[2,2]
        pose=CharacterPose.target(action:"",progress:0,airProgress:nil,walking:false,clock:clock)
        message="가운데 공에 가까이 가면 집습니다"
    }
    func duration(_ name: String) -> Double {
        if name == action, let override=actionDurationOverride { return override }
        switch name { case "jump": return jumpDuration; case "shot": return 1.8
        case "defense": return 1.6; default: return 2.16 }
    }
    func jumpHeight() -> CGFloat {
        guard let air=airborne else { return 0 }
        let t=air/airDuration
        return CGFloat(t > 0.2 && t < 0.8 ? 150*sin(.pi*(t-0.2)/0.6) : 0)*0.30
    }
    func groundedFeet()->[CGPoint] {
        [8,10].map {
            let p=pose.joints[$0]
            return CGPoint(x:player.x+(p.x-256)*0.3*facing.bodyWidth*facing.handSide,y:player.y)
        }
    }
    func shotOrigin()->CGPoint { CGPoint(x:(carriedBall ?? heldPosition()).x,y:player.y) }
    func aimedHoop(from origin:CGPoint? = nil)->(index:Int,distance:CGFloat,end:CGPoint)? {
        ShotAssist.target(from:origin ?? shotOrigin(),facing:facing.vector)
    }
    func updateGauge() {
        gaugeMarker=ShotGauge.marker(time:chargeTime)
        let distance=aimedHoop()?.distance ?? Hoop.all.map { hypot(player.x-$0.center.x,player.y-$0.center.y) }.min()!
        gaugeWidth=ShotGauge.width(distance:distance)
    }
    func awardGoal(_ index:Int,body:LooseBall) {
        guard shotCanScore else {
            // Arcade timing rule: reject an accidental entry before it is drawn.
            var miss=body
            miss.scoredHoop=nil; miss.rimHits += 1
            miss.height=Hoop.height+Basketball.radius+3
            miss.velocity=CGPoint(x:index == 0 ? 180 : -180,y:body.velocity.y*0.35)
            miss.verticalVelocity=max(180,min(360,abs(body.verticalVelocity)*0.45))
            flight=nil; goalBall=nil; rebound=miss; ball=miss.screen
            message="초록 구간 밖 · 슛 실패, 리바운드를 잡으세요"
            return
        }
        shotCanScore=false
        score += shotPointsByHoop[index]
        goalBall=(body,0); flight=nil; rebound=nil; ball=body.screen
        message="골! \(shotPointsByHoop[index])점 · 링 통과 확인"
    }
    func launchShot(from start: CGPoint) {
        let ground=CGPoint(x:start.x,y:player.y)
        let aim=aimedHoop(from:ground)
        shotCanScore=aim.map { accurateShot || (action == "dunk" && $0.distance<=220) } ?? false
        let direction=aim.map { CGPoint(x:($0.end.x-ground.x)/$0.distance,y:($0.end.y-ground.y)/$0.distance) } ?? facing.vector
        var range:CGFloat=aim?.distance ?? 620
        if aim != nil && !accurateShot && action != "dunk" {
            let error=CGFloat(abs(gaugeMarker-0.5))
            range += (gaugeMarker<0.5 ? -1 : 1)*max(65,range*error*0.5)
            range=max(20,range)
        }
        if aim == nil {
            var low:CGFloat=0, high=range
            if !CourtBounds.contains(CGPoint(x:ground.x+direction.x*range,y:ground.y+direction.y*range)) {
                for _ in 0..<30 {
                    let mid=(low+high)/2
                    if CourtBounds.contains(CGPoint(x:ground.x+direction.x*mid,y:ground.y+direction.y*mid)) { low=mid } else { high=mid }
                }
                range=low
            }
        }
        let end=CGPoint(x:ground.x+direction.x*range,y:ground.y+direction.y*range)
        shotGroundStart=ground; shotGroundEnd=end; shotDirection=direction
        let feet=airborne != nil ? (takeoffFeet ?? groundedFeet()) : groundedFeet()
        shotPointsByHoop=Hoop.all.indices.map { CourtGeometry.shotPoints(feet:feet,hoopIndex:$0) }
        flight=ShotFlight(startGround:ground,startHeight:max(0,ground.y-Basketball.radius-start.y),endGround:end,distance:range,points:shotPointsByHoop[aim?.index ?? 0],targetHeight:aim != nil ? Hoop.height : 0)
    }
    func tick(dt: Double = 1/60) {
        clock += dt
        gaugeFeedback=max(0,gaugeFeedback-dt)
        if charging {
            chargeTime += dt
        }
        if let air=airborne {
            airborne=air+dt
            if airborne! >= airDuration { airborne=nil; takeoffFeet=nil }
        }
        var dx: CGFloat=0, dy: CGFloat=0
        if keys.contains(123) { dx -= 1 }; if keys.contains(124) { dx += 1 }
        if keys.contains(126) { dy -= 1 }; if keys.contains(125) { dy += 1 }
        if dx != 0 || dy != 0 {
            facing = Facing.from(dx:dx,dy:dy)
            let length=sqrt(dx*dx+dy*dy)
            player.x += dx/length*movementSpeed*CGFloat(dt*60); player.y += dy/length*movementSpeed*CGFloat(dt*60)
        }
        player.y=max(CourtBounds.top,min(CourtBounds.bottom,player.y))
        let inset=CourtBounds.inset(at:player.y)
        player.x=max(inset,min(world.width-inset,player.x))
        if !action.isEmpty {
            let previous=elapsed; elapsed += dt
            let release=releaseTimeOverride ?? duration(action)*(action == "shot" ? 0.4 : action == "dunk" ? 0.55 : 0.49)
            if ownsBall && ["shot","jumpShot","dunk"].contains(action) && previous < release && elapsed >= release {
                if action == "dunk" && (aimedHoop()?.distance ?? CGFloat.infinity)>220 {
                    begin("jump"); actionDurationOverride=max(0.05,airDuration-(airborne ?? 0))
                    message="덩크 취소 · 골대에서 멀어져 공을 유지합니다"
                } else {
                    ownsBall=false
                    let start=carriedBall ?? heldPosition()
                    launchShot(from:start)
                }
            }
            if action == "defense" && keys.contains(8) && elapsed > 0.55 && elapsed < 1.2 { elapsed=0.8 }
            if !charging && elapsed >= duration(action) { action=""; elapsed=0 }
        }
        if var goal=goalBall {
            goal.time += dt
            ball=CGPoint(x:goal.body.screen.x,y:goal.body.screen.y+CGFloat(goal.time)*85)
            if goal.time>=0.30 { goalBall=nil; ball=CGPoint(x:836,y:570); message="골! 공이 가운데로 돌아왔습니다" }
            else { goalBall=goal }
        } else if var f=flight {
            let oldTime=f.time; f.time += dt
            var previous=f.sample(at:oldTime)
            var interrupted=false
            let steps=max(1,Int(ceil(dt*480)))
            for index in 1...steps {
                var body=f.sample(at:min(f.duration,oldTime+dt*Double(index)/Double(steps)))
                if body.collideWithHoops() {
                    rebound=body; flight=nil; ball=body.screen; interrupted=true
                    message=body.boardHits>0 ? "백보드에 맞고 튕겼습니다" : "림에 맞고 튕겼습니다"
                    break
                }
                if let hoop=ShotFlight.crossingHoop(from:previous,to:body) {
                    awardGoal(hoop,body:body); interrupted=true; break
                }
                previous=body
            }
            if !interrupted {
                ball=previous.screen
                if f.time>=f.duration {
                    rebound=previous; flight=nil; message="슛 실패 · 리바운드 공을 잡으세요"
                } else {
                    flight=f
                }
            }
        } else if var r=rebound {
            r.step(dt:dt); ball=r.screen
            if let hoop=r.scoredHoop { awardGoal(hoop,body:r) }
            else if r.height<35 && hypot(player.x-r.ground.x,player.y-r.ground.y)<60 && action.isEmpty {
                ownsBall=true; rebound=nil; shotCanScore=false; message="리바운드 획득"
            } else { rebound=r }
        } else if !ownsBall && hypot(player.x-ball.x,player.y-ball.y)<70 && action.isEmpty {
            ownsBall=true; shotCanScore=false; message="공 획득 · X 슛 / Space 점프 / Z 덩크"
        }
        let target=CharacterPose.target(action:action,progress:elapsed/duration(action),airProgress:airborne.map { $0/airDuration },walking:dx != 0 || dy != 0,clock:clock)
        pose.approach(target,dt:dt)
        // Navigation uses grounded feet, never the head or airborne sprite height.
        let footOffsets=[8,10].map { (pose.joints[$0].x-256)*0.3*facing.bodyWidth*facing.handSide }
        player.x=max(CourtBounds.inset(at:player.y)-footOffsets.min()!,
                     min(world.width-CourtBounds.inset(at:player.y)-footOffsets.max()!,player.x))
        if ownsBall {
            let target=heldPosition()
            if var current=carriedBall {
                let f=CGFloat(1-exp(-dt/0.04))
                current.x += (target.x-current.x)*f; current.y += (target.y-current.y)*f
                carriedBall=current
            } else { carriedBall=target }
        } else { carriedBall=nil }
        if charging { updateGauge() }
        needsDisplay=true
    }
    func heldPosition() -> CGPoint {
        if !action.isEmpty {
            let hand=pose.joints[6]
            return CGPoint(x:player.x+(hand.x-256+8)*0.3*facing.bodyWidth*facing.handSide,
                           y:player.y+(hand.y-691-24)*0.3-jumpHeight())
        }
        let bounce=action.isEmpty ? CGFloat(abs(sin(clock*5.2)))*65 : 65
        return CGPoint(x:player.x+31*facing.bodyWidth*facing.handSide,y:player.y-Basketball.radius-bounce-jumpHeight())
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        let scale=min(bounds.width/world.width,bounds.height/world.height)
        let transform=NSAffineTransform()
        transform.translateX(by:(bounds.width-world.width*scale)/2,yBy:(bounds.height-world.height*scale)/2)
        transform.scale(by:scale); transform.concat()
        court.draw(in:NSRect(x:0,y:0,width:1672,height:941),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        // The visible line and point classification use the same court geometry.
        NSGraphicsContext.saveGraphicsState()
        let courtClip=NSBezierPath()
        courtClip.move(to:CGPoint(x:CourtBounds.inset(at:CourtBounds.top),y:CourtBounds.top))
        courtClip.line(to:CGPoint(x:world.width-CourtBounds.inset(at:CourtBounds.top),y:CourtBounds.top))
        courtClip.line(to:CGPoint(x:world.width-CourtBounds.inset(at:CourtBounds.bottom),y:CourtBounds.bottom))
        courtClip.line(to:CGPoint(x:CourtBounds.inset(at:CourtBounds.bottom),y:CourtBounds.bottom)); courtClip.close(); courtClip.addClip()
        NSColor(calibratedRed:1,green:0.82,blue:0.24,alpha:0.8).setStroke()
        for left in [true,false] {
            let points=CourtGeometry.threePointPolyline(left:left)
            let path=NSBezierPath(); path.lineWidth=2
            path.setLineDash([7,7],count:2,phase:0)
            path.move(to:points[0]); for point in points.dropFirst() { path.line(to:point) }; path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        if ownsBall {
            let aim=aimedHoop()
            let origin=shotOrigin()
            let direction=aim.map { CGPoint(x:($0.end.x-origin.x)/$0.distance,y:($0.end.y-origin.y)/$0.distance) } ?? facing.vector
            let color=aim != nil ? NSColor.systemGreen : NSColor.systemOrange
            color.setStroke()
            let arrow=NSBezierPath(); arrow.lineWidth=3
            let tip=CGPoint(x:player.x+direction.x*65,y:player.y+direction.y*65)
            arrow.move(to:player); arrow.line(to:tip)
            arrow.move(to:CGPoint(x:tip.x-direction.x*12-direction.y*7,y:tip.y-direction.y*12+direction.x*7))
            arrow.line(to:tip); arrow.line(to:CGPoint(x:tip.x-direction.x*12+direction.y*7,y:tip.y-direction.y*12-direction.x*7)); arrow.stroke()
            if let aim {
                let hoop=Hoop.all[aim.index]
                let ring=NSBezierPath(ovalIn:NSRect(x:hoop.center.x-37,y:hoop.center.y-Basketball.radius-Hoop.height-15,width:74,height:30))
                ring.lineWidth=3; ring.stroke()
            }
            let label=aim.map { "\($0.index == 0 ? "왼쪽" : "오른쪽") 골대 · \(CourtGeometry.shotPoints(feet:airborne != nil ? takeoffFeet ?? groundedFeet() : groundedFeet(),hoopIndex:$0.index))점" } ?? "골대를 향해 방향을 맞추세요"
            label.draw(at:CGPoint(x:max(10,min(1400,player.x-85)),y:player.y+22),withAttributes:[.font:NSFont.systemFont(ofSize:16,weight:.semibold),.foregroundColor:color])
        }
        NSColor.black.withAlphaComponent(0.2).setFill()
        NSBezierPath(ovalIn:NSRect(x:player.x-27,y:player.y-8,width:54,height:16)).fill()
        let s:CGFloat=0.30
        func joint(_ index:Int)->CGPoint {
            let p=pose.joints[index]
            return CGPoint(x:player.x+(p.x-256)*s*facing.bodyWidth*facing.handSide,
                           y:player.y+(p.y-691)*s-jumpHeight())
        }
        NSColor.black.setStroke()
        for chain in [[0,2],[1,3,4],[1,5,6],[2,7,8],[2,9,10]] {
            let path=NSBezierPath(); path.lineWidth=12*s; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.move(to:joint(chain[0])); for index in chain.dropFirst() { path.line(to:joint(index)) }; path.stroke()
        }
        heads[facing.head]?.draw(in:NSRect(x:player.x-37.5,y:player.y+(pose.headY-691)*s-jumpHeight(),width:75,height:84),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        if !ownsBall {
            let ground:CGPoint
            if let r=rebound { ground=r.ground }
            else if let goal=goalBall { ground=goal.body.ground }
            else if let f=flight { ground=f.sample(at:f.time).ground }
            else { ground=CGPoint(x:ball.x,y:ball.y+Basketball.radius) }
            NSColor.black.withAlphaComponent(0.18).setFill()
            NSBezierPath(ovalIn:NSRect(x:ground.x-10,y:ground.y-3,width:20,height:6)).fill()
        }
        let b=ownsBall ? (carriedBall ?? heldPosition()) : ball
        NSColor(calibratedRed:0.95,green:0.49,blue:0.12,alpha:1).setFill()
        let radius=Basketball.radius
        let circle=NSBezierPath(ovalIn:NSRect(x:b.x-radius,y:b.y-radius,width:radius*2,height:radius*2)); circle.fill()
        NSColor.black.setStroke(); circle.lineWidth=1.5; circle.stroke()
        let seam=NSBezierPath(); seam.move(to:NSPoint(x:b.x-radius,y:b.y)); seam.line(to:NSPoint(x:b.x+radius,y:b.y)); seam.stroke()
        if charging || gaugeFeedback>0 {
            let rect=NSRect(x:max(12,min(world.width-262,player.x-125)),y:max(18,player.y-250-jumpHeight()),width:250,height:16)
            NSColor.black.setFill(); rect.insetBy(dx:-3,dy:-3).fill()
            NSGradient(colors:[.red,.orange,.yellow,.orange,.red])!.draw(in:rect,angle:0)
            NSColor.systemGreen.setFill()
            NSRect(x:rect.midX-rect.width*gaugeWidth/2,y:rect.minY,width:rect.width*gaugeWidth,height:rect.height).fill()
            NSColor.white.setFill()
            NSRect(x:rect.minX+rect.width*gaugeMarker-1.5,y:rect.minY-3,width:3,height:22).fill()
        }
        NSColor(calibratedWhite:0.10,alpha:1).setFill(); NSRect(x:0,y:941,width:1672,height:99).fill()
        let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:24,weight:.medium),.foregroundColor:NSColor.white]
        "방향키 이동   Shift 달리기   Space 점프   X 누르고 놓기: 슛   Z 덩크   C 수비 / 블로킹   R 초기화".draw(at:NSPoint(x:45,y:960),withAttributes:attrs)
        "\(score)점 · \(message) · \(updateStatus)".draw(at:NSPoint(x:45,y:1000),withAttributes:[.font:NSFont.systemFont(ofSize:18),.foregroundColor:NSColor.lightGray])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu=NSMenu(); let item=NSMenuItem(); let appMenu=NSMenu()
        appMenu.addItem(withTitle:"Full Court Stickman 종료",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        item.submenu=appMenu; menu.addItem(item); NSApp.mainMenu=menu
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1200,height:747),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Full Court Stickman"
        window.minSize=NSSize(width:840,height:550)
        let view=CourtView(frame:window.contentView!.bounds)
        view.autoresizingMask=[.width,.height]; window.contentView=view
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps:true)
        AutoUpdater.check { [weak view] status in view?.updateStatus=status; view?.needsDisplay=true }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main
enum Main {
    static func main() {
        let app=NSApplication.shared
        if let flag=CommandLine.arguments.firstIndex(of:"--render-preview"),flag+1<CommandLine.arguments.count {
            let view=CourtView(frame:NSRect(x:0,y:0,width:1672,height:1040)); view.timer?.invalidate()
            view.player=CGPoint(x:980,y:530); view.facing = .right; view.ownsBall=true
            view.startCharge(); view.chargeTime=0.55; view.elapsed=0.55
            view.pose=CharacterPose.target(action:"charge",progress:0.55/2.16,airProgress:nil,walking:false,clock:0)
            view.carriedBall=view.heldPosition(); view.updateGauge()
            view.updateStatus="v\(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "")"
            let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[flag+1]))
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            let view=CourtView(frame:NSRect(x:0,y:0,width:1200,height:747))
            view.timer?.invalidate()
            runShotPhysicsTests(); runCourtGeometryTests()
            precondition(abs(ShotGauge.width(distance:200)-0.32)<0.0001)
            precondition(abs(ShotGauge.width(distance:450)-0.16)<0.0001)
            precondition(abs(ShotGauge.width(distance:650)-0.06)<0.0001)
            for width in [0.32,0.16,0.06] {
                for sign in [-1.0,1.0] {
                    precondition(ShotGauge.isGreen(marker:0.5+sign*width/2,width:width),"Green edge must match the visible window")
                    precondition(!ShotGauge.isGreen(marker:0.5+sign*(width/2+0.000001),width:width),"Outside green must fail without extra tolerance")
                }
            }
            view.ownsBall=true; view.startCharge(); view.tick(dt:0.55)
            precondition(view.charging && view.ownsBall && view.flight == nil)
            view.releaseCharge()
            precondition(view.accurateShot && !view.ownsBall && view.flight != nil)
            view.reset()
            view.ownsBall=true; view.startCharge(); view.tick(dt:0.1); view.releaseCharge()
            precondition(!view.accurateShot && view.flight != nil,"Early release must miss")
            view.reset(); view.ownsBall=true; view.startCharge(); view.cancelCharge()
            precondition(!view.charging && view.ownsBall && view.flight == nil,"Focus loss must cancel, not shoot")
            view.reset()
            for distance in stride(from:201,through:700,by:1) {
                precondition(ShotGauge.width(distance:CGFloat(distance))<=ShotGauge.width(distance:CGFloat(distance-1)),"Green window must only narrow")
            }
            for facing:Facing in [.left,.right] {
                for distance:CGFloat in [700,1000,1300] {
                    for green in [false,true] {
                        view.reset(); view.facing=facing
                        let hoopX:CGFloat=facing == .left ? 130 : 1537
                        view.player=CGPoint(x:hoopX-facing.vector.x*distance,y:530)
                        view.ownsBall=true; view.startCharge()
                        view.tick(dt:green ? 0.55 : 0.1); view.releaseCharge()
                        precondition(abs(view.gaugeWidth-0.06)<0.0001,"Wrong basket used for long-range gauge")
                        precondition(view.flight != nil && view.score==0,"Score must wait for a downward crossing")
                        if green { precondition(abs(view.shotGroundEnd!.x-hoopX)<0.001,"Long shot stops short of hoop") }
                        for _ in 0..<160 { view.tick() }
                        precondition(green ? view.score==3 : view.score==0,"Long shot scoring/collision regression")
                    }
                }
            }
            for dt in [1.0/60,1.0/120,0.05] {
                for hoop in Hoop.all {
                    for offset:CGFloat in [-8,0,8] {
                        view.reset(); view.keys.removeAll()
                        view.player=CGPoint(x:836,y:hoop.center.y+offset)
                        view.facing=hoop.center.x<836 ? .left : .right
                        view.accurateShot=true
                        precondition(view.aimedHoop() != nil,"Walking-sized offsets must be aimable")
                        view.launchShot(from:CGPoint(x:836,y:view.player.y-120))
                        for _ in 0..<Int(4/dt) { view.tick(dt:dt) }
                        precondition(view.score==3,"Green aim must score once at every frame rate")
                    }
                }
            }
            for facing in Facing.allCases {
                view.reset(); view.keys.removeAll(); view.facing=facing
                let hoop=Hoop.all[facing.vector.x<0 ? 0 : 1]
                view.player=CGPoint(x:hoop.center.x-facing.vector.x*170,y:hoop.center.y-facing.vector.y*170)
                view.ownsBall=true; view.startCharge(); view.tick(dt:0.55)
                precondition(view.aimedHoop() != nil,"All eight shot directions must support aiming")
                view.releaseCharge()
                for _ in 0..<160 { view.tick() }
                precondition(view.score>0 && view.score<=3,"Eight-direction green shot failed")
            }
            for (index,hoop) in Hoop.all.enumerated() {
                let sign:CGFloat=index == 0 ? -1 : 1
                for distance:CGFloat in [170,500,1000] {
                    for angle:CGFloat in [-20,20] {
                        let a=(distance>700 ? angle/2 : angle) * .pi/180
                        let origin=CGPoint(x:hoop.center.x-sign*distance*cos(a),y:hoop.center.y-distance*sin(a))
                        view.reset(); view.keys.removeAll(); view.player=origin
                        view.facing=index == 0 ? .left : .right
                        view.accurateShot=true; view.gaugeMarker=0.5
                        view.launchShot(from:CGPoint(x:origin.x,y:origin.y-120))
                        precondition(hypot(view.shotGroundEnd!.x-hoop.center.x,view.shotGroundEnd!.y-hoop.center.y)<0.001,"Assisted green shot must target ring center")
                        let expected=view.shotPointsByHoop[index], fixedDirection=view.shotDirection, fixedEnd=view.shotGroundEnd!
                        view.keys=[126]; view.tick(); view.keys.removeAll()
                        precondition(view.shotDirection==fixedDirection && view.shotGroundEnd==fixedEnd,"Assist must not home after release")
                        for _ in 0..<180 { view.tick() }
                        precondition(view.score==expected,"Angled assist must physically score exactly once")
                    }
                }
            }
            // Even an exact ring-center bank is rejected for failed timing.
            for (index,hoop) in Hoop.all.enumerated() {
                for dt in [1.0/60,1.0/120,0.05] {
                    view.reset(); view.keys.removeAll(); view.accurateShot=true
                    view.rebound=LooseBall(ground:hoop.center,velocity:.zero,height:260,verticalVelocity:-300,rimHits:1,boardHits:1)
                    for _ in 0..<Int(6/dt) { view.tick(dt:dt) }
                    precondition(view.score==0 && view.goalBall == nil && view.ball.x != 836,"Off-green bank must not score or reset")
                    view.reset(); view.player=CGPoint(x:836,y:530); view.facing=index == 0 ? .left : .right
                    view.ownsBall=true; view.begin("shot"); view.accurateShot=false
                    view.launchShot(from:CGPoint(x:836,y:300))
                    view.ownsBall=false; view.flight=nil; view.accurateShot=true
                    view.rebound=LooseBall(ground:hoop.center,velocity:.zero,height:260,verticalVelocity:-300)
                    for _ in 0..<Int(6/dt) { view.tick(dt:dt) }
                    precondition(view.score==0,"Released failure must not change with mutable gauge state")
                }
                for distance:CGFloat in [150,450,900] {
                    for sign in [-1.0,1.0] {
                        view.reset(); view.keys.removeAll()
                        let direction:CGFloat=index == 0 ? -1 : 1
                        view.player=CGPoint(x:hoop.center.x-direction*distance,y:530)
                        view.facing=index == 0 ? .left : .right; view.ownsBall=true
                        view.startCharge(); view.tick(dt:0.4)
                        view.chargeTime=(0.5+sign*(view.gaugeWidth/2+0.005))*1.1
                        view.releaseCharge()
                        precondition(!view.accurateShot && !view.shotCanScore,"Out-of-green release must be ineligible")
                        for _ in 0..<360 { view.tick() }
                        precondition(view.score==0 && view.goalBall == nil,"Early/late assisted shots must never score")
                    }
                }
            }
            view.reset(); view.keys.removeAll(); view.shotPointsByHoop=[3,3]; view.shotCanScore=true
            view.rebound=LooseBall(ground:Hoop.all[0].center,velocity:.zero,height:260,verticalVelocity:-300)
            for _ in 0..<180 { view.tick() }
            precondition(view.score==3 && view.ball.x==836,"A descending rebound scores once and resets")
            view.reset(); view.player=CGPoint(x:1380,y:530); view.facing = .right
            view.begin("dunk"); view.accurateShot=false
            view.launchShot(from:CGPoint(x:1380,y:330))
            precondition(view.shotCanScore,"Dunk must stay independent of the shot gauge")
            for _ in 0..<180 { view.tick() }
            precondition(view.score==2,"Valid dunk must still score")
            view.reset(); view.player=CGPoint(x:650,y:530); view.facing = .left
            view.takeoffFeet=view.groundedFeet(); view.airborne=0.4; view.player.x=450
            view.accurateShot=true; view.launchShot(from:CGPoint(x:450,y:350))
            precondition(view.shotPointsByHoop[0]==3,"Jump shots must use takeoff feet")
            view.reset(); view.player=CGPoint(x:450,y:530); view.facing = .left
            view.accurateShot=true; view.launchShot(from:CGPoint(x:450,y:350))
            precondition(view.shotPointsByHoop[0]==2,"Ground shots must use current feet")
            view.reset(); view.ownsBall=true; view.facing = .right
            view.airborne=1.18; view.airDuration=2.16; view.begin("dunk"); view.elapsed=1.18
            view.player=CGPoint(x:800,y:530); view.tick(dt:0.02)
            precondition(view.ownsBall && view.flight == nil && view.action == "jump","A dunk leaving range must keep the ball")
            view.reset()
            precondition(view.court != nil && view.clips.count == 8 && view.heads.count == 4,"Missing assets")
            for dx:CGFloat in [-1,0,1] {
                for dy:CGFloat in [-1,0,1] where dx != 0 || dy != 0 {
                    view.keys.removeAll(); view.player=CGPoint(x:836,y:600)
                    if dx<0 { view.keys.insert(123) }; if dx>0 { view.keys.insert(124) }
                    if dy<0 { view.keys.insert(126) }; if dy>0 { view.keys.insert(125) }
                    view.tick()
                    precondition(view.facing == Facing.from(dx:dx,dy:dy),"Direction mismatch")
                    precondition(abs(hypot(view.player.x-836,view.player.y-600)-3.5)<0.001,"Diagonal speed mismatch")
                    let last=view.facing; view.keys.removeAll(); view.tick()
                    precondition(view.facing==last,"Direction must persist at rest")
                }
            }
            view.reset()
            view.keys=[126]
            for _ in 0..<200 { view.tick() }
            precondition(view.player.y==CourtBounds.top && view.player.y<390,"Upper court is still blocked")
            view.keys=[124,126]
            for _ in 0..<500 { view.tick() }
            precondition(CourtBounds.contains(view.player),"Player left upper corner")
            for foot in [8,10] {
                let x=view.player.x+(view.pose.joints[foot].x-256)*0.3*view.facing.bodyWidth*view.facing.handSide
                precondition(CourtBounds.contains(CGPoint(x:x,y:view.player.y)),"Grounded feet must stay inside court")
            }
            var upperBall=LooseBall(ground:CGPoint(x:836,y:300),velocity:CGPoint(x:0,y:-400),height:0,verticalVelocity:0)
            upperBall.step(dt:0.25)
            precondition(upperBall.ground.y>=CourtBounds.top && upperBall.velocity.y>0,"Ball upper boundary mismatch")
            view.keys.removeAll(); view.reset()
            for fast in [false,true] {
                view.running=fast; view.player=CGPoint(x:836,y:600)
                view.keys=[124,125]; view.tick()
                let expected:CGFloat=fast ? 5.6 : 3.5
                precondition(abs(hypot(view.player.x-836,view.player.y-600)-expected)<0.001,"Run speed mismatch")
            }
            view.keys.removeAll(); view.running=false; view.reset()
            view.player=view.ball; view.tick()
            precondition(view.ownsBall,"Pickup failed")
            view.begin("jump"); view.elapsed=0.45; view.airborne=0.45
            precondition(view.jumpHeight()>40,"Jump failed")
            view.begin("jumpShot")
            precondition(view.releaseTimeOverride!<=view.airDuration-view.airborne!,"Air shot timing failed")
            view.action="jump"; view.elapsed=0.45; view.airborne=0.45
            for _ in 0..<28 { view.tick() }
            precondition(view.airborne==nil && view.action.isEmpty,"Fast landing failed")
            view.reset(); view.player=CGPoint(x:1000,y:530); view.facing = .right; view.gaugeMarker=0.1
            view.launchShot(from:CGPoint(x:1000,y:300))
            for _ in 0..<160 { view.tick() }
            precondition(view.score==0 && view.rebound != nil,"Miss must rebound")
            for _ in 0..<70 { view.tick() }
            precondition(view.ball.x != 836,"Miss must not reset to center")
            view.reset(); view.player=CGPoint(x:1300,y:530); view.facing = .right; view.accurateShot=true
            view.launchShot(from:CGPoint(x:1300,y:300))
            for _ in 0..<160 { view.tick() }
            precondition(view.score==2 && view.ball.x==836,"Physical score reset failed")
            for facing in Facing.allCases {
                view.reset(); view.player=CGPoint(x:836,y:600); view.facing=facing
                view.launchShot(from:CGPoint(x:836,y:520))
                let end=view.shotGroundEnd!, v=view.shotDirection
                let dx=end.x-836, dy=end.y-600
                precondition(Double(v.x*facing.vector.x+v.y*facing.vector.y)>=ShotAssist.minimumAlignment-0.0001,"Shot turns outside forward aim cone")
                precondition(dx*v.x+dy*v.y>0,"Shot flies backward")
                precondition(abs(dx*v.y-dy*v.x)<0.001,"Shot must follow its release direction")
                view.keys=[123]; view.tick()
                precondition(view.shotDirection==v,"Shot direction changed after release")
            }
            for dt in [1.0/60,1.0/120] {
                var loose=LooseBall(ground:CGPoint(x:900,y:600),velocity:CGPoint(x:120,y:0),height:225)
                var firstPeak:CGFloat=0, secondPeak:CGFloat=0
                for _ in 0..<Int(8/dt) {
                    loose.step(dt:dt)
                    precondition(loose.height>=0,"Ball went below floor")
                    if loose.bounces==1 { firstPeak=max(firstPeak,loose.height) }
                    if loose.bounces==2 { secondPeak=max(secondPeak,loose.height) }
                }
                precondition(loose.bounces>=2 && firstPeak>20 && secondPeak>5 && secondPeak<firstPeak,"Rebound does not decay")
                precondition(loose.settled,"Rebound never settles")
            }
            for hoop in Hoop.all {
                for frameTime in [1.0/60,0.05] {
                    let rimDirection:CGFloat=hoop.center.x>800 ? 1 : -1
                    var rimBall=LooseBall(ground:CGPoint(x:hoop.center.x-rimDirection*65,y:530),velocity:CGPoint(x:rimDirection*900,y:0),height:Hoop.height,verticalVelocity:0)
                    for _ in 0..<Int(ceil(0.04/frameTime)) { rimBall.step(dt:frameTime) }
                    precondition(rimBall.rimHits>0 && rimBall.velocity.x*rimDirection<0,"Fast rim collision failed")
                    let sign:CGFloat=hoop.boardX>800 ? 1 : -1
                    var boardBall=LooseBall(ground:CGPoint(x:hoop.boardX-sign*30,y:550),velocity:CGPoint(x:sign*1200,y:0),height:270,verticalVelocity:0)
                    boardBall.step(dt:0.05)
                    precondition(boardBall.boardHits>0 && boardBall.velocity.x*sign<0,"Backboard reflection failed")
                }
                var clearBall=LooseBall(ground:hoop.center,velocity:.zero,height:260,verticalVelocity:-300)
                clearBall.step(dt:0.15)
                precondition(clearBall.rimHits==0 && clearBall.boardHits==0,"Clear hoop center falsely collides")
                let highDirection:CGFloat=hoop.center.x>800 ? 1 : -1
                var highBall=LooseBall(ground:CGPoint(x:hoop.center.x-highDirection*65,y:530),velocity:CGPoint(x:highDirection*900,y:0),height:410,verticalVelocity:0)
                highBall.step(dt:0.1)
                precondition(highBall.rimHits==0 && highBall.boardHits==0,"Ball above hoop falsely collides")
            }
            view.reset(); view.keys.removeAll()
            view.begin("defense"); view.keys.insert(8); view.elapsed=0.7; view.tick()
            precondition(view.action=="defense" && view.elapsed==0.8,"Defense hold failed")
            for motion in ["jumpShot","block"] {
                for inputTime in [0.2,0.45,0.65] {
                    view.reset(); view.keys.removeAll(); view.airborne=0; view.begin("jump")
                    for _ in 0..<Int(inputTime*60) { view.tick() }
                    let before=view.pose; let height=view.jumpHeight(); let air=view.airborne
                    view.begin(motion)
                    precondition(view.pose.joints==before.joints && view.pose.headY==before.headY,"Pose snapped on action change")
                    precondition(view.airborne==air && view.jumpHeight()==height,"Jump restarted on action change")
                    var last=view.pose; var lastHeight=view.jumpHeight()
                    for _ in 0..<75 {
                        view.tick()
                        for j in last.joints.indices {
                            let dx=(last.joints[j].x-view.pose.joints[j].x)*0.3
                            let dy=(last.joints[j].y-view.pose.joints[j].y)*0.3-lastHeight+view.jumpHeight()
                            precondition(hypot(dx,dy)<12,"Motion discontinuity: \(motion), input \(inputTime), joint \(j), delta \(hypot(dx,dy)), air \(String(describing:view.airborne)), action \(view.action)")
                        }
                        last=view.pose; lastHeight=view.jumpHeight()
                    }
                }
            }
            print("PASS: strict green timing/frozen eligibility/no lucky banks, dunks, physics scoring, 2/3 points, aim assist, rebounds and motion")
            return
        }
        app.setActivationPolicy(.regular)
        let delegate=AppDelegate(); app.delegate=delegate; app.run()
    }
}
