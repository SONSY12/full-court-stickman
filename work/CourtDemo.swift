import AppKit

struct Clip {
    var frames: [NSImage]
    var width: CGFloat
    var height: CGFloat
    var foot: CGFloat
}

struct DefenseOpponent {
    var position=CGPoint(x:1100,y:530)
    var facing:Facing = .right
    var ownsBall=true
    var phase="dribble"
    var elapsed:Double=0
    var pickupDelay:Double=0
    var pose=CharacterPose.target(action:"",progress:0,airProgress:nil,walking:false,clock:0)
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
    var movementSpeed: CGFloat { ["handsUp","steal"].contains(action) ? (running ? 5.04 : 3.15) : charging ? 1.75 : running ? 5.6 : 3.5 }
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
    var defensePractice=false
    var opponent=DefenseOpponent()
    var opponentScore=0
    var steals=0
    var blocks=0
    var defenseCooldown:Double=0
    var defenseContactUsed=false
    var defenseFeedback:Double=0
    var defenseReach:CGFloat=0
    var shotByOpponent=false
    var shotBlocked=false
    var charging = false
    var chargeTime:Double = 0
    var gaugeWidth:Double = 0.32
    var gaugeMarker:Double = 0
    var gaugeFeedback:Double = 0
    var gaugeContest:Double = 0
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
    var exitToMenu:(()->Void)?
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
        case 53: clearInput();exitToMenu?()
        case 49: startJump()
        case 7:
            if ownsBall && (action.isEmpty || action == "jump") {
                startCharge()
            }
        case 6:
            if ownsBall && action.isEmpty {
                if let aim=aimedHoop(), aim.distance<=220 { takeoffFeet=groundedFeet(); airborne=0; airDuration=2.16; begin("dunk"); message = "덩크!" }
                else { message = "덩크는 가까운 골대를 바라볼 때 가능합니다" }
            }
        case 8: startDefense()
        case 11: startSteal()
        case 9: startBlock()
        case 48: defensePractice.toggle(); reset()
        case 15: reset()
        default: break
        }
    }
    override func keyUp(with event: NSEvent) {
        keys.remove(event.keyCode)
        if event.keyCode == 7 && charging { releaseCharge() }
        if event.keyCode == 8 && action == "handsUp" { action=""; elapsed=0 }
    }
    func startJump() {
        guard airborne == nil && (action.isEmpty || ["handsUp","steal"].contains(action) || charging) else { return }
        takeoffFeet=groundedFeet(); airborne=0; airDuration=jumpDuration
        if charging { message="점프슛 준비 · X를 놓으면 현재 높이에서 발사합니다";return }
        if action == "handsUp" { message="점프 견제 · 블로킹은 V로 따로 입력하세요";return }
        begin("jump")
    }
    func startBlock() {
        guard !ownsBall && ["","jump","handsUp","steal"].contains(action) else { return }
        if airborne == nil { takeoffFeet=groundedFeet();airborne=0;airDuration=jumpDuration }
        begin("block");defenseContactUsed=false
        message="V 점프 블로킹 · 공이 손에 닿으면 쳐냅니다"
    }
    func startDefense() {
        guard !ownsBall else { message="공을 소유한 동안에는 수비할 수 없습니다"; return }
        if action.isEmpty || action == "jump" {
            begin("handsUp"); message="C 손 올린 견제 · B 스틸 / V 점프 블로킹"
        } else { return }
    }
    func startSteal() {
        guard !ownsBall && airborne == nil && defenseCooldown<=0 && ["","handsUp"].contains(action) else { return }
        begin("steal"); message="B 스틸 · 타이밍을 맞춰 공에 손을 뻗으세요"
        defenseCooldown=DefensePhysics.cooldown; defenseContactUsed=false
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
        let coverage=ShotGauge.contestLabel(gaugeContest)
        let timing=ShotGauge.timingLabel(marker:gaugeMarker,width:gaugeWidth)+(accurateShot ? " · 링 통과 확인 중" : gaugeMarker<0.5 ? " · 짧은 슛" : " · 긴 슛")
        message=aimedHoop() == nil ? "조준 방향이 골대를 벗어났습니다" : "\(coverage) · \(timing)"
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
    @objc private func clearInput() {
        keys.removeAll(); running=false; cancelCharge()
        if action == "handsUp" { action="";elapsed=0 }
    }
    func begin(_ name: String) {
        action=name; elapsed=0; actionDurationOverride=nil; releaseTimeOverride=nil
        if ["jumpShot","block"].contains(name), let air=airborne {
            actionDurationOverride=name == "block" ? 0.9 : 0.75
            releaseTimeOverride=max(0.015,min(0.30,(airDuration*0.8-air)*0.45))
        }
    }
    func reset() {
        player=CGPoint(x:550,y:530); ball=CGPoint(x:836,y:570)
        facing = .down
        ownsBall=false; action=""; actionDurationOverride=nil; airborne=nil; flight=nil; rebound=nil; score=0
        airDuration=jumpDuration
        releaseTimeOverride=nil; carriedBall=nil
        charging=false; chargeTime=0; gaugeFeedback=0; gaugeContest=0; accurateShot=false; elapsed=0
        shotCanScore=false
        shotByOpponent=false; shotBlocked=false
        defenseCooldown=0; defenseContactUsed=false; defenseFeedback=0; defenseReach=0
        opponent=DefenseOpponent(); opponentScore=0; steals=0; blocks=0
        shotGroundStart=nil; shotGroundEnd=nil
        goalBall=nil; takeoffFeet=nil; shotPointsByHoop=[2,2]
        pose=CharacterPose.target(action:"",progress:0,airProgress:nil,walking:false,clock:clock)
        message="가운데 공에 가까이 가면 집습니다"
        if defensePractice {
            player=CGPoint(x:1190,y:530); facing = .left
            ball=opponentBall().screen
            message="수비 연습 · C 손 올린 견제 · B 스틸 · V 점프 블로킹 · Tab 모드 전환"
        }
    }
    func duration(_ name: String) -> Double {
        if name == action, let override=actionDurationOverride { return override }
        switch name { case "jump": return jumpDuration; case "shot": return 0.75
        case "steal": return 0.45; case "handsUp": return 1.6; default: return 2.16 }
    }
    func jumpHeight() -> CGFloat {
        guard let air=airborne else { return 0 }
        let t=air/airDuration
        return JumpMotion.height(progress:t)
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
        gaugeContest=0
        if defensePractice && ["handsUp","block"].contains(opponent.phase) {
            let start=carriedBall ?? heldPosition()
            let shooter=DefenseHand(ground:CGPoint(x:start.x,y:player.y),height:max(0,player.y-Basketball.radius-start.y))
            let hands=[4,6].map { jointWorld($0,at:opponent.position,facing:opponent.facing,pose:opponent.pose,jump:0) }
            gaugeContest=DefensePhysics.contest(shooter:shooter,defender:opponent.position,facing:opponent.facing.vector,hands:hands)
            let delta=CGPoint(x:opponent.position.x-player.x,y:opponent.position.y-player.y)
            if delta.x*facing.vector.x+delta.y*facing.vector.y<0 { gaugeContest *= 0.35 }
        }
        let moving=keys.contains(123) || keys.contains(124) || keys.contains(125) || keys.contains(126)
        gaugeWidth=ShotGauge.width(distance:distance,moving:moving,contest:gaugeContest)
    }
    func opponentShotContest(_ body:LooseBall)->Double {
        guard ["handsUp","block"].contains(action) else { return 0 }
        var contest=DefensePhysics.contest(shooter:DefenseHand(ground:body.ground,height:body.height),defender:player,facing:facing.vector,hands:defenseHands())
        let delta=CGPoint(x:player.x-opponent.position.x,y:player.y-opponent.position.y)
        if delta.x*opponent.facing.vector.x+delta.y*opponent.facing.vector.y<0 { contest *= 0.35 }
        return contest
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
            message=shotBlocked ? "블로킹된 공 · 리바운드를 잡으세요" : "초록 구간 밖 · 슛 실패, 리바운드를 잡으세요"
            return
        }
        shotCanScore=false
        if shotByOpponent { opponentScore += shotPointsByHoop[index] }
        else { score += shotPointsByHoop[index] }
        goalBall=(body,0); flight=nil; rebound=nil; ball=body.screen
        message="\(shotByOpponent ? "상대 골" : "골")! \(shotPointsByHoop[index])점 · 링 통과 확인"
    }
    func launchShot(from start: CGPoint) {
        shotByOpponent=false; shotBlocked=false
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
    func jointWorld(_ index:Int,at position:CGPoint,facing direction:Facing,pose body:CharacterPose,jump:CGFloat,defending:CGFloat = 0)->DefenseHand {
        let p=body.joints[index]
        var x=(p.x-256)*0.3*direction.bodyWidth*direction.handSide
        var depth:CGFloat=0
        if defending>0 && [5,6].contains(index) {
            let weight=max(0,min(1,(body.joints[6].x-347)/149))*defending
            let reach:CGFloat=index == 6 ? 72 : 36
            let fullX:CGFloat=index == 6 ? 496 : 376
            let fullOffset=(fullX-256)*0.3*direction.bodyWidth*direction.handSide
            x += (direction.vector.x*reach-fullOffset)*weight
            depth=direction.vector.y*reach*weight/Hoop.groundDepthScale
        }
        return DefenseHand(ground:CGPoint(x:position.x+x,y:position.y+depth),height:(691-p.y)*0.3+jump-Basketball.radius)
    }
    func defenseHands()->[DefenseHand] {
        [4,6].map { jointWorld($0,at:player,facing:facing,pose:pose,jump:jumpHeight(),defending:defenseReach) }
    }
    func opponentBall()->LooseBall {
        let ground:CGPoint, height:CGFloat
        if ["charge","shot"].contains(opponent.phase) {
            let hand=opponent.pose.joints[6]
            ground=CGPoint(x:opponent.position.x+(hand.x-256+8)*0.3*opponent.facing.bodyWidth*opponent.facing.handSide,y:opponent.position.y)
            height=max(0,(691+24-hand.y)*0.3-Basketball.radius)
        } else {
            ground=CGPoint(x:opponent.position.x+31*opponent.facing.bodyWidth*opponent.facing.handSide,y:opponent.position.y)
            height=CGFloat(abs(sin(clock*5.2)))*65
        }
        return LooseBall(ground:ground,velocity:.zero,height:height,verticalVelocity:0)
    }
    func launchOpponentShot() {
        let body=opponentBall()
        guard let aim=ShotAssist.target(from:body.ground,facing:opponent.facing.vector) else { return }
        opponent.ownsBall=false; opponent.phase="shot"; opponent.elapsed=0.72
        opponent.pickupDelay=0.8
        shotByOpponent=true; shotBlocked=false
        // The opponent has a repeatable timing error, not a random miss. Raised
        // hands narrow its actual green window without inventing a phantom block.
        let contest=opponentShotContest(body)
        let marker=0.5+ShotGauge.width(distance:aim.distance)*0.35
        shotCanScore=ShotGauge.isGreen(marker:marker,width:ShotGauge.width(distance:aim.distance,contest:contest))
        let feet=[8,10].map { jointWorld($0,at:opponent.position,facing:opponent.facing,pose:opponent.pose,jump:0).ground }
        shotPointsByHoop=Hoop.all.indices.map { CourtGeometry.shotPoints(feet:feet,hoopIndex:$0) }
        flight=ShotFlight(startGround:body.ground,startHeight:body.height,endGround:aim.end,distance:aim.distance,points:shotPointsByHoop[aim.index],targetHeight:Hoop.height)
        rebound=nil; ball=body.screen
        message="상대 슛 · \(ShotGauge.contestLabel(contest)) · \(shotCanScore ? "정확" : "늦음") · V 점프 블로킹"
    }
    func updateOpponent(dt:Double) {
        guard defensePractice else { return }
        opponent.pickupDelay=max(0,opponent.pickupDelay-dt)
        opponent.elapsed += dt
        var walking=false
        if opponent.ownsBall {
            opponent.facing = .right
            if opponent.phase == "dribble" {
                let destination=1100+22*sin(opponent.elapsed*1.3)
                opponent.position.x += max(-CGFloat(dt)*45,min(CGFloat(dt)*45,destination-opponent.position.x))
                walking=true
                if opponent.elapsed>=2.1 {
                    opponent.phase="charge"; opponent.elapsed=0
                    message="상대가 슛을 준비합니다 · C 견제 / V 점프 블로킹"
                }
            } else if opponent.phase == "charge" && opponent.elapsed>=1.1 {
                launchOpponentShot()
            }
        } else {
            if opponent.phase == "shot" && opponent.elapsed>=1.8 { opponent.phase="waiting"; opponent.elapsed=0 }
            if !ownsBall && flight == nil && goalBall == nil && opponent.pickupDelay<=0 {
                let ground=rebound?.ground ?? CGPoint(x:ball.x,y:ball.y+Basketball.radius)
                let dx=ground.x-opponent.position.x, dy=ground.y-opponent.position.y
                let distance=CGFloat(hypot(Double(dx),Double(dy)))
                if distance>30 {
                    let step=min(distance,CGFloat(dt)*115)
                    opponent.position.x += dx/distance*step; opponent.position.y += dy/distance*step
                    opponent.facing=Facing.from(dx:dx,dy:dy); walking=true
                }
            }
        }
        opponent.position.y=max(CourtBounds.top,min(CourtBounds.bottom,opponent.position.y))
        let inset=CourtBounds.inset(at:opponent.position.y)+20
        opponent.position.x=max(inset,min(world.width-inset,opponent.position.x))
        let motion=opponent.phase == "charge" ? "charge" : opponent.phase == "shot" ? "shot" : ""
        // A longer telegraph gives the practice opponent time to teach blocking.
        let progress=motion == "charge" ? ShotGauge.poseProgress(time:opponent.elapsed*0.5) : opponent.elapsed/1.8
        opponent.pose.approach(CharacterPose.target(action:motion,progress:progress,airProgress:nil,walking:walking,clock:clock),dt:dt)
    }
    func separatePlayers() {
        guard defensePractice else { return }
        let dx=player.x-opponent.position.x, dy=(player.y-opponent.position.y)*Hoop.groundDepthScale
        let distance=CGFloat(hypot(Double(dx),Double(dy)))
        if distance<54 {
            let nx=distance>0.001 ? dx/distance : 1
            let ny=distance>0.001 ? dy/distance : 0
            player.x=opponent.position.x+nx*54
            player.y=opponent.position.y+ny*54/Hoop.groundDepthScale
            player.y=max(CourtBounds.top,min(CourtBounds.bottom,player.y))
        }
    }
    @discardableResult func trySteal(previous:LooseBall,previousHands:[DefenseHand])->Bool {
        guard defensePractice && opponent.ownsBall && !ownsBall && action == "steal" &&
              !defenseContactUsed && elapsed>=DefensePhysics.stealStart && elapsed<=DefensePhysics.stealEnd else { return false }
        let body=opponentBall()
        guard DefensePhysics.inFront(ball:body.ground,defender:player,facing:facing.vector),
              DefensePhysics.contact(from:previous,to:body,hands:defenseHands(),previousHands:previousHands,radius:DefensePhysics.stealRadius) != nil else { return false }
        opponent.ownsBall=false; opponent.phase="waiting"; opponent.elapsed=0; opponent.pickupDelay=0.8
        ownsBall=true; carriedBall=body.screen; flight=nil; rebound=nil
        shotCanScore=false; shotByOpponent=false; shotBlocked=false
        steals += 1; defenseContactUsed=true; defenseFeedback=0.5
        defenseCooldown=max(defenseCooldown,DefensePhysics.cooldown)
        action=""; elapsed=0
        message="스틸 성공! 공을 빼앗았습니다 · X 슛 / Z 덩크"
        return true
    }
    @discardableResult func tryBlock(from previous:LooseBall,to body:LooseBall,hands:[DefenseHand],previousHands:[DefenseHand])->Bool {
        guard !ownsBall && action == "block" && airborne != nil && jumpHeight()>2 &&
              !defenseContactUsed && defensePractice && shotByOpponent else { return false }
        guard DefensePhysics.inFront(ball:body.ground,defender:player,facing:facing.vector),
              DefensePhysics.contact(from:previous,to:body,hands:hands,previousHands:previousHands,radius:DefensePhysics.blockRadius) != nil else { return false }
        let deflected=DefensePhysics.deflected(body,defender:player,facing:facing.vector)
        flight=nil; rebound=deflected; ball=deflected.screen
        shotCanScore=false; shotBlocked=true; defenseContactUsed=true
        defenseCooldown=max(defenseCooldown,DefensePhysics.cooldown); defenseFeedback=0.5
        opponent.pickupDelay=max(opponent.pickupDelay,0.65)
        blocks += 1; message="블로킹 성공! 공이 튕겼습니다 · 리바운드를 잡으세요"
        return true
    }
    @discardableResult func pickup(_ body:LooseBall,rebounding:Bool)->Bool {
        guard body.height<35 else { return false }
        let playerDistance=hypot(player.x-body.ground.x,player.y-body.ground.y)
        let playerReady=(action.isEmpty || action == "handsUp") && airborne == nil && playerDistance<(rebounding ? 60 : 70)
        let opponentDistance=hypot(opponent.position.x-body.ground.x,opponent.position.y-body.ground.y)
        let opponentReady=defensePractice && !opponent.ownsBall && opponent.pickupDelay<=0 && opponentDistance<55
        if playerReady && (!opponentReady || playerDistance<=opponentDistance) {
            ownsBall=true; opponent.ownsBall=false; rebound=nil; shotCanScore=false; shotByOpponent=false
            if action == "handsUp" { action=""; elapsed=0 }
            message=rebounding ? "리바운드 획득" : "공 획득 · X 슛 / Space 점프 / Z 덩크"
            return true
        }
        if opponentReady {
            opponent.ownsBall=true; opponent.phase="dribble"; opponent.elapsed=0
            rebound=nil; shotCanScore=false; shotByOpponent=false
            ball=opponentBall().screen; message="상대 리바운드 · C 견제 / B 스틸을 시도하세요"
            return true
        }
        return false
    }
    func tick(dt: Double = 1/60) {
        let oldHands=defenseHands()
        let oldOpponentBall=opponentBall()
        clock += dt
        defenseCooldown=max(0,defenseCooldown-dt); defenseFeedback=max(0,defenseFeedback-dt)
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
        let guarding=defensePractice && ["handsUp","steal","block"].contains(action)
        if guarding {
            facing=Facing.closest(to:CGPoint(x:opponent.position.x-player.x,y:opponent.position.y-player.y),previous:facing)
        }
        if dx != 0 || dy != 0 {
            if !guarding { facing = Facing.from(dx:dx,dy:dy) }
            let length=sqrt(dx*dx+dy*dy)
            player.x += dx/length*movementSpeed*CGFloat(dt*60); player.y += dy/length*movementSpeed*CGFloat(dt*60)
        }
        player.y=max(CourtBounds.top,min(CourtBounds.bottom,player.y))
        updateOpponent(dt:dt); separatePlayers()
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
            if action == "handsUp" {
                if keys.contains(8) && !ownsBall { elapsed=0.5 }
                else { action=""; elapsed=0 }
            }
            if !charging && elapsed >= duration(action) { action=""; elapsed=0 }
        }
        if action.isEmpty && airborne == nil && !ownsBall && keys.contains(8) { startDefense() }
        let progress=charging ? ShotGauge.poseProgress(time:chargeTime) : elapsed/duration(action)
        let target=CharacterPose.target(action:action,progress:progress,airProgress:airborne.map { $0/airDuration },walking:dx != 0 || dy != 0,clock:clock)
        pose.approach(target,dt:dt)
        defenseReach += ((action == "steal" ? 1 : 0)-defenseReach)*CGFloat(1-exp(-dt/0.055))
        let newHands=defenseHands()
        if defensePractice && opponent.ownsBall {
            ball=opponentBall().screen
            trySteal(previous:oldOpponentBall,previousHands:oldHands)
        } else if var goal=goalBall {
            goal.time += dt
            ball=CGPoint(x:goal.body.screen.x,y:goal.body.screen.y+CGFloat(goal.time)*85)
            if goal.time>=0.30 { goalBall=nil; ball=CGPoint(x:836,y:570); message="\(shotByOpponent ? "상대 골" : "골")! 공이 가운데로 돌아왔습니다" }
            else { goalBall=goal }
        } else if var f=flight {
            let oldTime=f.time; f.time += dt
            var previous=f.sample(at:oldTime)
            var interrupted=false
            let steps=max(1,Int(ceil(dt*480)))
            for index in 1...steps {
                var body=f.sample(at:min(f.duration,oldTime+dt*Double(index)/Double(steps)))
                func hands(at fraction:CGFloat)->[DefenseHand] {
                    zip(oldHands,newHands).map { old,new in DefenseHand(ground:CGPoint(x:old.ground.x+(new.ground.x-old.ground.x)*fraction,y:old.ground.y+(new.ground.y-old.ground.y)*fraction),height:old.height+(new.height-old.height)*fraction) }
                }
                if action == "block" && defensePractice && shotByOpponent && tryBlock(from:previous,to:body,hands:hands(at:CGFloat(index)/CGFloat(steps)),previousHands:hands(at:CGFloat(index-1)/CGFloat(steps))) {
                    interrupted=true; break
                }
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
            let previous=r
            r.step(dt:dt); ball=r.screen
            if tryBlock(from:previous,to:r,hands:newHands,previousHands:oldHands) { }
            else if let hoop=r.scoredHoop { awardGoal(hoop,body:r) }
            else if !pickup(r,rebounding:true) { rebound=r }
        } else if !ownsBall {
            pickup(LooseBall(ground:CGPoint(x:ball.x,y:ball.y+Basketball.radius),velocity:.zero,height:0,verticalVelocity:0),rebounding:false)
        }
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
    func drawCharacter(at position:CGPoint,facing direction:Facing,pose body:CharacterPose,jump:CGFloat,color:NSColor,defending:CGFloat = 0,label:String? = nil) {
        let shadowScale=max(0.7,1-jump/180)
        NSColor.black.withAlphaComponent(max(0.08,0.2-Double(jump)/400)).setFill()
        NSBezierPath(ovalIn:NSRect(x:position.x-27*shadowScale,y:position.y-8*shadowScale,width:54*shadowScale,height:16*shadowScale)).fill()
        if let label {
            color.setStroke()
            let ring=NSBezierPath(ovalIn:NSRect(x:position.x-30,y:position.y-10,width:60,height:20)); ring.lineWidth=2; ring.stroke()
            let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:16,weight:.bold),.foregroundColor:NSColor.white]
            let size=label.size(withAttributes:attrs)
            NSColor.black.withAlphaComponent(0.6).setFill();NSBezierPath(roundedRect:NSRect(x:position.x-size.width/2-5,y:position.y+12,width:size.width+10,height:size.height+5),xRadius:4,yRadius:4).fill()
            label.draw(at:CGPoint(x:position.x-size.width/2,y:position.y+15),withAttributes:attrs)
        }
        color.setStroke()
        for chain in [[0,2],[1,3,4],[1,5,6],[2,7,8],[2,9,10]] {
            let path=NSBezierPath(); path.lineWidth=3.6; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.move(to:jointWorld(chain[0],at:position,facing:direction,pose:body,jump:jump,defending:defending).screen)
            for index in chain.dropFirst() { path.line(to:jointWorld(index,at:position,facing:direction,pose:body,jump:jump,defending:defending).screen) }; path.stroke()
        }
        heads[direction.head]?.draw(in:NSRect(x:position.x-37.5,y:position.y+(body.headY-691)*0.3-jump,width:75,height:84),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
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
        func drawPlayer() {
            drawCharacter(at:player,facing:facing,pose:pose,jump:jumpHeight(),color:.black,defending:defenseReach,label:defensePractice ? "플레이어" : nil)
        }
        if defensePractice {
            if player.y<opponent.position.y { drawPlayer() }
            drawCharacter(at:opponent.position,facing:opponent.facing,pose:opponent.pose,jump:0,color:NSColor(calibratedRed:0.8,green:0.15,blue:0.18,alpha:1),label:"연습 상대")
            if player.y>=opponent.position.y { drawPlayer() }
            if opponent.ownsBall && opponent.phase == "charge" {
                "슛 준비".draw(at:CGPoint(x:opponent.position.x-35,y:opponent.position.y-228),withAttributes:[.font:NSFont.systemFont(ofSize:19,weight:.bold),.foregroundColor:NSColor.systemRed])
            }
        } else { drawPlayer() }
        if defenseFeedback>0 {
            let ring=NSBezierPath(ovalIn:NSRect(x:player.x-42,y:player.y-14,width:84,height:28))
            NSColor.systemGreen.setStroke(); ring.lineWidth=4; ring.stroke()
        }
        if !ownsBall {
            let ground:CGPoint
            if defensePractice && opponent.ownsBall { ground=opponentBall().ground }
            else if let r=rebound { ground=r.ground }
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
            let timing=charging ? "X를 놓으세요" : ShotGauge.timingLabel(marker:gaugeMarker,width:gaugeWidth)
            "\(ShotGauge.contestLabel(gaugeContest)) · \(timing)".draw(at:CGPoint(x:rect.minX,y:rect.minY+24),withAttributes:[.font:NSFont.systemFont(ofSize:17,weight:.semibold),.foregroundColor:NSColor.white])
        }
        NSColor(calibratedWhite:0.10,alpha:1).setFill(); NSRect(x:0,y:941,width:1672,height:99).fill()
        let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:22,weight:.medium),.foregroundColor:NSColor.white]
        "방향키 이동   Shift 달리기   Space 점프   X 슛   Z 덩크   C 견제   B 스틸   V 블록   Tab 모드   R 초기화".draw(at:NSPoint(x:35,y:958),withAttributes:attrs)
        let status=defensePractice ? "수비 연습 · 나 \(score) : 상대 \(opponentScore) · 스틸 \(steals) / 블록 \(blocks)" : "슛 연습 · \(score)점"
        "\(status) · \(message) · \(updateStatus)".draw(at:NSPoint(x:35,y:997),withAttributes:[.font:NSFont.systemFont(ofSize:17),.foregroundColor:NSColor.lightGray])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu=NSMenu(); let item=NSMenuItem(); let appMenu=NSMenu()
        appMenu.addItem(withTitle:"Full Court Stickman 종료",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        item.submenu=appMenu; menu.addItem(item); NSApp.mainMenu=menu
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1200,height:747),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Full Court Stickman — LAN Beta"
        window.minSize=NSSize(width:840,height:550)
        let view=GameRootView(frame:window.contentView!.bounds)
        view.autoresizingMask=[.width,.height]; window.contentView=view
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps:true)
        AutoUpdater.check { [weak view] status in view?.updateStatus=status;if view?.screen == .home && view?.practice == nil { view?.showHome() } }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

