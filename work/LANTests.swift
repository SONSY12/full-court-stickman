import Foundation
import AppKit

func runShotDefenseRuleTests() {
    precondition(ShotGauge.marker(time:-0.2)==0 && ShotGauge.marker(time:0)==0,"Shot meter cannot start behind zero")
    precondition(abs(ShotGauge.marker(time:0.55)-0.5)<0.000001,"Shot gather and center release must remain synchronized")
    precondition(ShotGauge.marker(time:1.1)==1 && ShotGauge.marker(time:2.75)==1,"Overholding must never bring the meter back into green")
    var previous=0.0
    for tick in 0...600 {
        let marker=ShotGauge.marker(time:Double(tick)/60)
        precondition(marker>=previous && (0...1).contains(marker),"Shot meter must move only once, forward")
        previous=marker
    }
    let atRelease=CharacterPose.target(action:"charge",progress:ShotGauge.poseProgress(time:0.55),airProgress:nil,walking:false,clock:0)
    let gathered=CharacterPose.target(action:"charge",progress:1,airProgress:nil,walking:false,clock:0)
    precondition(atRelease.joints[6]==gathered.joints[6],"Center timing must match the gathered shooting hand, not an unfinished lift")
    for distance:CGFloat in [150,400,650,750,1000,1300] {
        let open=ShotGauge.width(distance:distance,moving:false,contest:0)
        let moving=ShotGauge.width(distance:distance,moving:true,contest:0)
        let guarded=ShotGauge.width(distance:distance,moving:false,contest:1)
        let both=ShotGauge.width(distance:distance,moving:true,contest:1)
        precondition(open>=moving && open>=guarded && both<=moving && both<=guarded,"Movement and real contest must never enlarge the green window")
        precondition(both>=0.015 && open<=0.32,"Timing window must retain its playable minimum and maximum")
        if distance<650 { precondition(open>moving && open>guarded,"Near/midrange movement and contest must actually reduce difficulty tolerance") }
        for width in [open,moving,guarded,both] {
            precondition(ShotGauge.isGreen(marker:0.5-width/2,width:width) && ShotGauge.isGreen(marker:0.5+width/2,width:width),"Displayed exact green edges must count")
            precondition(!ShotGauge.isGreen(marker:0.5-width/2-0.000001,width:width) && !ShotGauge.isGreen(marker:0.5+width/2+0.000001,width:width),"Contextual outside-green shots must always fail")
        }
    }
    precondition(abs(ShotGauge.width(distance:150,moving:true,contest:0)-0.24)<0.000001,"Moving release window balance")
    precondition(abs(ShotGauge.width(distance:150,moving:false,contest:1)-0.112)<0.000001,"Strong contest window balance")
    precondition(ShotGauge.timingLabel(marker:0,width:0.1)=="빠름" && ShotGauge.timingLabel(marker:0.5,width:0.1)=="정확" && ShotGauge.timingLabel(marker:1,width:0.1)=="늦음","Release feedback must distinguish early, green and late")

    let source=DefenseHand(ground:CGPoint(x:1000,y:530),height:190)
    let defender=CGPoint(x:1070,y:530),toward=CGPoint(x:-1,y:0)
    let raised=DefenseHand(ground:CGPoint(x:1040,y:530),height:185)
    precondition(DefensePhysics.contest(shooter:source,defender:defender,facing:toward,hands:[raised])>0,"Raised hand near release should contest without requiring a block")
    precondition(DefensePhysics.contest(shooter:source,defender:defender,facing:CGPoint(x:1,y:0),hands:[raised])==0,"A defender facing away cannot contest from behind")
    let otherDepth=DefenseHand(ground:CGPoint(x:1040,y:1530),height:185)
    let lowHand=DefenseHand(ground:raised.ground,height:source.height-300)
    precondition(DefensePhysics.contest(shooter:source,defender:defender,facing:toward,hands:[otherDepth])==0,"Different court depth cannot create a screen-overlap contest")
    precondition(DefensePhysics.contest(shooter:source,defender:defender,facing:toward,hands:[lowHand])==0,"A low stealing hand cannot contest a high release")

    func guardedShot(_ attacker:Int)->GameSession {
        let game=GameSession(),defender=1-attacker,sign:CGFloat=attacker==0 ? 1 : -1
        game.phase = .playing
        game.players[attacker].position=CGPoint(x:1000,y:600);game.players[attacker].facing=sign>0 ? .right : .left
        game.grant(attacker);game.players[attacker].action = .charge;game.players[attacker].chargeTime=0.55
        game.players[attacker].pose=CharacterPose.target(action:"charge",progress:1,airProgress:nil,walking:false,clock:0)
        game.players[attacker].moving=true
        game.players[attacker].input=InputFrame(matchID:game.matchID,seq:1,tick:0,x:Int(sign),y:0,buttons:InputFrame.shoot,actions:[])
        game.players[defender].position=CGPoint(x:1000+sign*54,y:600);game.players[defender].facing=sign>0 ? .left : .right
        game.players[defender].action = .defense
        game.players[defender].pose=CharacterPose.target(action:"handsUp",progress:0.5,airProgress:nil,walking:false,clock:0)
        game.players[defender].input=InputFrame(matchID:game.matchID,seq:1,tick:0,x:0,y:0,buttons:InputFrame.defend,actions:[])
        game.body=ActionSystem.held(game.players[attacker])
        return game
    }
    for attacker in 0..<2 {
        let fixture=guardedShot(attacker),defender=1-attacker
        let hand=ActionSystem.joint(6,player:fixture.players[attacker]),guarder=fixture.players[defender]
        precondition(DefensePhysics.contest(shooter:hand,defender:guarder.position,facing:guarder.facing.vector,hands:ActionSystem.hands(guarder))>0,"Both scorers must receive a real, height-aware hands-up contest")
        let distance=fixture.aimed(attacker)!.distance
        fixture.launch(attacker,marker:0.5,dunk:false)
        let width=fixture.players[attacker].shotWidth
        precondition(fixture.players[attacker].contest>0 && width<ShotGauge.width(distance:distance),"Authority must apply movement and actual opponent hands to the green window")
        precondition(fixture.canScore && fixture.players[attacker].score==0,"Contested green may score only after the actual hoop crossing")
        let outside=guardedShot(attacker)
        outside.launch(attacker,marker:0.5+width/2+0.000001,dunk:false)
        precondition(!outside.canScore && outside.players[attacker].score==0,"A shot inside the old open window but outside the new guarded window must miss")
    }
    let overheld=GameSession();overheld.phase = .playing
    overheld.players[0].position=CGPoint(x:1300,y:530);overheld.players[0].facing = .right;overheld.grant(0)
    overheld.players[0].action = .charge;overheld.players[0].chargeTime=2.75
    overheld.players[0].pose=CharacterPose.target(action:"charge",progress:1,airProgress:nil,walking:false,clock:0)
    overheld.body=ActionSystem.held(overheld.players[0])
    overheld.execute(ActionCommand(id:1,tick:overheld.tick,action:.release),player:0)
    precondition(overheld.flight != nil && !overheld.canScore && overheld.event.kind.contains("늦음"),"Authority must launch an overheld shot as a late miss, never a second-cycle green")

    // chargeTime in a completed snapshot belongs to that snapshot's tick,
    // while queued input executes before the next chargeTime increment.
    func releaseTimingGame(tick:Int=100,time:Double=0.55)->GameSession {
        let game=GameSession();game.phase = .playing;game.tick=tick
        game.players[0].position=CGPoint(x:Hoop.all[1].center.x-1100,y:530);game.players[0].facing = .right
        game.players[1].position=CGPoint(x:836,y:750);game.grant(0)
        game.players[0].action = .charge;game.players[0].chargeTime=time;game.players[0].inputAt=tick
        game.players[0].pose=CharacterPose.target(action:"charge",progress:ShotGauge.poseProgress(time:time),airProgress:nil,walking:false,clock:0)
        game.body=ActionSystem.held(game.players[0]);game.players[0].shotWidth=game.shotContext(0).width
        precondition(game.players[0].shotWidth==0.015,"Release timing regression needs the narrowest real long-range window")
        return game
    }
    for (deliveryTick,shownTime,intendedTick) in [(100,0.55,100),(100,0.55-1.0/60,101),(103,0.55+3.0/60,100)] {
        let game=releaseTimingGame(tick:deliveryTick,time:shownTime)
        let release=ActionCommand(id:1,tick:intendedTick,action:.release)
        game.ingest(InputFrame(matchID:game.matchID,seq:1,tick:deliveryTick+2,x:0,y:0,buttons:0,actions:[release]),player:0)
        game.step()
        precondition(game.flight != nil && game.canScore && game.event.kind.contains("정확"),"Shown center must remain green for immediate, predicted-future and three-tick-late queued releases")
    }
    let late=releaseTimingGame(time:0.55+(0.015/2+0.000001)*ShotGauge.duration)
    late.ingest(InputFrame(matchID:late.matchID,seq:1,tick:late.tick+2,x:0,y:0,buttons:0,actions:[ActionCommand(id:1,tick:late.tick,action:.release)]),player:0)
    late.step();precondition(!late.canScore,"Aligning network release time cannot create an outside-green tolerance")
    let timingNetwork=NetworkSession();timingNetwork.role = .host;timingNetwork.udpReady=true;timingNetwork.game=releaseTimingGame()
    timingNetwork.input.key(7,down:true,tick:67);timingNetwork.input.acknowledge(seq:0,action:1);timingNetwork.game.players[0].ackAction=1
    let timingView=LANMatchView(frame:NSRect(x:0,y:0,width:840,height:550),network:timingNetwork);timingView.timer?.invalidate()
    let keyUp=NSEvent.keyEvent(with:.keyUp,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"x",charactersIgnoringModifiers:"x",isARepeat:false,keyCode:7)!
    let displayedTick=timingNetwork.estimatedTick
    timingView.keyUp(with:keyUp)
    precondition(timingNetwork.input.pending.last?.tick==displayedTick,"Physical release must carry the displayed meter tick, not a future movement tick")
    timingNetwork.game.step()
    precondition(timingNetwork.game.canScore && timingNetwork.game.flight != nil,"Host physical key-up at displayed long-range center must be a green release")
    timingNetwork.stop()

    func contextualReleaseGame(marker:Double)->GameSession {
        let game=releaseTimingGame(tick:103,time:marker*ShotGauge.duration+3.0/60)
        game.players[0].position=CGPoint(x:Hoop.all[1].center.x-150,y:530)
        game.body=ActionSystem.held(game.players[0]);game.players[0].shotWidth=game.shotContext(0).width
        return game
    }
    let oldNarrow=ShotGauge.width(distance:150,moving:true,contest:1)
    let outsideOldMarker=0.5+oldNarrow/2+0.000001
    let widened=contextualReleaseGame(marker:outsideOldMarker)
    widened.players[0].shotSamples=[(tick:100,width:oldNarrow,contest:1)]
    precondition(ShotGauge.isGreen(marker:outsideOldMarker,width:widened.shotContext(0).width),"Historical-window sample must actually be inside the newly widened open window")
    widened.ingest(InputFrame(matchID:widened.matchID,seq:1,tick:105,x:0,y:0,buttons:0,actions:[ActionCommand(id:1,tick:100,action:.release)]),player:0)
    widened.step()
    precondition(!widened.canScore && widened.players[0].shotWidth==oldNarrow && widened.players[0].contest==1,"Delayed release outside the displayed guarded window must not become green just because movement or defense stopped")
    let oldOpen=ShotGauge.width(distance:150),insideOldMarker=0.5+ShotGauge.width(distance:150)*0.35
    let tightened=contextualReleaseGame(marker:insideOldMarker)
    tightened.players[0].moving=true
    tightened.players[1].position=CGPoint(x:tightened.players[0].position.x+54,y:530);tightened.players[1].facing = .left;tightened.players[1].action = .defense
    tightened.players[1].pose=CharacterPose.target(action:"handsUp",progress:0.5,airProgress:nil,walking:false,clock:0)
    tightened.players[1].input=InputFrame(matchID:tightened.matchID,seq:1,tick:103,x:0,y:0,buttons:InputFrame.defend,actions:[]);tightened.players[1].inputAt=103
    tightened.players[0].shotSamples=[(tick:100,width:oldOpen,contest:0)]
    precondition(!ShotGauge.isGreen(marker:insideOldMarker,width:tightened.shotContext(0).width),"Historical-window sample must actually be outside the newly tightened guarded window")
    tightened.ingest(InputFrame(matchID:tightened.matchID,seq:1,tick:105,x:0,y:0,buttons:0,actions:[ActionCommand(id:1,tick:100,action:.release)]),player:0)
    tightened.step()
    precondition(tightened.canScore && tightened.players[0].shotWidth==oldOpen && tightened.players[0].contest==0,"A valid displayed open green must retain its release-time window when new hands-up pressure arrives before delivery")

    var sample=PlayerState(id:0,position:CGPoint(x:1000,y:530),facing:.right)
    sample.shotWidth=0.07456789123456789;sample.contest=0.623456789
    let packet=PlayerPacket(sample),data=try! JSONEncoder().encode(packet)
    let decoded=try! JSONDecoder().decode(PlayerPacket.self,from:data)
    precondition(decoded.shotWidth==sample.shotWidth && decoded.state.shotWidth==sample.shotWidth,"Network green edges cannot gain a rounding tolerance")
    precondition(decoded.contest>=0 && decoded.contest<=1,"Contest feedback must stay normalized after packet decoding")
    let valid=GameSession().snapshot();var invalid=valid
    invalid.players[0].shotWidth = .nan;precondition(!invalid.valid,"Nonfinite authoritative green width must be rejected")
    invalid=valid;invalid.players[0].contest=1.1;precondition(!invalid.valid,"Out-of-range authoritative contest must be rejected")

    let stance=GameSession();stance.phase = .playing
    stance.players[0].position=CGPoint(x:1000,y:600);stance.players[0].facing = .left;stance.grant(0)
    stance.players[0].dribble=0.12;stance.body=ActionSystem.held(stance.players[0])
    stance.players[1].position=CGPoint(x:stance.body.ground.x-72,y:600);stance.players[1].facing = .right
    stance.execute(ActionCommand(id:1,tick:0,action:.defend),player:1)
    precondition(stance.players[1].action == .defense && stance.players[1].cooldown==0,"C must raise hands without spending a steal attempt")
    for seq in 1...120 {
        stance.ingest(InputFrame(matchID:stance.matchID,seq:seq,tick:stance.tick,x:0,y:0,buttons:InputFrame.defend,actions:[]),player:1)
        stance.step()
    }
    precondition(stance.owner==0 && stance.players[1].steals==0 && stance.players[1].blocks==0 && stance.players[1].action == .defense,"Holding C cannot automatically steal or jump-block")

    let steal=GameSession();steal.phase = .playing;steal.grant(0)
    steal.execute(ActionCommand(id:1,tick:0,action:.steal),player:1)
    precondition(steal.players[1].action == .steal && abs(steal.players[1].cooldown-DefensePhysics.cooldown)<0.000001,"B must start one contact-based steal and recovery")
    for _ in 0..<13 { steal.step() }
    let elapsed=steal.players[1].elapsed,cooldown=steal.players[1].cooldown
    steal.execute(ActionCommand(id:2,tick:steal.tick,action:.steal),player:1)
    precondition(steal.players[1].elapsed==elapsed && steal.players[1].cooldown==cooldown,"Repeated B cannot restart an active steal or bypass recovery")
    for _ in 0..<16 { steal.step() }
    precondition(steal.players[1].action == .idle && steal.players[1].cooldown>0,"Missed steal must leave its short action before the cooldown ends")
    steal.execute(ActionCommand(id:3,tick:steal.tick,action:.steal),player:1)
    precondition(steal.players[1].action == .idle,"B cannot retry during the remaining recovery")
    for _ in 0..<15 { steal.step() }
    steal.execute(ActionCommand(id:4,tick:steal.tick,action:.steal),player:1)
    precondition(steal.players[1].action == .steal,"B must work again once recovery finishes")
    steal.players[0].action = .idle;steal.execute(ActionCommand(id:5,tick:steal.tick,action:.steal),player:0)
    precondition(steal.players[0].action == .idle,"Ball owner cannot steal")
    steal.players[1].action = .idle;steal.players[1].cooldown=0;steal.players[1].air=0.3
    steal.execute(ActionCommand(id:6,tick:steal.tick,action:.steal),player:1)
    precondition(steal.players[1].action == .idle && steal.players[1].air==0.3,"B cannot interrupt an airborne player with a ground steal")
    let keyboard=InputController();keyboard.key(11,down:true,tick:0)
    for tick in 1...10 { keyboard.key(11,down:true,tick:tick) }
    precondition(keyboard.pending.map(\.action)==[.steal],"Holding or keyboard-repeat B cannot emit repeated steals")
    keyboard.key(11,down:false,tick:11);keyboard.key(11,down:true,tick:12)
    precondition(keyboard.pending.map(\.action)==[.steal,.steal],"A new B press must remain a separate reliable action")
    print("PASS: one-way gather meter, movement/height-aware hands-up contest, strict contextual green edges, authoritative width precision, C stance and B single-attempt cooldown")
}

