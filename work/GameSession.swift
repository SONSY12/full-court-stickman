import Foundation

private func wireNumber(_ value:Double)->Double { (value*1000).rounded()/1000 }
private func wirePoint(_ value:CGPoint)->CGPoint { CGPoint(x:CGFloat(wireNumber(Double(value.x))),y:CGFloat(wireNumber(Double(value.y)))) }

enum MatchPhase:String,Codable { case lobby,countdown,playing,restart,paused,endingShot,finished }
struct PlayerState {
    let id:Int
    var position:CGPoint
    var facing:Facing
    var action:GameAction = .idle
    var elapsed:Double=0
    var air:Double?
    var airDuration:Double=0.9
    var chargeTime:Double=0
    var cooldown:Double=0
    var reach:CGFloat=0
    var contactUsed=false
    var gait:Double=0
    var moving=false
    var dribble:Double=0
    var takeoffFeet:[CGPoint]?
    var pose=CharacterPose.target(action:"",progress:0,airProgress:nil,walking:false,clock:0)
    var input:InputFrame?
    var inputAt=0
    var ackSeq=0,ackAction=0
    var queued:[ActionCommand]=[]
    var score=0,steals=0,blocks=0,rebounds=0
    var attackHoop:Int { id == 0 ? 1 : 0 }
    var jumpHeight:CGFloat {
        guard let air else { return 0 }; let t=air/airDuration
        return CGFloat(t>0.2 && t<0.8 ? 45*sin(.pi*(t-0.2)/0.6) : 0)
    }
    var actionDuration:Double {
        switch action { case .shot:return 0.75; case .steal:return 0.4; case .block:return 0.75; case .dunk:return 1.1; case .catchBall:return 0.25; default:return 1.6 }
    }
    var poseAction:String {
        switch action { case .idle:return air == nil ? "" : "jump"; case .shot:return air == nil ? "shot" : "jumpShot"; case .steal:return "defense"; case .catchBall:return "charge"; default:return action.rawValue }
    }
    var speed:CGFloat {
        if [.defense,.steal].contains(action) { return 138 }
        if action == .charge { return 105 }
        return (input?.buttons ?? 0)&InputFrame.run != 0 ? 336 : 210
    }
}

enum ActionSystem {
    static func joint(_ index:Int,player p:PlayerState)->DefenseHand {
        let j=p.pose.joints[index]
        var x=(j.x-256)*0.3*p.facing.bodyWidth*p.facing.handSide, depth:CGFloat=0
        if [5,6].contains(index),p.reach>0 {
            let weight=max(0,min(1,(p.pose.joints[6].x-347)/149))*p.reach
            let reach:CGFloat=index == 6 ? 72 : 36
            let fullX:CGFloat=index == 6 ? 496 : 376
            x += (p.facing.vector.x*reach-(fullX-256)*0.3*p.facing.bodyWidth*p.facing.handSide)*weight
            depth=p.facing.vector.y*reach*weight/Hoop.groundDepthScale
        }
        return DefenseHand(ground:CGPoint(x:p.position.x+x,y:p.position.y+depth),height:(691-j.y)*0.3+p.jumpHeight-Basketball.radius)
    }
    static func hands(_ p:PlayerState)->[DefenseHand] { [4,6].map { joint($0,player:p) } }
    static func feet(_ p:PlayerState)->[CGPoint] { [8,10].map { joint($0,player:p).ground } }
    static func held(_ p:PlayerState)->LooseBall {
        if [.charge,.shot,.dunk,.catchBall].contains(p.action) {
            let h=joint(6,player:p)
            return LooseBall(ground:CGPoint(x:h.ground.x+2.4*p.facing.bodyWidth*p.facing.handSide,y:p.position.y),velocity:.zero,height:max(0,h.height+7.2),verticalVelocity:0)
        }
        return LooseBall(ground:CGPoint(x:p.position.x+31*p.facing.bodyWidth*p.facing.handSide,y:p.position.y),velocity:.zero,height:CGFloat(abs(sin(p.dribble*5.2)))*65+p.jumpHeight,verticalVelocity:0)
    }
    static func clamp(_ p:inout PlayerState) {
        p.position.y=max(CourtBounds.top,min(CourtBounds.bottom,p.position.y))
        let offsets=[8,10].map { (p.pose.joints[$0].x-256)*0.3*p.facing.bodyWidth*p.facing.handSide }
        let inset=CourtBounds.inset(at:p.position.y)
        p.position.x=max(inset-offsets.min()!,min(1672-inset-offsets.max()!,p.position.x))
    }
}

