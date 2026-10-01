import AppKit

// Joint interpolation keeps the body continuous across action changes.
struct CharacterPose {
    var joints: [CGPoint]
    var headY: CGFloat
    static func smooth(_ t: Double) -> CGFloat {
        let v=max(0,min(1,t)); return CGFloat(v*v*(3-2*v))
    }
    static func target(action: String, progress t: Double, airProgress: Double?, walking: Bool, clock: Double) -> CharacterPose {
        let phase=clock*20/24*2 * Double.pi
        let bob:CGFloat=walking && action.isEmpty ? -3*abs(sin(phase)) : 0
        var crouch:CGFloat=0
        if let air=airProgress {
            if air<0.2 { crouch=22*sin(.pi*air/0.2) }
            if air>0.8 { crouch=12*sin(.pi*(air-0.8)/0.2) }
        }
        let recovery=smooth((t-0.64)/0.3)
        var lift:CGFloat=0
        if ["shot","jumpShot"].contains(action) { lift=smooth(t/0.32)*(1-recovery) }
        if action == "charge" { lift=smooth(t/0.32) }
        if action == "block" { lift=smooth(t/0.16)*(1-smooth((t-0.82)/0.16)) }
        if action == "dunk" { lift=smooth((t-0.12)/0.22)*(1-smooth((t-0.66)/0.25)) }
        let defense=action == "defense" ? smooth(t/0.2)*(1-smooth((t-0.72)/0.22)) : 0
        crouch += 12*defense
        let offset=crouch+bob
        func mix(_ a:CGFloat,_ b:CGFloat,_ f:CGFloat)->CGFloat { a+(b-a)*f }
        var le=CGPoint(x:198,y:388), lh=CGPoint(x:165,y:449)
        var re=CGPoint(x:314,y:388), rh=CGPoint(x:347,y:449)
        if action == "block" {
            le=CGPoint(x:mix(198,125,lift),y:mix(388,205,lift)); lh=CGPoint(x:mix(165,155,lift),y:mix(449,25,lift))
            re=CGPoint(x:mix(314,387,lift),y:mix(388,205,lift)); rh=CGPoint(x:mix(347,357,lift),y:mix(449,25,lift))
        } else if action == "dunk" {
            let slam=smooth((t-0.43)/0.12)*(1-smooth((t-0.66)/0.25))
            le.x -= 20*lift; lh.x -= 25*lift
            re=CGPoint(x:mix(314,356,lift),y:mix(388,220,lift))
            rh=CGPoint(x:mix(347,390,lift)+35*slam,y:mix(449,60,lift)+165*slam)
        } else {
            le=CGPoint(x:mix(198,142,lift)-62*defense,y:mix(388,260,lift)-52*defense)
            lh=CGPoint(x:mix(165,195,lift)-149*defense,y:mix(449,55,lift)-119*defense)
            re=CGPoint(x:mix(314,365,lift)+62*defense,y:mix(388,235,lift)-52*defense)
            // Lead hand reaches down toward the dribble; the other guards high.
            rh=CGPoint(x:mix(347,310,lift)+149*defense,y:mix(449,40,lift)+72*defense)
        }
        // All arm joints share the same body offset.
        le.y += offset; lh.y += offset; re.y += offset; rh.y += offset
        let stride:CGFloat=walking && action.isEmpty ? sin(phase)*34 : 0
        let leftLift:CGFloat=walking && action.isEmpty ? max(0,cos(phase))*18 : 0
        let rightLift:CGFloat=walking && action.isEmpty ? max(0,-cos(phase))*18 : 0
        return CharacterPose(joints:[CGPoint(x:256,y:292+offset),CGPoint(x:256,y:333+offset),CGPoint(x:256,y:494+offset),
            le,lh,re,rh,CGPoint(x:216+stride*0.4-crouch*0.5,y:591+offset*0.7),CGPoint(x:196+stride,y:691-leftLift),
            CGPoint(x:296-stride*0.4+crouch*0.5,y:591+offset*0.7),CGPoint(x:316-stride,y:691-rightLift)],headY:28+offset)
    }
    mutating func approach(_ target: CharacterPose, dt: Double) {
        let blend=CGFloat(1-exp(-dt/0.055))
        for i in joints.indices {
            let dx=(target.joints[i].x-joints[i].x)*blend
            let dy=(target.joints[i].y-joints[i].y)*blend
            let distance=hypot(dx,dy)
            // Leave room for the higher root jump without a visible hand snap.
            let fraction=distance>0 ? min(1,CGFloat(dt*1200)/distance) : 1
            joints[i].x += dx*fraction
            joints[i].y += dy*fraction
        }
        headY += (target.headY-headY)*blend
    }
}
