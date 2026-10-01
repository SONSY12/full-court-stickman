import Foundation

struct DefenseHand {
    var ground: CGPoint
    // Same height convention as LooseBall; the rendered ball adds its radius.
    var height: CGFloat
    var screen: CGPoint { CGPoint(x:ground.x,y:ground.y-Basketball.radius-height) }
}

enum DefensePhysics {
    static let contactRadius = Basketball.radius+6
    static let stealRadius = Basketball.radius+14
    static let blockRadius = Basketball.radius+20
    static let stealStart=0.06,stealEnd=0.36
    static let cooldown:Double = 0.7

    static func inFront(ball:CGPoint,defender:CGPoint,facing:CGPoint)->Bool {
        let dx=ball.x-defender.x, dy=ball.y-defender.y
        let distance=CGFloat(hypot(Double(dx),Double(dy)))
        return distance<1 || dx*facing.x+dy*facing.y >= -distance*0.15
    }

    // Sweep relative motion, so neither a fast shot nor a moving hand tunnels.
    static func contact(from:LooseBall,to:LooseBall,hands:[DefenseHand],previousHands:[DefenseHand]? = nil,radius:CGFloat=DefensePhysics.contactRadius)->Int? {
        for i in hands.indices {
            let old=(previousHands?.count == hands.count) ? previousHands![i] : hands[i]
            let a=[from.ground.x-old.ground.x,(from.ground.y-old.ground.y)*Hoop.groundDepthScale,from.height-old.height]
            let b=[to.ground.x-hands[i].ground.x,(to.ground.y-hands[i].ground.y)*Hoop.groundDepthScale,to.height-hands[i].height]
            let d=zip(a,b).map { $1-$0 }
            let length=d.reduce(CGFloat(0)) { $0+$1*$1 }
            let t=length>0 ? max(0,min(1,-zip(a,d).reduce(CGFloat(0)) { $0+$1.0*$1.1 }/length)) : 0
            let distance=zip(a,d).reduce(CGFloat(0)) { $0+pow($1.0+$1.1*t,2) }
            if distance<=radius*radius { return i }
        }
        return nil
    }

    static func deflected(_ ball:LooseBall,defender:CGPoint,facing:CGPoint)->LooseBall {
        var result=ball
        let dx=ball.ground.x-defender.x, dy=(ball.ground.y-defender.y)*Hoop.groundDepthScale
        let distance=CGFloat(hypot(Double(dx),Double(dy)))
        let nx=distance>1 ? dx/distance : facing.x
        let ny=distance>1 ? dy/distance : facing.y
        result.velocity=CGPoint(x:nx*300,y:ny*300/Hoop.groundDepthScale)
        result.verticalVelocity=min(-160,ball.verticalVelocity*0.4)
        result.scoredHoop=nil
        return result
    }
}

func runDefensePhysicsTests() {
    let hand=DefenseHand(ground:CGPoint(x:900,y:530),height:200)
    let a=LooseBall(ground:CGPoint(x:850,y:530),velocity:CGPoint(x:1400,y:0),height:200,verticalVelocity:100)
    var b=a; b.ground.x=950
    precondition(DefensePhysics.contact(from:a,to:b,hands:[hand])==0,"Fast shot tunneled through hand")
    var distant=a; distant.ground.y += 30; distant.height += 30
    var distantEnd=b; distantEnd.ground.y += 30; distantEnd.height += 30
    precondition(DefensePhysics.contact(from:distant,to:distantEnd,hands:[hand])==nil,"Screen overlap at another court depth must not block")
    var high=a; high.height=260
    var highEnd=b; highEnd.height=260
    precondition(DefensePhysics.contact(from:high,to:highEnd,hands:[hand])==nil,"Ball above reach must not block")
    let movingHand=DefenseHand(ground:CGPoint(x:960,y:530),height:200)
    let oldHand=DefenseHand(ground:CGPoint(x:840,y:530),height:200)
    let stationary=LooseBall(ground:CGPoint(x:900,y:530),velocity:.zero,height:200)
    precondition(DefensePhysics.contact(from:stationary,to:stationary,hands:[movingHand],previousHands:[oldHand])==0,"Moving hand tunneled through ball")
    precondition(!DefensePhysics.inFront(ball:CGPoint(x:800,y:530),defender:CGPoint(x:900,y:530),facing:CGPoint(x:1,y:0)),"Steal behind defender")
    let reflected=DefensePhysics.deflected(a,defender:CGPoint(x:900,y:530),facing:CGPoint(x:-1,y:0))
    precondition(reflected.velocity.x<0 && reflected.verticalVelocity<0 && reflected.scoredHoop==nil,"Blocked ball must travel away and fall")
}