func runDefenseGameplayTests(_ view:CourtView) {
    view.keys.removeAll(); view.running=false; view.defensePractice=true; view.reset()
    for _ in 0..<540 { view.tick() }
    precondition(view.opponentScore>0 && view.score==0,"Practice opponent must dribble, shoot and own its score")
    for direction in Facing.allCases {
        view.reset(); view.clock=0.12; view.opponent.position=CGPoint(x:1000,y:600)
        let body=view.opponentBall()
        view.player=CGPoint(x:body.ground.x-direction.vector.x*72,y:body.ground.y-direction.vector.y*72/Hoop.groundDepthScale)
        view.facing=direction; view.begin("steal"); view.elapsed=0.2
        view.pose=CharacterPose.target(action:"steal",progress:0.5,airProgress:nil,walking:false,clock:view.clock)
        view.defenseReach=1
        let hands=view.defenseHands()
        precondition(view.trySteal(previous:body,previousHands:hands),"Eight-direction hand contact failed: \(direction)")
        precondition(view.ownsBall && !view.opponent.ownsBall && view.steals==1 && view.flight==nil,"Steal must transfer a single ball")
        precondition(!view.trySteal(previous:body,previousHands:hands) && view.steals==1,"One reach cannot steal twice")
    }
    view.reset(); view.clock=0.12; view.player=CGPoint(x:1350,y:530); view.facing = .left
    view.begin("steal"); view.elapsed=0.2
    view.pose=CharacterPose.target(action:"steal",progress:0.5,airProgress:nil,walking:false,clock:view.clock)
    view.defenseReach=1
    precondition(!view.trySteal(previous:view.opponentBall(),previousHands:view.defenseHands()),"Distant B must not steal")
    view.defensePractice=false; view.reset(); view.startDefense()
    precondition(view.action=="handsUp" && view.defenseCooldown==0,"C must activate a hands-up stance, not a steal")
    view.startSteal()
    precondition(view.action=="steal" && view.defenseCooldown>0,"B must perform a discrete steal")
    view.action=""; view.startSteal()
    precondition(view.action.isEmpty,"Repeated steal input bypassed cooldown")
    view.defenseCooldown=0; view.ownsBall=true; view.startDefense(); view.startSteal()
    precondition(view.action.isEmpty && view.ownsBall,"Cannot defend one's own held ball")
    view.ownsBall=false; view.begin("handsUp"); view.player=CGPoint(x:550,y:600)
    view.running=true; view.keys=[124,8]; view.tick()
    precondition(abs(view.player.x-555.04)<0.001,"Defensive stance must allow ninety percent Shift speed")
    view.keys.removeAll(); view.running=false
    view.keys=[8]; view.startJump()
    precondition(view.action=="handsUp" && view.airborne==0,"C plus Space must preserve hands-up pressure without automatically blocking")
    view.airborne=0.3;view.startBlock()
    precondition(view.action=="block" && view.airborne==0.3,"V must not restart an existing jump")
    view.action="jump";view.airborne=0.3;view.startDefense()
    precondition(view.action=="handsUp" && view.airborne==0.3,"Space then C must also raise hands without restarting or blocking")
    view.keys.removeAll()
    // Raised hands change the shooter's real timing window without recording
    // a block, while a trailing defender must not get front-facing coverage.
    for front in [true,false] {
        view.defensePractice=true; view.keys.removeAll(); view.reset()
        view.opponent.phase="charge"; view.opponent.elapsed=1.1
        view.opponent.pose=CharacterPose.target(action:"charge",progress:ShotGauge.poseProgress(time:0.55),airProgress:nil,walking:false,clock:0)
        view.player=CGPoint(x:view.opponent.position.x+(front ? 90 : -90),y:view.opponent.position.y)
        view.facing=front ? .left : .right; view.keys=[8]; view.startDefense()
        view.pose=CharacterPose.target(action:"handsUp",progress:0.5,airProgress:nil,walking:false,clock:0)
        let pressure=view.opponentShotContest(view.opponentBall())
        view.launchOpponentShot()
        precondition(front ? pressure>=0.65 && !view.shotCanScore : view.shotCanScore,"Hands-up coverage must affect the timing window, not pretend to block")
        precondition(view.blocks==0 && view.flight != nil,"A contest alone must not deflect the ball")
    }
    view.keys.removeAll()
    for dt in [1.0/60,1.0/120,0.05] {
        for enemyShot in [true,false] {
            view.defensePractice=true; view.reset()
            view.opponent.ownsBall=false; view.opponent.phase="waiting"; view.opponent.pickupDelay=10
            view.player=CGPoint(x:1000,y:530); view.facing = .right
            view.airborne=0.45; view.begin("block"); view.elapsed=0.30
            view.pose=CharacterPose.target(action:"block",progress:0.4,airProgress:0.5,walking:false,clock:view.clock)
            let hand=view.defenseHands()[1]
            view.flight=ShotFlight(startGround:CGPoint(x:hand.ground.x+8,y:hand.ground.y),startHeight:hand.height,endGround:CGPoint(x:hand.ground.x-180,y:hand.ground.y),distance:188,points:2,targetHeight:hand.height)
            view.shotByOpponent=enemyShot; view.shotCanScore=true
            view.tick(dt:dt)
            if enemyShot {
                precondition(view.blocks==1 && view.flight==nil && view.rebound != nil,"Airborne hand contact must interrupt flight at \(dt)")
                precondition(!view.shotCanScore && view.rebound!.verticalVelocity<0,"Block must knock down the ball and cancel scoring eligibility")
                for _ in 0..<Int(2/dt) { view.tick(dt:dt) }
                precondition(view.blocks==1 && view.score==0 && view.opponentScore==0 && view.ball.x != 836,"Blocked ball must rebound, not score/reset/re-block")
            } else { precondition(view.blocks==0 && view.flight != nil,"Player cannot block their own shot") }
        }
        view.reset(); view.keys=[8]; view.startDefense()
        for _ in 0..<Int(1/dt) { view.tick(dt:dt) }
        precondition(view.steals==0 && !view.ownsBall && view.opponent.ownsBall && view.action=="handsUp","Held C must never automatically steal at \(dt)")
        view.keys.removeAll(); view.reset(); view.keys=[11]; view.startSteal()
        for _ in 0..<Int(1/dt) { view.tick(dt:dt) }
        precondition(view.steals==1 && view.ownsBall && !view.opponent.ownsBall,"Discrete B dribble steal failed at \(dt)")
        view.keys.removeAll()
        var naturalBlock=false
        for timing in [0.65,0.75,0.85,0.95] {
            view.clock=0; view.reset()
            while view.opponent.phase != "charge" || view.opponent.elapsed<timing { view.tick(dt:dt) }
            view.keys=[9]; view.startBlock()
            for _ in 0..<Int(1.5/dt) { view.tick(dt:dt) }
            view.keys.removeAll()
            if view.blocks>0 { naturalBlock=true; break }
        }
        precondition(naturalBlock,"Normal opponent shot must be blockable with V at \(dt)")
    }
    view.defensePractice=false; view.keys.removeAll(); view.reset()
}
@main
enum Main {
    static func main() {
        let app=NSApplication.shared
        if CommandLine.arguments.contains("--lan-self-test") { runLANTransportTests();return }
        if let flag=CommandLine.arguments.firstIndex(of:"--render-lan-preview"),flag+1<CommandLine.arguments.count {
            let network=NetworkSession();network.role = .host;network.game.phase = .playing;network.game.arrange(0)
            network.game.players[0].position=CGPoint(x:1250,y:530);network.game.players[0].action = .charge;network.game.players[0].elapsed=0.55;network.game.players[0].chargeTime=0.55
            network.game.players[1].position=CGPoint(x:1390,y:530);network.game.players[1].action = .block;network.game.players[1].air=0.45;network.game.players[1].elapsed=0.30
            network.names=["방장","참가자"];network.game.remaining=153;network.rttMS=12
            for i in 0..<2 {
                let p=network.game.players[i]
                let progress=p.action == .charge ? ShotGauge.poseProgress(time:p.chargeTime) : p.elapsed/p.actionDuration
                network.game.players[i].pose=CharacterPose.target(action:p.poseAction,progress:progress,airProgress:p.air.map{$0/p.airDuration},walking:false,clock:0)
            }
            network.game.body=ActionSystem.held(network.game.players[0])
            let context=network.game.shotContext(0)
            network.game.players[0].shotWidth=context.width;network.game.players[0].contest=context.contest
            let small=CommandLine.arguments.contains("--small"),size=NSSize(width:small ? 840 : 1200,height:small ? 550 : 747)
            let view=LANMatchView(frame:NSRect(origin:.zero,size:size),network:network);view.timer?.invalidate();view.shown=network.game.snapshot();view.poses=network.game.players.map(\.pose)
            for _ in 0..<120 { view.camera.update(snapshot:view.shown!,local:0,size:CGSize(width:size.width,height:size.height-104),dt:1.0/60) }
            let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[flag+1]));network.stop();return
        }
        if let flag=CommandLine.arguments.firstIndex(where:{ ["--render-preview","--render-defense-preview"].contains($0) }),flag+1<CommandLine.arguments.count {
            let view=CourtView(frame:NSRect(x:0,y:0,width:1672,height:1040)); view.timer?.invalidate()
            view.player=CGPoint(x:980,y:530); view.facing = .right; view.ownsBall=true
            view.startCharge(); view.chargeTime=0.55; view.elapsed=0.55
            view.pose=CharacterPose.target(action:"charge",progress:ShotGauge.poseProgress(time:0.55),airProgress:nil,walking:false,clock:0)
            view.carriedBall=view.heldPosition(); view.updateGauge()
            if CommandLine.arguments[flag] == "--render-defense-preview" {
                view.defensePractice=true
                for timing in [0.65,0.75,0.85,0.95] {
                    view.clock=0; view.keys.removeAll(); view.reset()
                    while view.opponent.phase != "charge" || view.opponent.elapsed<timing { view.tick() }
                    view.keys=[9]; view.startBlock()
                    for _ in 0..<90 { view.tick(); if view.blocks>0 { break } }
                    if view.blocks>0 { break }
                }
                precondition(view.blocks>0,"Defense preview must show a real blocked shot")
            }
            view.updateStatus="v\(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "")"
            let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[flag+1]))
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            let view=CourtView(frame:NSRect(x:0,y:0,width:1200,height:747))
            view.timer?.invalidate()
            runShotPhysicsTests(); runCourtGeometryTests(); runDefensePhysicsTests();runMatchTests();runLANViewTests()
            precondition(abs(ShotGauge.width(distance:200)-0.32)<0.0001)
            precondition(abs(ShotGauge.width(distance:450)-0.16)<0.0001)
            precondition(abs(ShotGauge.width(distance:650)-0.06)<0.0001)
            for width in [0.32,0.16,0.06,0.03,0.015,0.008] {
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
            view.reset(); view.ownsBall=true; view.startCharge(); view.tick(dt:2.2); view.releaseCharge()
            precondition(view.gaugeMarker==1 && !view.accurateShot && !view.shotCanScore,"Overheld one-way meter must never return to green")
            view.reset(); view.ownsBall=true; view.keys=[124]; view.startCharge(); view.tick()
            let movingDistance=view.aimedHoop()?.distance ?? Hoop.all.map { hypot(view.player.x-$0.center.x,view.player.y-$0.center.y) }.min()!
            precondition(view.gaugeWidth<ShotGauge.width(distance:movingDistance),"Moving gather must narrow the green window")
            view.keys.removeAll()
            view.reset(); view.ownsBall=true; view.startCharge(); view.cancelCharge()
            precondition(!view.charging && view.ownsBall && view.flight == nil,"Focus loss must cancel, not shoot")
            view.reset()
            for distance in stride(from:201,through:1600,by:1) {
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
                        let aimedDistance=view.aimedHoop()?.distance ?? distance
                        precondition(abs(view.gaugeWidth-ShotGauge.width(distance:aimedDistance))<0.0001,"Wrong basket used for long-range gauge")
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
                        let limit=CGFloat(acos(ShotAssist.alignment(distance:distance)))
                        let a=angle/20*limit*0.8
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
            view.begin("handsUp"); view.keys.insert(8); view.elapsed=0.7; view.tick()
            precondition(view.action=="handsUp" && view.elapsed==0.5,"Hands-up hold failed")
            view.keys.removeAll(); view.tick()
            precondition(view.action.isEmpty,"Releasing C must release the hands-up stance")
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
            runDefenseGameplayTests(view)
            print("PASS: defense contacts/steals/blocks/opponent/cooldown; strict green timing, dunks, physics scoring, 2/3 points, aim assist, rebounds and motion")
            return
        }
        app.setActivationPolicy(.regular)
        let delegate=AppDelegate(); app.delegate=delegate; app.run()
    }
}
