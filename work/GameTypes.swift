import Foundation

enum ShotGauge {
    static func width(distance:CGFloat)->Double {
        if distance<=200 { return 0.32 }
        if distance<=450 { return 0.32-Double((distance-200)/250)*0.16 }
        if distance<=650 { return 0.16-Double((distance-450)/200)*0.10 }
        if distance<=750 { return 0.06-Double((distance-650)/100)*0.03 }
        if distance<=1000 { return 0.03-Double((distance-750)/250)*0.015 }
        return 0.015 // Do not shrink below one 60Hz timing step.
    }
    static func marker(time:Double)->Double {
        let phase=time.truncatingRemainder(dividingBy:2.2)/1.1
        return phase<=1 ? phase : 2-phase
    }
    static func isGreen(marker:Double,width:Double)->Bool {
        marker.isFinite && width.isFinite && width>=0 && width<=1 && marker>=0.5-width/2 && marker<=0.5+width/2
    }
}

enum JumpMotion {
    static let peak:CGFloat=58.5 // 30% higher; the 0.9-second jump is unchanged.
    static func height(progress t:Double)->CGFloat {
        CGFloat(t>0.2 && t<0.8 ? Double(peak)*sin(.pi*(t-0.2)/0.6) : 0)
    }
}

enum Facing:String,Codable,CaseIterable {
    case up,upRight,right,downRight,down,downLeft,left,upLeft
    static func from(dx:CGFloat,dy:CGFloat)->Facing {
        if dy<0 { return dx<0 ? .upLeft : dx>0 ? .upRight : .up }
        if dy>0 { return dx<0 ? .downLeft : dx>0 ? .downRight : .down }
        return dx<0 ? .left : .right
    }
    var head:String {
        switch self { case .up,.upLeft,.upRight:return "back"; case .left,.downLeft:return "left"; case .right,.downRight:return "right"; case .down:return "front" }
    }
    var bodyWidth:CGFloat { self == .left || self == .right ? 0.65 : self == .down ? 1 : 0.85 }
    var handSide:CGFloat { [.left,.downLeft,.upLeft].contains(self) ? -1 : 1 }
    var vector:CGPoint {
        let d:CGFloat=1/sqrt(2)
        switch self { case .up:return CGPoint(x:0,y:-1); case .upRight:return CGPoint(x:d,y:-d); case .right:return CGPoint(x:1,y:0); case .downRight:return CGPoint(x:d,y:d); case .down:return CGPoint(x:0,y:1); case .downLeft:return CGPoint(x:-d,y:d); case .left:return CGPoint(x:-1,y:0); case .upLeft:return CGPoint(x:-d,y:-d) }
    }
    static func closest(to vector:CGPoint,previous:Facing)->Facing {
        let length=sqrt(vector.x*vector.x+vector.y*vector.y)
        guard length>0.001 else { return previous }
        let v=CGPoint(x:vector.x/length,y:vector.y/length),old=previous.vector
        let difference=abs(atan2(Double(old.x*v.y-old.y*v.x),Double(old.x*v.x+old.y*v.y)))
        if difference<Double.pi/8+Double.pi/36 { return previous }
        return allCases.max { a,b in a.vector.x*v.x+a.vector.y*v.y<b.vector.x*v.x+b.vector.y*v.y }!
    }
}

enum GameAction:String,Codable { case idle,charge,shot,defense,steal,block,dunk,catchBall }
enum InputAction:String,Codable { case charge,release,jump,dunk,defend,block }
struct ActionCommand:Codable,Equatable {
    var id:Int; var tick:Int; var action:InputAction
    enum CodingKeys:String,CodingKey { case id="i",tick="t",action="a" }
}
struct InputFrame:Codable {
    var epoch:Int=0
    var matchID:String; var seq:Int; var tick:Int; var x:Int; var y:Int; var buttons:Int; var actions:[ActionCommand]
    static let run=1,shoot=2,defend=4
    enum CodingKeys:String,CodingKey { case epoch="z",matchID="m",seq="s",tick="t",x,y,buttons="b",actions="a" }
    var valid:Bool { seq>=0 && seq<Int.max/2 && tick>=0 && tick<Int.max/2 && (-1...1).contains(x) && (-1...1).contains(y) && buttons>=0 && buttons<=7 && actions.count<=12 && actions.allSatisfy { $0.id>0 && $0.id<Int.max/2 && $0.tick>=0 && $0.tick<Int.max/2 } }
}

final class InputController {
    var x=0,y=0,buttons=0,seq=0,nextAction=0
    var pending:[ActionCommand]=[]
    var history:[InputFrame]=[]
    var keys=Set<UInt16>()
    func key(_ code:UInt16,down:Bool,tick:Int) {
        let was=keys.contains(code)
        if down { keys.insert(code) } else { keys.remove(code) }
        x=(keys.contains(124) ? 1 : 0)-(keys.contains(123) ? 1 : 0)
        y=(keys.contains(125) ? 1 : 0)-(keys.contains(126) ? 1 : 0)
        buttons=(buttons & InputFrame.run) | (keys.contains(7) ? InputFrame.shoot : 0) | (keys.contains(8) ? InputFrame.defend : 0)
        var action:InputAction?
        if down && !was { action=[7:.charge,49:.jump,6:.dunk,8:.defend,9:.block][code] }
        if !down && was && code==7 { action = .release }
        if let action, pending.count<12 { nextAction += 1; pending.append(ActionCommand(id:nextAction,tick:tick,action:action)) }
    }
    func frame(matchID:String,tick:Int,epoch:Int=0)->InputFrame {
        seq += 1
        let f=InputFrame(epoch:epoch,matchID:matchID,seq:seq,tick:tick,x:x,y:y,buttons:buttons,actions:pending)
        history.append(f); if history.count>180 { history.removeFirst(history.count-180) }; return f
    }
    func acknowledge(seq:Int,action:Int) { pending.removeAll { $0.id<=action }; history.removeAll { $0.seq<=seq } }
    func clear() { keys.removeAll(); x=0; y=0; buttons=0 }
    func reset() { clear(); seq=0; nextAction=0; pending.removeAll(); history.removeAll() }
}
