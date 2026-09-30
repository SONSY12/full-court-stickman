import AppKit

struct Clip {
    var frames: [NSImage]
    var width: CGFloat
    var height: CGFloat
    var foot: CGFloat
}

final class CourtView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    let resources = Bundle.main.resourceURL!
    var court: NSImage!
    var clips: [String: Clip] = [:]
    var keys = Set<UInt16>()
    var player = CGPoint(x: 550, y: 530)
    var ball = CGPoint(x: 836, y: 570)
    var ownsBall = false
    var action = ""
    var elapsed: Double = 0
    var clock: Double = 0
    var score = 0
    var flight: (start: CGPoint, end: CGPoint, time: Double, made: Bool, points: Int)?
    var rebound: (start: CGPoint, end: CGPoint, time: Double)?
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
        timer = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { [weak self] _ in self?.tick() }
    }
    required init?(coder: NSCoder) { fatalError() }
    func load(_ name: String, _ file: String, _ w: Int, _ h: Int, _ foot: Int) {
        guard let image = NSImage(contentsOf: resources.appendingPathComponent(file)),
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
        case 49: if action.isEmpty { begin("jump") }
        case 7:
            if ownsBall && (action.isEmpty || action == "jump") {
                begin(action == "jump" ? "jumpShot" : "shot")
                message = "슛!"
            }
        case 6:
            if ownsBall && action.isEmpty {
                if player.x > 1350 || player.x < 320 { begin("dunk"); message = "덩크!" }
                else { message = "덩크는 골대 가까이에서 가능합니다" }
            }
        case 8:
            if action == "jump" { begin("block"); message = "점프 블로킹" }
            else if action.isEmpty { begin("defense"); message = "수비 자세" }
        case 15: reset()
        default: break
        }
    }
    override func keyUp(with event: NSEvent) { keys.remove(event.keyCode) }
    override func resignFirstResponder() -> Bool { keys.removeAll(); return true }
    func begin(_ name: String) { action=name; elapsed=0 }
    func reset() {
        player=CGPoint(x:550,y:530); ball=CGPoint(x:836,y:570)
        ownsBall=false; action=""; flight=nil; rebound=nil; score=0
        message="가운데 공에 가까이 가면 집습니다"
    }
    func duration(_ name: String) -> Double {
        switch name { case "jump": return 1.4; case "shot": return 1.8
        case "defense": return 1.6; default: return 2.16 }
    }
    func jumpHeight() -> CGFloat {
        guard ["jump","jumpShot","block","dunk"].contains(action) else { return 0 }
        let t=elapsed/duration(action)
        let amplitude: Double = action == "jump" || action == "dunk" ? 150 : 110
        return CGFloat(t > 0.2 && t < 0.8 ? amplitude*sin(.pi*(t-0.2)/0.6) : 0)*0.30
    }
    func tick() {
        clock += 1/60
        var dx: CGFloat=0, dy: CGFloat=0
        if keys.contains(123) { dx -= 1 }; if keys.contains(124) { dx += 1 }
        if keys.contains(126) { dy -= 1 }; if keys.contains(125) { dy += 1 }
        if dx != 0 || dy != 0 {
            let length=sqrt(dx*dx+dy*dy)
            player.x += dx/length*3.5; player.y += dy/length*3.5
        }
        player.y=max(390,min(855,player.y))
        let inset=180-(player.y-390)*0.30
        player.x=max(inset,min(world.width-inset,player.x))
        if !action.isEmpty {
            let previous=elapsed; elapsed += 1/60
            let release=duration(action)*(action == "shot" ? 0.4 : action == "dunk" ? 0.55 : 0.49)
            if ownsBall && ["shot","jumpShot","dunk"].contains(action) && previous < release && elapsed >= release {
                ownsBall=false
                let start=heldPosition()
                let target=CGPoint(x: player.x > world.width/2 ? 1537 : 130, y:305)
                let distance=hypot(player.x-target.x,player.y-530)
                let made=action == "dunk" || Double.random(in:0...1) < max(0.25,0.95-Double(distance)/1300)
                flight=(start,target,0,made,distance>600 ? 3 : 2)
            }
            if action == "defense" && keys.contains(8) && elapsed > 0.55 && elapsed < 1.2 { elapsed=0.8 }
            if elapsed >= duration(action) { action=""; elapsed=0 }
        }
        if var f=flight {
            f.time += 1/60
            let t=min(1,f.time/0.8)
            ball=CGPoint(x:f.start.x+(f.end.x-f.start.x)*t,
                         y:f.start.y+(f.end.y-f.start.y)*t-140*sin(.pi*t))
            if t>=1 {
                flight=nil
                if f.made {
                    score += f.points; ball=CGPoint(x:836,y:570)
                    message="골! 공이 가운데로 돌아왔습니다"
                } else {
                    rebound=(f.end,CGPoint(x:f.end.x > 800 ? 1300 : 370,y:580),0)
                    message="슛 실패 · 리바운드 공을 잡으세요"
                }
            } else { flight=f }
        } else if var r=rebound {
            r.time += 1/60
            let t=min(1,r.time/1.1)
            ball=CGPoint(x:r.start.x+(r.end.x-r.start.x)*t,y:r.start.y+(r.end.y-r.start.y)*t-70*sin(.pi*t))
            if t>=1 { rebound=nil } else { rebound=r }
        } else if !ownsBall && hypot(player.x-ball.x,player.y-ball.y)<70 && action.isEmpty {
            ownsBall=true; message="공 획득 · X 슛 / Space 점프 / Z 덩크"
        }
        needsDisplay=true
    }
    func heldPosition() -> CGPoint {
        func smooth(_ t: Double) -> Double { let v=max(0,min(1,t)); return v*v*(3-2*v) }
        if ["shot","jumpShot","dunk"].contains(action) {
            let t=elapsed/duration(action)
            let lift=smooth(t/0.32)*(1-smooth((t-0.64)/0.3))
            if action == "dunk" {
                let arm=smooth((t-0.12)/0.22)*(1-smooth((t-0.66)/0.25))
                let slam=smooth((t-0.43)/0.12)*(1-smooth((t-0.66)/0.25))
                return CGPoint(x:player.x+(99+43*arm+35*slam)*0.3,
                               y:player.y+(-266-389*arm+165*slam)*0.3-jumpHeight())
            }
            return CGPoint(x:player.x+(99-37*lift)*0.3,y:player.y+(-266-409*lift)*0.3-jumpHeight())
        }
        let bounce=action.isEmpty ? CGFloat(abs(sin(clock*5.2)))*65 : 65
        return CGPoint(x:player.x+31,y:player.y-8-bounce-jumpHeight())
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        let scale=min(bounds.width/world.width,bounds.height/world.height)
        let transform=NSAffineTransform()
        transform.translateX(by:(bounds.width-world.width*scale)/2,yBy:(bounds.height-world.height*scale)/2)
        transform.scale(by:scale); transform.concat()
        court.draw(in:NSRect(x:0,y:0,width:1672,height:941),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        NSColor.black.withAlphaComponent(0.2).setFill()
        NSBezierPath(ovalIn:NSRect(x:player.x-27,y:player.y-8,width:54,height:16)).fill()
        let moving=keys.contains(123)||keys.contains(124)||keys.contains(125)||keys.contains(126)
        let name=action.isEmpty ? (moving ? "walk" : "idle") : action
        if let clip=clips[name], !clip.frames.isEmpty {
            let index=action.isEmpty ? Int(clock*20)%clip.frames.count : min(clip.frames.count-1,Int(elapsed/duration(action)*Double(clip.frames.count)))
            let s:CGFloat=0.30
            clip.frames[index].draw(in:NSRect(x:player.x-clip.width*s/2,y:player.y-clip.foot*s,width:clip.width*s,height:clip.height*s),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
        let b=ownsBall ? heldPosition() : ball
        NSColor(calibratedRed:0.95,green:0.49,blue:0.12,alpha:1).setFill()
        let circle=NSBezierPath(ovalIn:NSRect(x:b.x-8,y:b.y-8,width:16,height:16)); circle.fill()
        NSColor.black.setStroke(); circle.lineWidth=1.5; circle.stroke()
        let seam=NSBezierPath(); seam.move(to:NSPoint(x:b.x-8,y:b.y)); seam.line(to:NSPoint(x:b.x+8,y:b.y)); seam.stroke()
        NSColor(calibratedWhite:0.10,alpha:1).setFill(); NSRect(x:0,y:941,width:1672,height:99).fill()
        let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:24,weight:.medium),.foregroundColor:NSColor.white]
        "방향키 이동   Space 점프   X 슛   Z 덩크   C 수비 / 공중 블로킹   R 초기화".draw(at:NSPoint(x:45,y:960),withAttributes:attrs)
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
        if CommandLine.arguments.contains("--self-test") {
            let view=CourtView(frame:NSRect(x:0,y:0,width:1200,height:747))
            view.timer?.invalidate()
            precondition(view.court != nil && view.clips.count == 9,"Missing assets")
            view.player=view.ball; view.tick()
            precondition(view.ownsBall,"Pickup failed")
            view.begin("jump"); view.elapsed=0.7
            precondition(view.jumpHeight()>40,"Jump failed")
            view.reset(); view.flight=(CGPoint(x:1300,y:300),CGPoint(x:1537,y:305),0.79,false,2)
            view.tick(); precondition(view.score==0 && view.rebound != nil,"Miss must rebound")
            for _ in 0..<70 { view.tick() }
            precondition(view.ball.x != 836,"Miss must not reset to center")
            view.reset(); view.flight=(CGPoint(x:1300,y:300),CGPoint(x:1537,y:305),0.79,true,2)
            view.tick(); precondition(view.score==2 && view.ball.x==836,"Score reset failed")
            view.begin("defense"); view.keys.insert(8); view.elapsed=0.7; view.tick()
            precondition(view.action=="defense" && view.elapsed==0.8,"Defense hold failed")
            print("PASS: assets, pickup, jump, miss rebound, score reset, defense hold")
            return
        }
        app.setActivationPolicy(.regular)
        let delegate=AppDelegate(); app.delegate=delegate; app.run()
    }
}
