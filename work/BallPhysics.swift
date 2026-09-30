import Foundation

struct Hoop {
    var center: CGPoint
    var boardX: CGFloat
    static let all = [Hoop(center:CGPoint(x:130,y:530),boardX:78),Hoop(center:CGPoint(x:1537,y:530),boardX:1590)]
    static let height:CGFloat = 217
    static let radiusX:CGFloat = 37
    static let radiusY:CGFloat = 15
    func nearestRim(to point: CGPoint) -> CGPoint {
        var best = center
        var distance=CGFloat.greatestFiniteMagnitude
        for i in 0..<64 {
            let a=CGFloat(i)*2 * .pi/64, b=CGFloat(i+1)*2 * .pi/64
            let p=CGPoint(x:center.x+37*cos(a),y:center.y+15*sin(a))
            let q=CGPoint(x:center.x+37*cos(b),y:center.y+15*sin(b))
            let dx=q.x-p.x, dy=q.y-p.y
            let t=max(0,min(1,((point.x-p.x)*dx+(point.y-p.y)*dy)/(dx*dx+dy*dy)))
            let candidate=CGPoint(x:p.x+dx*t,y:p.y+dy*t)
            let d=hypot(point.x-candidate.x,point.y-candidate.y)
            if d<distance { distance=d; best=candidate }
        }
        return best
    }
}

struct LooseBall {
    var ground: CGPoint
    var velocity: CGPoint
    var height: CGFloat
    var verticalVelocity: CGFloat = -180
    var bounces = 0
    var rimHits = 0
    var boardHits = 0
    var settled: Bool { height==0 && verticalVelocity==0 && hypot(velocity.x,velocity.y)<8 }
    var screen: CGPoint { CGPoint(x:ground.x,y:ground.y-8-height) }

    mutating func contact(x:CGFloat,y:CGFloat,z:CGFloat,radius:CGFloat,restitution:CGFloat) -> Bool {
        let dx=ground.x-x,dy=ground.y-y,dz=height-z
        let distance=sqrt(dx*dx+dy*dy+dz*dz)
        guard distance<radius else { return false }
        let nx=distance>0.0001 ? dx/distance : (velocity.x>0 ? -1.0 : 1.0)
        let ny=distance>0.0001 ? dy/distance : 0
        let nz=distance>0.0001 ? dz/distance : 0
        ground.x=x+nx*(radius+0.01); ground.y=y+ny*(radius+0.01); height=z+nz*(radius+0.01)
        let incoming=velocity.x*nx+velocity.y*ny+verticalVelocity*nz
        guard incoming<0 else { return false }
        velocity.x -= (1+restitution)*incoming*nx
        velocity.y -= (1+restitution)*incoming*ny
        verticalVelocity -= (1+restitution)*incoming*nz
        return true
    }

    mutating func step(dt: Double) {
        // Adaptive substeps prevent a fast ball passing through the thin rim or board.
        let speed=sqrt(velocity.x*velocity.x+velocity.y*velocity.y+verticalVelocity*verticalVelocity)
        let count=max(1,Int(ceil(max(dt*240,dt*Double(speed)/3))))
        let delta=CGFloat(dt/Double(count))
        for _ in 0..<count {
            ground.x += velocity.x*delta; ground.y += velocity.y*delta
            if height>0 || verticalVelocity != 0 {
                height += verticalVelocity*delta-550*delta*delta
                verticalVelocity -= 1100*delta
            }
            collideWithHoops()
            if height<=0 {
                height=0
                if verticalVelocity<0 {
                    bounces += 1; verticalVelocity = -verticalVelocity*0.60
                    if verticalVelocity<65 { verticalVelocity=0 }
                }
            }
            if ground.y<390 { ground.y=390; velocity.y=abs(velocity.y)*0.6 }
            if ground.y>855 { ground.y=855; velocity.y = -abs(velocity.y)*0.6 }
            // Elevated balls can reach baskets that overhang the court boundary.
            let inset:CGFloat=height>145 ? 45 : 180-(ground.y-390)*0.30
            if ground.x<inset { ground.x=inset; velocity.x=abs(velocity.x)*0.6 }
            if ground.x>1672-inset { ground.x=1672-inset; velocity.x = -abs(velocity.x)*0.6 }
            let friction=exp(-(height==0 ? 4.0 : 0.7)*delta)
            velocity.x *= friction; velocity.y *= friction
            if settled { velocity = .zero }
        }
    }
    @discardableResult
    mutating func collideWithHoops() -> Bool {
        let previousHits=rimHits+boardHits
        for hoop in Hoop.all {
            let y=max(hoop.center.y-55,min(hoop.center.y+55,ground.y))
            let z=max(156,min(336,height))
            if contact(x:hoop.boardX,y:y,z:z,radius:9,restitution:0.72) { boardHits += 1 }
            let nearest=hoop.nearestRim(to:ground)
            if contact(x:nearest.x,y:nearest.y,z:Hoop.height,radius:11,restitution:0.66) { rimHits += 1 }
        }
        return rimHits+boardHits>previousHits
    }
}