struct PlayerPacket:Codable {
    var moving:Bool
    var id:Int; var position:CGPoint; var facing:Facing; var action:GameAction; var elapsed:Double; var air:Double?; var airDuration:Double; var charge:Double; var reach:CGFloat; var gait:Double; var score:Int; var steals:Int; var blocks:Int; var rebounds:Int; var ackSeq:Int; var ackAction:Int
    enum CodingKeys:String,CodingKey { case moving="w",id="i",position="p",facing="f",action="a",elapsed="e",air="h",airDuration="d",charge="c",reach="r",gait="g",score="s",steals="v",blocks="b",rebounds="u",ackSeq="q",ackAction="k" }
    init(_ p:PlayerState) { moving=p.moving;id=p.id;position=wirePoint(p.position);facing=p.facing;action=p.action;elapsed=wireNumber(p.elapsed);air=p.air.map(wireNumber);airDuration=wireNumber(p.airDuration);charge=wireNumber(p.chargeTime);reach=CGFloat(wireNumber(Double(p.reach)));gait=wireNumber(p.gait);score=p.score;steals=p.steals;blocks=p.blocks;rebounds=p.rebounds;ackSeq=p.ackSeq;ackAction=p.ackAction }
    var state:PlayerState { var p=PlayerState(id:id,position:position,facing:facing);p.action=action;p.elapsed=elapsed;p.air=air;p.airDuration=airDuration;p.chargeTime=charge;p.reach=reach;p.gait=gait;p.moving=moving;return p }
}
struct BallPacket:Codable {
    var owner:Int?; var shooter:Int?; var ground:CGPoint; var height:CGFloat
    enum CodingKeys:String,CodingKey { case owner="o",shooter="s",ground="g",height="h" }
}
struct MatchEvent:Codable {
    var id:Int;var tick:Int;var kind:String;var player:Int?;var points:Int
    enum CodingKeys:String,CodingKey { case id="i",tick="t",kind="k",player="p",points="s" }
}
struct MatchSnapshot:Codable {
    var epoch:Int=0
    var matchID:String;var tick:Int;var phase:MatchPhase;var phaseTime:Double;var remaining:Double;var shotClock:Double;var overtime:Bool;var players:[PlayerPacket];var ball:BallPacket;var event:MatchEvent
    enum CodingKeys:String,CodingKey { case epoch="z",matchID="m",tick="t",phase="p",phaseTime="e",remaining="r",shotClock="c",overtime="o",players="u",ball="b",event="v" }
    var valid:Bool {
        guard players.count==2,players.map(\.id)==[0,1],epoch>=0,tick>=0,tick<Int.max/2,
              remaining.isFinite,remaining>=0,remaining<=180,shotClock.isFinite,shotClock>=0,shotClock<=14,
              phaseTime.isFinite,ball.height.isFinite,abs(ball.height)<10000,ball.ground.x.isFinite,ball.ground.y.isFinite,
              ball.owner == nil || [0,1].contains(ball.owner!),ball.shooter == nil || [0,1].contains(ball.shooter!),event.kind.utf8.count<=160 else { return false }
        return players.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && abs($0.position.x)<3000 && abs($0.position.y)<2000 && $0.elapsed.isFinite && $0.charge.isFinite && $0.reach.isFinite && $0.gait.isFinite && $0.airDuration>0 && $0.airDuration<=2.2 && ($0.air?.isFinite ?? true) && $0.score>=0 && $0.ackSeq>=0 && $0.ackAction>=0 }
    }
}