func runMatchTests() {
    runShotDefenseRuleTests()
    precondition(abs(JumpMotion.height(progress:0.5)-58.5)<0.001,"Jump peak must be 30 percent higher")
    precondition(JumpMotion.height(progress:0)==0 && JumpMotion.height(progress:1)==0,"Jump must end on the floor")
    for (distance,width) in [(750.0,0.03),(1000.0,0.015),(1300.0,0.015)] {
        precondition(abs(ShotGauge.width(distance:CGFloat(distance))-width)<0.00001,"Long-range gauge balance")
        precondition(!ShotGauge.isGreen(marker:0.5+width/2+0.000001,width:width),"Long-range outside green must still miss")
    }
    let balanceHand=DefenseHand(ground:CGPoint(x:1000,y:530),height:200)
    var jumper=PlayerState(id:0,position:.zero,facing:.right);jumper.air=0.45
    precondition(jumper.airDuration==0.9 && abs(jumper.jumpHeight-58.5)<0.001,"Higher jump must preserve duration")
    for (gap,radius) in [(22.0,DefensePhysics.stealRadius),(29.0,DefensePhysics.blockRadius)] {
        let ball=LooseBall(ground:CGPoint(x:1000+gap,y:530),velocity:.zero,height:200)
        precondition(DefensePhysics.contact(from:ball,to:ball,hands:[balanceHand])==nil,"Balance sample should be outside old reach")
        precondition(DefensePhysics.contact(from:ball,to:ball,hands:[balanceHand],radius:radius)==0,"New defense reach should accept near-hand contact")
        var far=ball;far.ground.x=1040
        precondition(DefensePhysics.contact(from:far,to:far,hands:[balanceHand],radius:radius)==nil,"Defense must not steal/block from far away")
    }
    let g=GameSession();g.begin()
    for _ in 0..<181 { g.step() }
    precondition(g.phase == .playing && g.owner==0 && g.remaining>179.9,"Countdown/first possession")
    for id in 0..<2 {
        for distance:CGFloat in [150,550,1100] {
            for green in [true,false] {
                let m=GameSession();m.begin();m.phase = .playing
                let hoop=Hoop.all[id == 0 ? 1 : 0],sign:CGFloat=id == 0 ? 1 : -1
                m.players[id].position=CGPoint(x:hoop.center.x-sign*distance,y:530);m.players[id].facing=id == 0 ? .right : .left
                m.players[1-id].position=CGPoint(x:836,y:750);m.grant(id)
                m.players[id].action = .charge;m.players[id].pose=CharacterPose.target(action:"charge",progress:1,airProgress:nil,walking:false,clock:0)
                m.body=ActionSystem.held(m.players[id]);let aim=m.aimed(id)!
                let marker=green ? 0.5 : 0.5+ShotGauge.width(distance:aim.distance)/2+0.000001
                m.launch(id,marker:marker,dunk:false)
                precondition(m.canScore==green && m.players[id].score==0,"Release cannot score before ring crossing")
                for _ in 0..<210 { m.step() }
                precondition(green ? m.players[id].score>0 : m.players[id].score==0,"Symmetric green timing/scoring regression")
                precondition(m.players[1-id].score==0,"Wrong scorer")
            }
        }
    }
    let same=GameSession();same.phase = .playing;same.owner=0;same.players[0].position=CGPoint(x:1000,y:530);same.players[0].facing = .left
    precondition(same.aimed(0)==nil,"Cannot auto-aim at one's own basket")
    same.players[0].action = .charge;same.players[0].chargeTime=0.4
    same.execute(ActionCommand(id:1,tick:0,action:.jump),player:0)
    precondition(same.players[0].air==0 && same.players[0].action == .charge && same.players[0].chargeTime==0.4,"Jump must preserve charge")
    same.players[1].action = .defense;same.players[1].input=InputFrame(matchID:same.matchID,seq:1,tick:0,x:1,y:0,buttons:InputFrame.defend,actions:[])
    same.execute(ActionCommand(id:1,tick:0,action:.jump),player:1)
    precondition(same.players[1].action != .block && same.players[1].air==0,"C then Space must remain an ordinary jump")
    same.players[1].air=0.3;let feet=same.players[1].takeoffFeet
    same.execute(ActionCommand(id:2,tick:0,action:.block),player:1)
    precondition(same.players[1].action == .block && same.players[1].air==0.3 && same.players[1].takeoffFeet==feet,"Airborne V must preserve jump and takeoff")
    same.players[1].air=nil;same.players[1].action = .idle
    same.execute(ActionCommand(id:3,tick:0,action:.block),player:1)
    precondition(same.players[1].air==0 && same.players[1].action == .block,"Grounded V must jump-block")
    same.players[0].air=nil;same.players[0].action = .idle
    same.execute(ActionCommand(id:4,tick:0,action:.block),player:0)
    precondition(same.players[0].air==nil && same.players[0].action == .idle,"Ball owner cannot block")
    var defender=PlayerState(id:1,position:.zero,facing:.left);defender.action = .defense
    precondition(defender.speed==189,"Defense must retain ninety percent walk speed")
    defender.input=InputFrame(matchID:same.matchID,seq:1,tick:0,x:1,y:0,buttons:InputFrame.run,actions:[])
    precondition(abs(defender.speed-302.4)<0.001,"Defense Shift must retain ninety percent run speed")
    let landing=GameSession();landing.phase = .playing;landing.owner=0;landing.players[1].air=0.899
    landing.players[1].input=InputFrame(matchID:landing.matchID,seq:1,tick:0,x:0,y:0,buttons:InputFrame.defend,actions:[])
    landing.execute(ActionCommand(id:1,tick:0,action:.defend),player:1)
    precondition(landing.players[1].action != .block,"Airborne C must not block")
    landing.step();precondition(landing.players[1].action == .defense && landing.players[1].air==nil,"Held C must resume stance on landing")
    let clock=GameSession();clock.begin();clock.phase = .playing;clock.arrange(0);clock.shotClock=0.01;clock.step()
    precondition(clock.phase == .restart && clock.possession==1,"14-second violation must turn over")
    clock.arrange(0);clock.shotClock=4;clock.grant(0,rebound:true);precondition(clock.shotClock==6,"Offensive rebound minimum six")
    clock.grant(1,rebound:true);precondition(clock.shotClock==14,"Defensive rebound resets fourteen")
    clock.phase = .playing;clock.pause();let remaining=clock.remaining,shot=clock.shotClock
    for _ in 0..<120 { clock.step() }
    precondition(clock.remaining==remaining && clock.shotClock==shot,"Paused clocks changed")
    clock.resume();for _ in 0..<181 { clock.step() };precondition(clock.phase == .playing && clock.remaining==remaining,"Resume countdown cannot consume game time")
    clock.ingest(InputFrame(epoch:0,matchID:clock.matchID,seq:999,tick:clock.tick,x:1,y:0,buttons:0,actions:[]),player:0)
    precondition(clock.players[0].ackSeq==0,"Old pause/connection epoch input accepted")
    let end=GameSession();end.phase = .playing;end.remaining=0.01;end.step();precondition(end.overtime,"Tie must enter sudden death")
    end.phase = .playing;end.shooter=1;end.canScore=true;end.points=3;end.goal(0);precondition(end.phase == .finished && end.players[1].score==3,"Overtime first goal wins")
    let boundary=GameSession();boundary.phase = .playing;boundary.lastTouch=1;boundary.owner=nil;boundary.body=LooseBall(ground:CGPoint(x:836,y:254),velocity:CGPoint(x:0,y:-900),height:0,verticalVelocity:0);boundary.step()
    precondition(boundary.phase == .restart && boundary.possession==0,"Last-touch out-of-bounds turnover")
    let stale=GameSession();stale.phase = .playing
    stale.ingest(InputFrame(matchID:stale.matchID,seq:1,tick:0,x:1,y:0,buttons:0,actions:[]),player:0)
    for _ in 0..<30 { stale.step() };let stopped=stale.players[0].position
    for _ in 0..<10 { stale.step() };precondition(stale.players[0].position==stopped,"Lost input caused endless movement")
    let duplicate=GameSession();duplicate.phase = .playing;duplicate.arrange(0)
    duplicate.players[0].position=CGPoint(x:1300,y:530);duplicate.players[0].facing = .right;duplicate.players[1].position=CGPoint(x:500,y:730)
    let charge=ActionCommand(id:1,tick:0,action:.charge)
    duplicate.ingest(InputFrame(matchID:duplicate.matchID,seq:1,tick:0,x:0,y:0,buttons:2,actions:[charge]),player:0);duplicate.step()
    for step in 2...34 { duplicate.ingest(InputFrame(matchID:duplicate.matchID,seq:step,tick:duplicate.tick,x:0,y:0,buttons:2,actions:[charge]),player:0);duplicate.step() }
    let release=ActionCommand(id:2,tick:duplicate.tick+1,action:.release)
    for seq in 35...40 { duplicate.ingest(InputFrame(matchID:duplicate.matchID,seq:seq,tick:duplicate.tick,x:0,y:0,buttons:0,actions:[charge,release]),player:0);duplicate.step() }
    precondition(duplicate.players[0].ackAction==2 && duplicate.event.id==1 && duplicate.flight != nil,"Duplicated release launched twice")
    let obsolete=InputFrame(matchID:UUID().uuidString,seq:100,tick:duplicate.tick,x:1,y:0,buttons:0,actions:[])
    duplicate.ingest(obsolete,player:0);precondition(duplicate.players[0].ackSeq==40,"Previous match input accepted")
    let malformed=InputFrame(matchID:duplicate.matchID,seq:100,tick:duplicate.tick,x:Int.min,y:0,buttons:0,actions:[])
    precondition(!malformed.valid,"Malformed movement accepted")
    for tick in 0..<100 {
        duplicate.tick=tick
        let packet=LANDatagram(token:UUID().uuidString,kind:"snapshot",snapshot:duplicate.snapshot())
        let data=try! JSONEncoder().encode(packet)
        precondition(data.count<=LANProtocol.maxDatagram,"Snapshot exceeds one datagram: \(data.count)")
        precondition((try! JSONDecoder().decode(LANDatagram.self,from:data)).snapshot!.valid,"Snapshot round trip")
    }
    // Stress every bounded wire field, exact timing/context precision and the
    // complete UTF-8 event budget together, not just a typical idle snapshot.
    var maximal=duplicate.snapshot()
    maximal.epoch=Int.max/2-1;maximal.tick=Int.max/2-1;maximal.phase = .endingShot
    maximal.phaseTime = .greatestFiniteMagnitude;maximal.remaining=179.999;maximal.shotClock=13.999;maximal.overtime=true
    for id in 0..<2 {
        maximal.players[id].position=CGPoint(x:2999.999,y:1999.999)
        maximal.players[id].moving=true;maximal.players[id].facing = .downRight;maximal.players[id].action = .catchBall
        maximal.players[id].elapsed = .greatestFiniteMagnitude;maximal.players[id].air = .greatestFiniteMagnitude;maximal.players[id].airDuration=2.2
        maximal.players[id].charge = .greatestFiniteMagnitude;maximal.players[id].gait = .greatestFiniteMagnitude;maximal.players[id].reach = .greatestFiniteMagnitude
        maximal.players[id].shotWidth=0.07456789123456789;maximal.players[id].contest=0.6234567890123456
        maximal.players[id].score=Int.max;maximal.players[id].steals=Int.max;maximal.players[id].blocks=Int.max;maximal.players[id].rebounds=Int.max
        maximal.players[id].ackSeq=Int.max;maximal.players[id].ackAction=Int.max
    }
    maximal.ball=BallPacket(owner:1,shooter:0,ground:CGPoint(x:2999.999,y:1999.999),height:9999.999)
    maximal.event=MatchEvent(id:Int.max,tick:Int.max/2-1,kind:String(repeating:"가",count:53),player:1,points:Int.max)
    precondition(maximal.valid && maximal.event.kind.utf8.count==159,"Extreme packet fixture must remain within every accepted field bound")
    let maximalData=try! JSONEncoder().encode(LANDatagram(token:UUID().uuidString,kind:"snapshot",snapshot:maximal))
    precondition(maximalData.count<=LANProtocol.maxDatagram,"Maximum permitted snapshot exceeds one datagram: \(maximalData.count)")
    let maximalRoundTrip=(try! JSONDecoder().decode(LANDatagram.self,from:maximalData)).snapshot!
    precondition(maximalRoundTrip.valid && maximalRoundTrip.players[0].shotWidth==maximal.players[0].shotWidth,"Maximum UTF-8/precision packet must decode without changing the green edges")
    let buffer=SnapshotBuffer();let a=duplicate.snapshot();precondition(buffer.accept(a));precondition(!buffer.accept(a),"Stale/duplicated snapshot")
    let input=InputController();input.key(7,down:true,tick:1);input.key(7,down:false,tick:34)
    for _ in 0..<10 { precondition(input.frame(matchID:"test",tick:35).actions.count==2,"Lost release cannot disappear before ACK") }
    input.acknowledge(seq:10,action:2);precondition(input.pending.isEmpty)
    for defender in 0..<2 {
        for time in [0.08,0.30,0.34] {
            let steal=GameSession(),attacker=1-defender,sign:CGFloat=defender==0 ? 1 : -1
            steal.phase = .playing;steal.players[attacker].position=CGPoint(x:1000,y:600);steal.players[attacker].facing=sign>0 ? .left : .right;steal.grant(attacker)
            steal.players[attacker].dribble=0.12;steal.body=ActionSystem.held(steal.players[attacker])
            steal.players[defender].position=CGPoint(x:steal.body.ground.x-sign*72,y:600);steal.players[defender].facing=sign>0 ? .right : .left
            steal.players[defender].action = .steal;steal.players[defender].elapsed=time;steal.players[defender].reach=1
            steal.players[defender].pose=CharacterPose.target(action:"defense",progress:0.5,airProgress:nil,walking:false,clock:0)
            steal.step();precondition(steal.owner==defender,"Extended early/late steal window must work for either player")
        }
        let m=GameSession(),attacker=1-defender,sign:CGFloat=defender==0 ? 1 : -1
        m.phase = .playing;m.players[attacker].position=CGPoint(x:1000,y:600);m.players[attacker].facing=sign>0 ? .left : .right;m.grant(attacker)
        m.players[attacker].dribble=0.12;m.body=ActionSystem.held(m.players[attacker])
        m.players[defender].position=CGPoint(x:m.body.ground.x-sign*72,y:600);m.players[defender].facing=sign>0 ? .right : .left
        m.players[defender].action = .steal;m.players[defender].elapsed=0.15;m.players[defender].reach=1
        m.players[defender].pose=CharacterPose.target(action:"defense",progress:0.5,airProgress:nil,walking:false,clock:0)
        m.step();precondition(m.owner==defender && m.players[defender].steals==1,"Both players must share real steal contacts")
        let blocked=GameSession();blocked.phase = .playing;blocked.shooter=attacker;blocked.canScore=true
        blocked.players[attacker].position=CGPoint(x:1000+sign*100,y:530)
        blocked.players[defender].position=CGPoint(x:1000,y:530);blocked.players[defender].facing=sign>0 ? .right : .left
        blocked.players[defender].action = .block;blocked.players[defender].air=0.45;blocked.players[defender].elapsed=0.3
        blocked.players[defender].pose=CharacterPose.target(action:"block",progress:0.4,airProgress:0.5,walking:false,clock:0)
        let hand=ActionSystem.hands(blocked.players[defender])[1]
        blocked.flight=ShotFlight(startGround:CGPoint(x:hand.ground.x+sign*8,y:hand.ground.y),startHeight:hand.height,endGround:CGPoint(x:hand.ground.x-sign*180,y:hand.ground.y),distance:188,points:2,targetHeight:hand.height)
        blocked.body=blocked.flight!.sample(at:0);blocked.step()
        precondition(blocked.players[defender].blocks==1 && blocked.flight==nil && !blocked.canScore,"Both players must block with same authority")
        let catchBall=GameSession();catchBall.phase = .playing;catchBall.players[defender]=blocked.players[defender]
        let catcher=ActionSystem.hands(catchBall.players[defender])[1]
        catchBall.body=LooseBall(ground:catcher.ground,velocity:.zero,height:catcher.height,verticalVelocity:-50)
        catchBall.step();precondition(catchBall.owner==defender && catchBall.players[defender].rebounds==1,"Airborne hand-contact rebound")
    }
    let buzzer=GameSession();buzzer.phase = .playing;buzzer.remaining=0.01;buzzer.players[0].position=CGPoint(x:1300,y:530);buzzer.players[0].facing = .right;buzzer.grant(0)
    buzzer.players[0].action = .charge;buzzer.players[0].pose=CharacterPose.target(action:"charge",progress:1,airProgress:nil,walking:false,clock:0);buzzer.body=ActionSystem.held(buzzer.players[0]);buzzer.launch(0,marker:0.5,dunk:false)
    buzzer.step();precondition(buzzer.phase == .endingShot,"Shot before buzzer must stay live")
    for _ in 0..<160 { buzzer.step() };precondition(buzzer.phase == .finished && buzzer.players[0].score==2,"Buzzer shot must decide result")
    for attacker in 0..<2 {
        var successes=0
        for preparation in [6,10,14,18] {
            let m=GameSession(),defender=1-attacker,sign:CGFloat=attacker==0 ? 1 : -1
            m.phase = .playing;m.players[attacker].position=CGPoint(x:attacker==0 ? 1300 : 330,y:530)
            m.players[attacker].facing=sign>0 ? .right : .left;m.grant(attacker)
            m.players[attacker].action = .charge
            m.players[attacker].pose=CharacterPose.target(action:"charge",progress:1,airProgress:nil,walking:false,clock:0)
            m.body=ActionSystem.held(m.players[attacker])
            m.players[defender].position=CGPoint(x:m.players[attacker].position.x+sign*85,y:530)
            m.players[defender].facing=sign>0 ? .left : .right
            m.players[defender].input=InputFrame(matchID:m.matchID,seq:1,tick:0,x:0,y:0,buttons:InputFrame.defend,actions:[])
            m.execute(ActionCommand(id:1,tick:0,action:.block),player:defender)
            for _ in 0..<preparation { m.step() }
            m.launch(attacker,marker:0.5,dunk:false)
            for _ in 0..<65 { m.step() }
            if m.players[defender].blocks>0 { successes += 1 }
            precondition(m.players[defender].blocks<=1,"One jump cannot block repeatedly")
        }
        precondition(successes>=2,"A normal close-range LAN shot needs several usable block timings, attacker \(attacker), successes \(successes)")
    }
    print("PASS: common match rules, both scorers, strict green, charge-jump, fourteen-second possession, pause, overtime, out-of-bounds, stale input, action deduplication and datagram bounds")
}

func runLANViewTests() {
    func key(_ code:UInt16,_ type:NSEvent.EventType = .keyDown,_ chars:String="")->NSEvent {
        NSEvent.keyEvent(with:type,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:chars,charactersIgnoringModifiers:chars,isARepeat:false,keyCode:code)!
    }
    let root=GameRootView(frame:NSRect(x:0,y:0,width:840,height:550))
    for _ in 0..<3 { root.keyDown(with:key(125)) };root.keyDown(with:key(36))
    precondition(root.screen == .help,"Keyboard menu selection")
    root.keyDown(with:key(53));precondition(root.screen == .home,"Keyboard back")
    root.network.role = .host;root.network.game.phase = .playing;root.network.game.arrange(0)
    let view=LANMatchView(frame:root.bounds,network:root.network);view.timer?.invalidate()
    view.keyDown(with:key(7,.keyDown,"ㅌ"));view.keyUp(with:key(7,.keyUp,"ㅌ"))
    precondition(root.network.input.pending.map(\.action)==[.charge,.release],"Hangul input state must not alter physical X key")
    view.keyDown(with:key(8));view.keyDown(with:key(49));view.keyDown(with:key(9));view.keyDown(with:key(11,.keyDown,"ㅠ"));view.keyDown(with:key(123))
    precondition(root.network.input.pending.suffix(4).map(\.action)==[.defend,.jump,.block,.steal] && root.network.input.x == -1,"Separate C/Space/V/B/arrow commands, including Hangul B")
    _ = view.resignFirstResponder();precondition(root.network.input.buttons==0 && root.network.input.x==0,"Focus loss must clear held controls")
    for phase:MatchPhase in [.countdown,.playing,.restart,.endingShot] {
        root.screen = .match;root.network.game.phase=phase;root.lostFocus()
        precondition(root.network.game.phase == .paused,"Focus loss must pause every active match phase")
    }
    let client=NetworkSession();client.role = .client
    let clientView=LANMatchView(frame:root.bounds,network:client);clientView.timer?.invalidate()
    let authority=GameSession();authority.phase = .playing;authority.tick=100
    authority.players[1].position=CGPoint(x:900,y:530);authority.players[1].facing = .left;authority.grant(1)
    authority.body=ActionSystem.held(authority.players[1]);authority.body.height=23.456
    client.game=authority;client.input.x=1;client.input.buttons=InputFrame.run
    let dribbleGround=authority.body.ground,dribbleHeight=authority.body.height
    let dribble=authority.snapshot();precondition(client.snapshots.accept(dribble))
    _ = client.input.frame(matchID:dribble.matchID,tick:dribble.tick+2,epoch:dribble.epoch)
    clientView.last=ProcessInfo.processInfo.systemUptime-1.0/60;clientView.updateFrame()
    let drawnDribble=clientView.shown!,carrier=drawnDribble.players[1].position
    let expectedDribble=CGPoint(x:dribble.ball.ground.x+carrier.x-dribble.players[1].position.x,y:dribble.ball.ground.y+carrier.y-dribble.players[1].position.y)
    precondition(carrier.x>dribble.players[1].position.x,"Owned-ball coupling sample must include unacknowledged local movement prediction")
    precondition(hypot(drawnDribble.ball.ground.x-expectedDribble.x,drawnDribble.ball.ground.y-expectedDribble.y)<0.000001 && drawnDribble.ball.height==dribble.ball.height,"Predicted local dribble must keep the authoritative root offset and bounce height")
    precondition(authority.body.ground==dribbleGround && authority.body.height==dribbleHeight && client.latest?.ball.ground==dribble.ball.ground,"Owned-ball display prediction must not move the authority or buffered packet")
    authority.tick=102;authority.players[1].action = .charge;authority.players[1].chargeTime=0.55
    authority.players[1].pose=CharacterPose.target(action:"charge",progress:ShotGauge.poseProgress(time:0.55),airProgress:nil,walking:false,clock:0)
    authority.body=ActionSystem.held(authority.players[1]);authority.players[1].shotWidth=authority.shotContext(1).width
    let chargeGround=authority.body.ground,chargeHeight=authority.body.height
    let charge=authority.snapshot();precondition(client.snapshots.accept(charge))
    clientView.last=ProcessInfo.processInfo.systemUptime-1.0/60;clientView.updateFrame()
    let drawnCharge=clientView.shown!;var drawnState=drawnCharge.players[1].state;drawnState.pose=clientView.poses[1]
    let expectedHeld=ActionSystem.held(drawnState)
    precondition(drawnCharge.ball.ground==expectedHeld.ground && drawnCharge.ball.height==expectedHeld.height,"Locally gathered ball must follow the interpolated displayed shooting hand, not a stale remote charge pose")
    precondition(authority.body.ground==chargeGround && authority.body.height==chargeHeight && client.latest?.ball.ground==charge.ball.ground,"Gather display coupling must leave host physics and the latest authority packet untouched")
    client.stop()
    root.showHome();precondition(root.screen == .home && root.network.role == .idle,"Leave/menu must not recurse")
    print("PASS: keyboard menus, Hangul physical key mapping, input combinations, predicted local dribble/gather ball attachment, focus clearing and pause/menu lifecycle")
}