/// Host-only authority. Both players enter through the same semantic input queue.
final class GameSession {
    static let step=1.0/60
    var matchID=UUID().uuidString
    var tick=0
    var inputEpoch=0
    var phase:MatchPhase = .lobby
    var phaseTime:Double=0
    var remaining:Double=180
    var shotClock:Double=14
    var overtime=false
    var players=[PlayerState(id:0,position:CGPoint(x:720,y:570),facing:.right),PlayerState(id:1,position:CGPoint(x:950,y:570),facing:.left)]
    var owner:Int?
    var body=LooseBall(ground:CGPoint(x:836,y:570),velocity:.zero,height:0,verticalVelocity:0)
    var flight:ShotFlight?
    var shooter:Int?
    var lastTouch=0
    var points=2
    var canScore=false
    var pendingShot=false
    var possession=0
    var firstServe=0
    var priority=0
    var pausedFrom:MatchPhase = .playing
    var pausedPhaseTime:Double=0
    var resumeCountdown=false
    var event=MatchEvent(id:0,tick:0,kind:"준비",player:nil,points:0)
    func emit(_ kind:String,player:Int?=nil,points:Int=0) { event=MatchEvent(id:event.id+1,tick:tick,kind:kind,player:player,points:points) }
    func begin(firstServe:Int=0) {
        let fresh=GameSession(); matchID=fresh.matchID;tick=0;inputEpoch=0;players=fresh.players
        owner=nil;body=fresh.body;flight=nil;shooter=nil;canScore=false;pendingShot=false
        remaining=180;shotClock=14;overtime=false;self.firstServe=firstServe;priority=firstServe;possession=firstServe
        phase = .countdown;phaseTime=0;resumeCountdown=false;emit("경기 시작")
    }
    func pause() {
        guard [.playing,.countdown,.restart,.endingShot].contains(phase) else { return }
        pausedFrom=phase;pausedPhaseTime=phaseTime;phase = .paused
        for i in 0..<2 { players[i].input=nil;players[i].moving=false;players[i].queued.removeAll();if players[i].action == .charge { players[i].action = .idle;players[i].chargeTime=0 } }
        emit("일시정지")
    }
    func resetInputEpoch() {
        inputEpoch += 1
        for id in 0..<2 { players[id].ackSeq=0;players[id].ackAction=0;players[id].queued.removeAll();players[id].input=nil }
    }
    func resume() { guard phase == .paused else { return };resetInputEpoch();phase = .countdown;phaseTime=0;resumeCountdown=true;emit("재개 준비") }
    func ingest(_ frame:InputFrame,player:Int) {
        guard [0,1].contains(player),frame.valid,frame.matchID==matchID,frame.epoch==inputEpoch,frame.tick<=tick+15,frame.tick>=tick-120 else { return }
        if frame.seq>players[player].ackSeq { players[player].input=frame;players[player].ackSeq=frame.seq;players[player].inputAt=tick }
        if phase != .playing { players[player].ackAction=max(players[player].ackAction,frame.actions.map(\.id).max() ?? 0);return }
        // A lost release remains in later frames until its contiguous ID is acknowledged.
        for command in frame.actions.sorted(by:{$0.id<$1.id}) {
            guard command.id>players[player].ackAction,command.id<=players[player].ackAction+12,
                  command.tick<=tick+15,command.tick>=tick-120,
                  !players[player].queued.contains(where:{$0.id==command.id}) else { continue }
            players[player].queued.append(command)
        }
        players[player].queued.sort { $0.id<$1.id }
    }
    func grant(_ id:Int,rebound:Bool=false) {
        let previous=possession
        owner=id;lastTouch=id;possession=id;flight=nil;canScore=false;pendingShot=false
        shotClock=previous != id ? 14 : rebound ? max(6,shotClock) : shotClock
        players[id].action = rebound ? .catchBall : .idle;players[id].elapsed=0
        if rebound { players[id].rebounds += 1;emit("리바운드",player:id) }
    }
    func arrange(_ receiver:Int) {
        for i in 0..<2 { players[i].position=CGPoint(x:i == receiver ? 836 : receiver == 0 ? 980 : 692,y:570);players[i].facing=i == 0 ? .right : .left;players[i].action = .idle;players[i].air=nil;players[i].elapsed=0;players[i].chargeTime=0;players[i].queued.removeAll() }
        body=LooseBall(ground:CGPoint(x:836,y:570),velocity:.zero,height:0,verticalVelocity:0)
        possession=receiver;shotClock=14;shooter=nil;grant(receiver);body=ActionSystem.held(players[receiver])
    }
    func turnover(to id:Int,reason:String) { owner=nil;flight=nil;canScore=false;pendingShot=false;possession=id;body=LooseBall(ground:CGPoint(x:836,y:570),velocity:.zero,height:0,verticalVelocity:0);phase = .restart;phaseTime=0;emit(reason,player:id) }
    func aimed(_ id:Int)->(index:Int,distance:CGFloat,end:CGPoint)? {
        let origin=CGPoint(x:owner == id ? body.ground.x : players[id].position.x,y:players[id].position.y)
        return ShotAssist.target(from:origin,facing:players[id].facing.vector,hoopIndex:players[id].attackHoop)
    }
    func execute(_ command:ActionCommand,player id:Int) {
        guard phase == .playing else { return }
        switch command.action {
        case .charge:
            if owner==id && [.idle,.catchBall].contains(players[id].action) { players[id].action = .charge;players[id].elapsed=0;players[id].chargeTime=0 }
        case .release:
            if owner==id && players[id].action == .charge {
                let approvedTick=max(tick-6,min(tick,command.tick))
                let marker=ShotGauge.marker(time:max(0,players[id].chargeTime-Double(tick-approvedTick)/60))
                launch(id,marker:marker,dunk:false)
            }
        case .jump:
            if players[id].air == nil && [.idle,.defense,.steal,.charge,.catchBall].contains(players[id].action) {
                players[id].takeoffFeet=ActionSystem.feet(players[id]);players[id].air=0;players[id].airDuration=0.9
                if owner != id && (players[id].input?.buttons ?? 0)&InputFrame.defend != 0 { players[id].action = .block;players[id].elapsed=0;players[id].contactUsed=false }
            }
        case .dunk:
            if owner==id && players[id].action == .idle && (aimed(id)?.distance ?? .infinity)<=220 { players[id].takeoffFeet=ActionSystem.feet(players[id]);players[id].action = .dunk;players[id].elapsed=0;players[id].air=0;players[id].airDuration=1.1 }
        case .defend:
            if owner != id && players[id].cooldown<=0 && [.idle,.defense,.steal].contains(players[id].action) {
                players[id].action=players[id].air == nil ? .steal : .block;players[id].elapsed=0;players[id].contactUsed=false;players[id].cooldown=0.7
            }
        }
    }
    func launch(_ id:Int,marker:Double,dunk:Bool) {
        let aim=aimed(id)
        if dunk && (aim?.distance ?? .infinity)>220 { players[id].action = .idle;emit("덩크 취소",player:id);return }
        let p=players[id],start=body.ground
        canScore=aim != nil && (dunk || ShotGauge.isGreen(marker:marker,width:ShotGauge.width(distance:aim!.distance)))
        let direction=aim.map { CGPoint(x:($0.end.x-start.x)/$0.distance,y:($0.end.y-start.y)/$0.distance) } ?? p.facing.vector
        var range=aim?.distance ?? 620
        if aim != nil && !canScore { range=max(20,range+(marker<0.5 ? -1 : 1)*max(65,range*CGFloat(abs(marker-0.5))*0.5)) }
        let end=CGPoint(x:start.x+direction.x*range,y:start.y+direction.y*range)
        points=CourtGeometry.shotPoints(feet:p.air != nil ? p.takeoffFeet ?? ActionSystem.feet(p) : ActionSystem.feet(p),hoopIndex:p.attackHoop)
        flight=ShotFlight(startGround:start,startHeight:body.height,endGround:end,distance:range,points:points,targetHeight:aim != nil ? Hoop.height : 0)
        owner=nil;shooter=id;lastTouch=id;pendingShot=true
        players[id].action = dunk ? .dunk : .shot;players[id].elapsed=dunk ? players[id].elapsed : 0.3
        emit(dunk ? "덩크" : canScore ? "초록 타이밍" : "타이밍 실패",player:id)
    }
    func goal(_ hoop:Int) {
        guard let shooter,canScore,hoop==players[shooter].attackHoop else {
            body.scoredHoop=nil;body.height=Hoop.height+Basketball.radius+3;body.velocity=CGPoint(x:hoop == 0 ? 180 : -180,y:0);body.verticalVelocity=240;flight=nil;pendingShot=false;return
        }
        canScore=false;pendingShot=false;players[shooter].score += points;owner=nil;flight=nil
        emit("득점",player:shooter,points:points)
        if overtime || remaining<=0 { finish();return }
        possession=1-shooter;phase = .restart;phaseTime=0
    }
    func finish() {
        if players[0].score==players[1].score { overtime=true;phase = .restart;phaseTime=0;possession=1-firstServe;emit("선득점 연장전") }
        else { phase = .finished;owner=nil;emit("경기 종료",player:players[0].score>players[1].score ? 0 : 1) }
    }
    func block(_ previous:LooseBall,_ next:LooseBall,oldHands:[[DefenseHand]],newHands:[[DefenseHand]])->Bool {
        guard let shooter else { return false };let id=1-shooter,p=players[id]
        guard p.action == .block,p.air != nil,p.jumpHeight>5,!p.contactUsed,
              DefensePhysics.inFront(ball:next.ground,defender:p.position,facing:p.facing.vector),
              DefensePhysics.contact(from:previous,to:next,hands:newHands[id],previousHands:oldHands[id]) != nil else { return false }
        body=DefensePhysics.deflected(next,defender:p.position,facing:p.facing.vector);flight=nil;canScore=false;pendingShot=false;lastTouch=id
        players[id].contactUsed=true;players[id].blocks += 1;players[id].cooldown=max(0.7,p.cooldown);emit("블로킹",player:id);return true
    }
    func step() {
        tick += 1
        guard phase != .lobby && phase != .paused && phase != .finished else { return }
        let dt=Self.step
        if phase == .countdown {
            phaseTime += dt
            if phaseTime>=3 { if resumeCountdown { phase=pausedFrom;phaseTime=pausedPhaseTime;resumeCountdown=false } else { arrange(firstServe);phase = .playing;phaseTime=0 };emit("시작") };return
        }
        if phase == .restart {
            phaseTime += dt
            if event.kind=="득점" && phaseTime<=0.3 { body.height=max(0,body.height-CGFloat(dt)*85) }
            else if phaseTime>0.3 { body.ground=CGPoint(x:836,y:570);body.height=0 }
            if phaseTime>=1 { arrange(possession);phase = .playing;phaseTime=0 };return
        }
        let oldHands=players.map(ActionSystem.hands),oldBody=body
        for id in 0..<2 {
            if tick-players[id].inputAt>18 { players[id].input=nil;if players[id].action == .charge { players[id].action = .idle } }
            while let command=players[id].queued.first,command.id==players[id].ackAction+1,command.tick<=tick {
                players[id].queued.removeFirst();players[id].ackAction=command.id;execute(command,player:id)
            }
            var p=players[id]
            p.cooldown=max(0,p.cooldown-dt);p.elapsed += dt
            if p.action == .charge { p.chargeTime += dt }
            if let air=p.air { p.air=air+dt;if p.air!>=p.airDuration { p.air=nil;p.takeoffFeet=nil } }
            if [.shot,.steal,.block,.catchBall].contains(p.action),p.elapsed>=p.actionDuration { p.action=(p.input?.buttons ?? 0)&InputFrame.defend != 0 && owner != id ? .defense : .idle;p.elapsed=0 }
            if p.action == .defense && (p.input?.buttons ?? 0)&InputFrame.defend == 0 { p.action = .idle;p.elapsed=0 }
            if [.defense,.steal,.block].contains(p.action),owner != id {
                let other=players[1-id].position;p.facing=Facing.closest(to:CGPoint(x:other.x-p.position.x,y:other.y-p.position.y),previous:p.facing)
            }
            let dx=CGFloat(p.input?.x ?? 0),dy=CGFloat(p.input?.y ?? 0),length=sqrt(dx*dx+dy*dy)
            p.moving=length>0 && phase == .playing
            if p.moving {
                if ![.defense,.steal,.block].contains(p.action) { p.facing=Facing.from(dx:dx,dy:dy) }
                let distance=p.speed*CGFloat(dt);p.position.x += dx/length*distance;p.position.y += dy/length*distance;p.gait += Double(distance)/105
            }
            if owner==id { p.dribble += dt }
            let progress=p.action == .defense ? 0.5 : p.action == .charge ? p.elapsed/2.16 : p.elapsed/p.actionDuration
            p.pose.approach(CharacterPose.target(action:p.poseAction,progress:progress,airProgress:p.air.map { $0/p.airDuration },walking:length>0,clock:p.gait),dt:dt)
            p.reach += (([.defense,.steal].contains(p.action) ? 1 : 0)-p.reach)*CGFloat(1-exp(-dt/0.055))
            ActionSystem.clamp(&p);players[id]=p
        }
        let dx=players[1].position.x-players[0].position.x,dy=(players[1].position.y-players[0].position.y)*Hoop.groundDepthScale,distance=sqrt(dx*dx+dy*dy)
        if distance<54 {
            let nx=distance>0.001 ? dx/distance : (priority == 0 ? 1.0 : -1.0),ny=distance>0.001 ? dy/distance : 0
            for id in 0..<2 { let sign:CGFloat=id == 0 ? -1 : 1;players[id].position.x += sign*nx*(54-distance)/2;players[id].position.y += sign*ny*(54-distance)/2/Hoop.groundDepthScale;ActionSystem.clamp(&players[id]) }
        }
        let newHands=players.map(ActionSystem.hands)
        if let owner {
            let target=ActionSystem.held(players[owner]),f=CGFloat(1-exp(-dt/0.04))
            body.ground.x += (target.ground.x-body.ground.x)*f;body.ground.y += (target.ground.y-body.ground.y)*f;body.height += (target.height-body.height)*f
            let defender=1-owner,p=players[defender]
            if p.action == .steal,p.elapsed>=0.10,p.elapsed<=0.27,!p.contactUsed,
               DefensePhysics.inFront(ball:body.ground,defender:p.position,facing:p.facing.vector),
               DefensePhysics.contact(from:oldBody,to:body,hands:newHands[defender],previousHands:oldHands[defender]) != nil {
                players[defender].contactUsed=true;players[defender].steals += 1;grant(defender,rebound:false);players[defender].action = .catchBall;emit("스틸",player:defender)
            } else if p.action == .block { /* Owned balls are never blocked. */ }
            if self.owner==owner && players[owner].action == .dunk && players[owner].elapsed>=0.605 { launch(owner,marker:0.5,dunk:true) }
        } else if var f=flight {
            let old=f.time;f.time += dt;var previous=f.sample(at:old);var interrupted=false
            for index in 1...8 {
                var next=f.sample(at:min(f.duration,old+dt*Double(index)/8))
                if block(previous,next,oldHands:oldHands,newHands:newHands) { interrupted=true;break }
                if next.collideWithHoops() { body=next;flight=nil;interrupted=true;break }
                if let hoop=ShotFlight.crossingHoop(from:previous,to:next) { body=next;goal(hoop);interrupted=true;break }
                previous=next
            }
            if !interrupted { body=previous;if f.time>=f.duration { flight=nil } else { flight=f } }
        } else {
            let previous=body;body.step(dt:dt)
            if block(previous,body,oldHands:oldHands,newHands:newHands) { }
            else if let hoop=body.scoredHoop { goal(hoop) }
            else if body.crossedBoundary { turnover(to:1-lastTouch,reason:"아웃 · 공격권 변경") }
            else if phase == .playing {
                let candidates=(0..<2).filter { id in
                    let p=players[id]
                    guard [.idle,.defense,.block].contains(p.action) else { return false }
                    if p.air==nil && body.height<35 { return hypot(p.position.x-body.ground.x,(p.position.y-body.ground.y)*Hoop.groundDepthScale)<60 }
                    return DefensePhysics.contact(from:previous,to:body,hands:newHands[id],previousHands:oldHands[id]) != nil
                }.sorted { a,b in
                    let da=hypot(players[a].position.x-body.ground.x,(players[a].position.y-body.ground.y)*Hoop.groundDepthScale),db=hypot(players[b].position.x-body.ground.x,(players[b].position.y-body.ground.y)*Hoop.groundDepthScale)
                    return abs(da-db)<0.001 ? a==priority : da<db
                }
                if let id=candidates.first { grant(id,rebound:true) }
            }
            if body.bounces>0 { pendingShot=false }
        }
        if phase == .playing {
            if !overtime { remaining=max(0,remaining-dt) }
            if !pendingShot { shotClock=max(0,shotClock-dt) }
            if remaining<=0 && !overtime { if owner==nil && shooter != nil && body.height>0 { phase = .endingShot } else { finish() } }
            else if shotClock<=0 && !pendingShot { turnover(to:1-possession,reason:"14초 위반") }
        } else if phase == .endingShot && flight==nil && (body.bounces>0 || body.height<=0) { finish() }
    }
    func snapshot()->MatchSnapshot { MatchSnapshot(epoch:inputEpoch,matchID:matchID,tick:tick,phase:phase,phaseTime:wireNumber(phaseTime),remaining:wireNumber(remaining),shotClock:wireNumber(shotClock),overtime:overtime,players:players.map(PlayerPacket.init),ball:BallPacket(owner:owner,shooter:shooter,ground:wirePoint(body.ground),height:CGFloat(wireNumber(Double(body.height)))),event:event) }
}