/// Fresh endpoints repeatedly exercise the first-packet hello/ready/ping order.
/// These are still loopback connections on this Mac, not two-Mac Wi-Fi.
func runLANColdHandshakeTests() {
    func wait(_ seconds:Double,until predicate:()->Bool)->Bool {
        let deadline=Date().addingTimeInterval(seconds)
        while Date()<deadline { if predicate() { return true };RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
        return predicate()
    }
    for attempt in 1...3 {
        let host=NetworkSession(),client=NetworkSession()
        host.host(name:"Cold Host",room:"Cold Handshake \(attempt)",advertise:false)
        host.setReady();precondition(host.ready==[false,false],"Host cannot become ready before a peer/UDP handshake")
        precondition(wait(8,until:{host.tcpPort != nil}),"Cold listener start failed, attempt \(attempt): \(host.status)")
        precondition(client.direct("127.0.0.1:\(host.tcpPort!)",name:"Cold Client"))
        precondition(!client.udpReady && !client.peerPresent,"Cold fixture must exercise a pre-hello participant")
        client.setReady();precondition(client.ready==[false,false],"Early ready input must not be queued before the client's hello, attempt \(attempt)")
        precondition(wait(8,until:{host.udpReady && client.udpReady && host.peerPresent && client.peerPresent}),"Cold hello/welcome/UDP failed, attempt \(attempt): host \(host.status), client \(client.status)")
        host.setReady();client.setReady()
        precondition(wait(2,until:{host.ready.allSatisfy{$0} && client.ready.allSatisfy{$0}}),"Ready must work normally after a cold handshake, attempt \(attempt)")
        client.stop();precondition(wait(2,until:{!host.peerPresent}),"Cold client leave was not delivered, attempt \(attempt)")
        host.stop()
    }
    print("PASS: three fresh loopback TCP/UDP handshakes; early ready cannot precede hello, connected readiness and leave remain functional")
}

/// Real TCP+UDP, two endpoints on this Mac only. This does NOT certify two-Mac Wi-Fi.
func runLANTransportTests() {
    runLANColdHandshakeTests()
    let host=NetworkSession(),root=GameRootView(frame:NSRect(x:0,y:0,width:840,height:550))
    let client=root.network;root.screen = .lobby
    host.host(name:"Host Test",room:"Loopback Test",advertise:false)
    func wait(_ seconds:Double,until predicate:()->Bool)->Bool {
        let deadline=Date().addingTimeInterval(seconds)
        while Date()<deadline { if predicate() { return true };RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
        return predicate()
    }
    precondition(wait(8,until:{host.tcpPort != nil}),"TCP/UDP listeners failed: \(host.status)")
    precondition(client.direct("127.0.0.1:\(host.tcpPort!)",name:"Client Test"))
    precondition(!client.udpReady && !client.peerPresent,"Participant early-ready fixture must start before hello/UDP completion")
    client.setReady();precondition(client.ready==[false,false],"Participant ready before handshake must leave readiness unchanged")
    precondition(wait(8,until:{host.udpReady && client.udpReady}),"TCP handshake / UDP binding failed: host=\(host.status), client=\(client.status)")
    let readyButton=root.buttons[0],menu=root.stack
    let lobbyTick=client.latest!.tick
    precondition(wait(1,until:{client.latest!.tick>lobbyTick+20}),"Lobby snapshots not received")
    precondition(root.buttons[0] === readyButton && root.stack === menu,"Lobby snapshots replaced participant ready button")
    host.setReady();readyButton.performClick(nil)
    precondition(wait(2,until:{host.ready.allSatisfy{$0} && client.ready.allSatisfy{$0}}),"Lobby ready sync")
    precondition(root.buttons[0].title=="준비 취소","Participant ready click was not reflected")
    root.network.onChange=nil // Remaining checks exercise transport without a live view.
    host.startMatch()
    precondition(wait(5,until:{host.game.phase == .playing && client.latest?.phase == .playing}),"Shared countdown/start")
    precondition(host.game.matchID==client.latest!.matchID && client.localID==1,"Match/assigned player mismatch")
    client.input.key(9,down:true,tick:client.estimatedTick+2);client.sendInputNow()
    precondition(wait(2,until:{host.game.players[1].action == .block && (host.game.players[1].air ?? 0)>0.2}),"Remote V must jump-block")
    let air=host.game.players[1].air!
    client.input.key(49,down:true,tick:client.estimatedTick+2);client.sendInputNow()
    precondition(wait(1,until:{host.game.players[1].ackAction>=2 && (host.game.players[1].air ?? 0)>=air}),"Space cannot restart an airborne block")
    client.input.key(49,down:false,tick:client.estimatedTick+2);client.input.key(9,down:false,tick:client.estimatedTick+2);client.sendInputNow()
    precondition(wait(2,until:{host.game.players[1].air==nil && host.game.players[1].action == .idle}),"V block must land and recover")
    client.input.key(8,down:true,tick:client.estimatedTick+2);client.sendInputNow()
    precondition(wait(2,until:{host.game.players[1].action == .defense && client.latest?.players[1].action == .defense}),"Remote C must synchronize a hands-up stance, not a steal")
    precondition(host.game.owner==0 && host.game.players[1].steals==0,"Remote hands-up cannot automatically change possession")
    client.input.key(11,down:true,tick:client.estimatedTick+2);client.sendInputNow()
    precondition(wait(2,until:{host.game.players[1].action == .steal && client.latest?.players[1].action == .steal}),"Remote B must start its own reliable steal command")
    precondition(wait(2,until:{host.game.players[1].action == .defense && host.game.players[1].cooldown==0}),"Holding B must recover once, then return to the held-C stance")
    precondition(host.game.owner==0 && host.game.players[1].steals==0,"A distant remote B must not steal without hand contact")
    client.input.key(11,down:false,tick:client.estimatedTick+2);client.input.key(8,down:false,tick:client.estimatedTick+2);client.sendInputNow()
    precondition(wait(2,until:{host.game.players[1].action == .idle}),"Releasing C must clear the remote stance")
    host.debugDropEvery=4;client.debugDropEvery=4
    let old=host.game.players[1].position
    client.input.key(123,down:true,tick:client.estimatedTick+2);client.sendInputNow()
    precondition(wait(1,until:{host.game.players[1].position.x<old.x-20}),"Remote movement under packet loss")
    client.input.key(123,down:false,tick:client.estimatedTick+2);client.sendInputNow()
    host.game.players[1].position=CGPoint(x:330,y:530);host.game.players[1].facing = .left;host.game.grant(1);host.game.body=ActionSystem.held(host.game.players[1])
    precondition(wait(2,until:{client.latest?.ball.owner==1}),"Single owner sync")
    client.input.key(7,down:true,tick:client.estimatedTick+2);client.sendInputNow()
    precondition(wait(2,until:{host.game.players[1].action == .charge && host.game.players[1].chargeTime>=0.55}),"Remote charge start")
    client.input.key(7,down:false,tick:client.estimatedTick);client.sendInputNow()
    precondition(wait(3,until:{host.game.players[1].score==2 && client.latest?.players[1].score==2}),"Release/scoring/score sync under packet loss")
    precondition(host.game.players[0].score==0,"Client points credited to host")
    precondition(wait(2,until:{host.game.phase == .playing}),"Loser's central restart")
    client.pause();precondition(wait(2,until:{host.game.phase == .paused && client.latest?.phase == .paused}),"Remote pause request")
    let remaining=host.game.remaining
    _=wait(0.2,until:{false});precondition(host.game.remaining==remaining,"Paused transport advanced clock")
    host.setReady();client.setReady();precondition(wait(2,until:{host.ready.allSatisfy{$0}}));host.startMatch()
    precondition(wait(5,until:{host.game.phase == .playing && client.latest?.phase == .playing}),"Resume readiness/countdown")
    for latency in [20,50,100] {
        host.debugDelayMS=latency/2;client.debugDelayMS=latency/2;host.debugJitterMS=10;client.debugJitterMS=10
        let y=host.game.players[1].position.y
        client.input.key(126,down:true,tick:client.estimatedTick+2);client.sendInputNow()
        precondition(wait(2,until:{host.game.players[1].position.y<y-20}),"Movement at RTT \(latency)ms")
        client.input.key(126,down:false,tick:client.estimatedTick+2);client.sendInputNow()
        let stoppedSeq=client.input.seq
        precondition(wait(2,until:{host.game.players[1].input?.y==0 && host.game.players[1].ackSeq>=stoppedSeq}),"Stop acknowledgement before test reposition")
        let score=host.game.players[1].score
        host.game.players[1].position=CGPoint(x:330,y:530);host.game.players[1].facing = .left;host.game.grant(1);host.game.body=ActionSystem.held(host.game.players[1])
        precondition(wait(2,until:{client.latest?.ball.owner==1}))
        client.input.key(7,down:true,tick:client.estimatedTick+2);client.sendInputNow()
        precondition(wait(2,until:{host.game.players[1].action == .charge && host.game.players[1].chargeTime>=0.55}))
        client.input.key(7,down:false,tick:client.estimatedTick);client.sendInputNow()
        precondition(wait(3,until:{host.game.players[1].score==score+2 && client.latest?.players[1].score==score+2}),"Release at RTT \(latency)ms with loss/jitter: host \(host.game.players[1].score), client \(client.latest?.players[1].score ?? -1), facing \(host.game.players[1].facing), event \(host.game.event.kind), charge \(host.game.players[1].chargeTime), ack \(host.game.players[1].ackAction), input actions \(client.input.pending.map { $0.action.rawValue })")
        precondition(wait(2,until:{host.game.phase == .playing}))
    }
    host.debugDelayMS=0;client.debugDelayMS=0;host.debugJitterMS=0;client.debugJitterMS=0
    let epoch=host.game.inputEpoch
    client.disconnectForTest()
    precondition(wait(8,until:{host.udpReady && client.udpReady && host.game.inputEpoch>epoch}),"Reconnect/session rebinding")
    precondition(host.game.phase == .paused,"Disconnect must freeze official match")
    host.setReady();client.setReady();precondition(wait(2,until:{host.ready.allSatisfy{$0}}));host.startMatch()
    precondition(wait(5,until:{host.game.phase == .playing && client.latest?.phase == .playing}))
    host.game.players[0].score=0;host.game.players[1].score=2;host.game.finish()
    precondition(wait(2,until:{client.latest?.phase == .finished}),"Result synchronization")
    let matchID=host.game.matchID;host.rematch();client.rematch()
    precondition(wait(2,until:{host.game.matchID != matchID && client.latest?.matchID==host.game.matchID}),"New rematch identity")
    precondition(host.game.firstServe==1,"Rematch opening possession must alternate")
    client.stop();precondition(wait(2,until:{!host.peerPresent}),"Leave handling")
    host.stop()
    print("PASS: loopback TCP/UDP, stable lobby-ready button, separate remote C/B/V controls, two players, RTT 20/50/100ms + jitter + 25% loss, reliable release, score sync, pause/resume, reconnect, results, rematch and leave. TWO-MAC WIFI TEST STILL REQUIRED.")
}
