import AppKit

final class CameraController {
    var center=CGPoint(x:836,y:470)
    var scale:CGFloat=0.7
    func update(snapshot:MatchSnapshot,local:Int,size:CGSize,dt:Double) {
        let p=snapshot.players[local],other=snapshot.players[1-local]
        let hoop=Hoop.all[(snapshot.ball.shooter ?? snapshot.ball.owner ?? local) == 0 ? 1 : 0]
        let points=[p.position,other.position,CGPoint(x:snapshot.ball.ground.x,y:snapshot.ball.ground.y-Basketball.radius-snapshot.ball.height),CGPoint(x:hoop.center.x,y:hoop.center.y-Hoop.height)]
        let minX=points.map(\.x).min()!-100,maxX=points.map(\.x).max()!+100
        let minY=min(p.position.y-250,points.map(\.y).min()!-80),maxY=points.map(\.y).max()!+80
        let desired=min(size.height*0.27/209,min(size.width/(maxX-minX),size.height/(maxY-minY)))
        let zoom=max(0.38,min(1.2,desired));scale += (zoom-scale)*CGFloat(1-exp(-dt/0.3))
        var target=CGPoint(x:(minX+maxX)/2,y:(minY+maxY)/2)
        let halfX=size.width/scale/2,halfY=size.height/scale/2
        target.x=max(min(halfX,836),min(max(1672-halfX,836),target.x));target.y=max(min(halfY,470.5),min(max(941-halfY,470.5),target.y))
        if hypot(target.x-center.x,target.y-center.y)*scale>10 { let blend=CGFloat(1-exp(-dt/0.18));center.x += (target.x-center.x)*blend;center.y += (target.y-center.y)*blend }
    }
}

final class LANMatchView:NSView {
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    let network:NetworkSession
    let assets:CourtView
    let camera=CameraController()
    var poses=[CharacterPose.target(action:"",progress:0,airProgress:nil,walking:false,clock:0),CharacterPose.target(action:"",progress:0,airProgress:nil,walking:false,clock:0)]
    var shown:MatchSnapshot?
    var predicted:CGPoint?
    var onMenuKey:((NSEvent)->Void)?
    var timer:Timer?
    var last=ProcessInfo.processInfo.systemUptime
    init(frame:NSRect,network:NetworkSession) {
        self.network=network;assets=CourtView(frame:.zero);assets.timer?.invalidate();super.init(frame:frame)
        timer=Timer(timeInterval:1/60,repeats:true) { [weak self] _ in self?.updateFrame() };RunLoop.main.add(timer!,forMode:.common)
    }
    required init?(coder:NSCoder) { fatalError() }
    deinit { timer?.invalidate() }
    func updateFrame() {
        let now=ProcessInfo.processInfo.systemUptime,dt=min(0.05,now-last);last=now
        guard var s=network.role == .host ? network.latest : network.snapshots.rendered(),let latest=network.latest else { needsDisplay=true;return }
        let local=network.localID
        if network.role == .client && latest.phase == .playing {
            var point=latest.players[local].position
            let state=latest.players[local]
            for f in network.input.history {
                let dx=CGFloat(f.x),dy=CGFloat(f.y),length=sqrt(dx*dx+dy*dy)
                let speed:CGFloat=[.defense,.steal].contains(state.action) ? 138 : state.action == .charge ? 105 : f.buttons&InputFrame.run != 0 ? 336 : 210
                if length>0 { point.x += dx/length*speed/60;point.y += dy/length*speed/60 }
                point.y=max(CourtBounds.top,min(CourtBounds.bottom,point.y));point.x=max(CourtBounds.inset(at:point.y)+20,min(1672-CourtBounds.inset(at:point.y)-20,point.x))
            }
            if let old=predicted,hypot(old.x-point.x,old.y-point.y)<100 { let f=CGFloat(1-exp(-dt/0.035));predicted=CGPoint(x:old.x+(point.x-old.x)*f,y:old.y+(point.y-old.y)*f) } else { predicted=point }
            s.players[local]=latest.players[local];s.players[local].position=predicted!
            s.players[local].moving=network.input.x != 0 || network.input.y != 0
            if network.input.x != 0 || network.input.y != 0,![.defense,.steal,.block].contains(s.players[local].action) { s.players[local].facing=Facing.from(dx:CGFloat(network.input.x),dy:CGFloat(network.input.y)) }
            if network.input.pending.contains(where:{$0.action == .charge}),s.ball.owner==local,s.players[local].action == .idle { s.players[local].action = .charge;s.players[local].elapsed=0.08 }
        } else { predicted=nil }
        for i in 0..<2 {
            let p=s.players[i].state
            let progress=p.action == .defense ? 0.5 : p.action == .charge ? p.elapsed/2.16 : p.elapsed/p.actionDuration
            poses[i].approach(CharacterPose.target(action:p.poseAction,progress:progress,airProgress:p.air.map{$0/p.airDuration},walking:p.moving,clock:p.gait),dt:dt)
        }
        shown=s;camera.update(snapshot:s,local:local,size:CGSize(width:bounds.width,height:max(100,bounds.height-104)),dt:dt);needsDisplay=true
    }
    override func keyDown(with e:NSEvent) {
        if [.paused,.finished].contains(network.latest?.phase ?? .lobby) { onMenuKey?(e);return }
        if e.keyCode==53 { network.pause();return }
        if [15,48,36].contains(e.keyCode) { return }
        if !e.isARepeat { network.input.key(e.keyCode,down:true,tick:network.estimatedTick+2);network.sendInputNow() }
    }
    override func keyUp(with e:NSEvent) { network.input.key(e.keyCode,down:false,tick:network.estimatedTick+2);network.sendInputNow() }
    override func flagsChanged(with e:NSEvent) { if e.modifierFlags.contains(.shift) { network.input.buttons |= InputFrame.run } else { network.input.buttons &= ~InputFrame.run };network.sendInputNow() }
    override func resignFirstResponder()->Bool { network.input.clear();network.sendInputNow();return true }
    func label(_ text:String,at point:CGPoint,size:CGFloat=16,color:NSColor = .white,width:CGFloat=1000) {
        text.draw(in:NSRect(x:point.x,y:point.y,width:width,height:size*2.6),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:color])
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.black.setFill();bounds.fill()
        guard let s=shown,let official=network.latest else { label("연결을 준비하는 중…",at:CGPoint(x:30,y:30));return }
        let local=network.localID,viewport=NSRect(x:0,y:0,width:bounds.width,height:bounds.height-104)
        NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:viewport).addClip()
        let transform=NSAffineTransform();transform.translateX(by:viewport.midX,yBy:viewport.midY);transform.scale(by:camera.scale);transform.translateX(by:-camera.center.x,yBy:-camera.center.y);transform.concat()
        assets.court.draw(in:NSRect(x:0,y:0,width:1672,height:941),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        NSColor(calibratedRed:1,green:0.82,blue:0.24,alpha:0.65).setStroke()
        for left in [true,false] { let points=CourtGeometry.threePointPolyline(left:left),path=NSBezierPath();path.move(to:points[0]);for point in points.dropFirst() { path.line(to:point) };path.lineWidth=2;path.setLineDash([7,7],count:2,phase:0);path.stroke() }
        if s.ball.owner==local {
            let p=s.players[local],hoopIndex=local == 0 ? 1 : 0
            let aim=ShotAssist.target(from:CGPoint(x:s.ball.ground.x,y:p.position.y),facing:p.facing.vector,hoopIndex:hoopIndex)
            let direction=aim.map { CGPoint(x:($0.end.x-s.ball.ground.x)/$0.distance,y:($0.end.y-p.position.y)/$0.distance) } ?? p.facing.vector
            (aim == nil ? NSColor.systemOrange : NSColor.systemGreen).setStroke();let path=NSBezierPath();path.lineWidth=3;path.move(to:p.position);path.line(to:CGPoint(x:p.position.x+direction.x*70,y:p.position.y+direction.y*70));path.stroke()
        }
        for i in [0,1].sorted(by:{s.players[$0].position.y<s.players[$1].position.y}) {
            let packet=s.players[i];var p=packet.state;p.pose=poses[i]
            let color=i==local ? NSColor.systemBlue : NSColor.systemRed
            let name=String(network.names[i].prefix(10))+(s.ball.owner==i ? " ●" : "")
            assets.drawCharacter(at:p.position,facing:p.facing,pose:p.pose,jump:p.jumpHeight,color:color,defending:p.reach,label:name)
        }
        let b=s.ball,screen=CGPoint(x:b.ground.x,y:b.ground.y-Basketball.radius-b.height)
        NSColor.black.withAlphaComponent(max(0.06,0.20-Double(b.height)/1600)).setFill();NSBezierPath(ovalIn:NSRect(x:b.ground.x-10,y:b.ground.y-3,width:20,height:6)).fill()
        NSColor(calibratedRed:0.95,green:0.49,blue:0.12,alpha:1).setFill();let circle=NSBezierPath(ovalIn:NSRect(x:screen.x-Basketball.radius,y:screen.y-Basketball.radius,width:Basketball.radius*2,height:Basketball.radius*2));circle.fill();NSColor.black.setStroke();circle.lineWidth=1.5;circle.stroke();let seam=NSBezierPath();seam.move(to:CGPoint(x:screen.x-Basketball.radius,y:screen.y));seam.line(to:CGPoint(x:screen.x+Basketball.radius,y:screen.y));seam.stroke()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.78).setFill();NSRect(x:12,y:12,width:bounds.width-24,height:62).fill()
        let time=official.overtime ? "연장 · 선득점" : String(format:"%d:%02d",Int(ceil(official.remaining))/60,Int(ceil(official.remaining))%60)
        label("나 \(official.players[local].score) : \(official.players[1-local].score) 상대    \(time)    공격 \(String(format:"%.1f",official.shotClock))초",at:CGPoint(x:26,y:20),size:bounds.width<950 ? 19 : 23,width:bounds.width-50)
        label("공격 방향 \(local==0 ? "오른쪽 →" : "← 왼쪽")    LAN \(Int(network.rttMS)) ms",at:CGPoint(x:26,y:49),size:13,color:.lightGray,width:bounds.width-50)
        let p=official.players[local]
        if p.action == .charge {
            let aim=ShotAssist.target(from:CGPoint(x:official.ball.ground.x,y:p.position.y),facing:p.facing.vector,hoopIndex:local == 0 ? 1 : 0)
            let distance=aim?.distance ?? CGFloat(hypot(Double(p.position.x-Hoop.all[local == 0 ? 1 : 0].center.x),Double(p.position.y-530)))
            let width=ShotGauge.width(distance:distance),marker=ShotGauge.marker(time:p.charge+max(0,Double(network.estimatedTick-official.tick)/60))
            let x=viewport.midX+(p.position.x-camera.center.x)*camera.scale
            let top=official.players.filter { abs($0.position.x-p.position.x)<250 }.map { $0.position.y-290-$0.state.jumpHeight }.min() ?? p.position.y-250-p.state.jumpHeight
            let y=viewport.midY+(top-camera.center.y)*camera.scale
            let rect=NSRect(x:max(8,min(bounds.width-218,x-105)),y:max(82,min(viewport.maxY-30,y)),width:210,height:15)
            NSColor.black.setFill();rect.insetBy(dx:-3,dy:-3).fill();NSGradient(colors:[.red,.orange,.yellow,.orange,.red])!.draw(in:rect,angle:0);NSColor.systemGreen.setFill();NSRect(x:rect.midX-rect.width*width/2,y:rect.minY,width:rect.width*width,height:rect.height).fill();NSColor.white.setFill();NSRect(x:rect.minX+rect.width*marker-1.5,y:rect.minY-3,width:3,height:21).fill()
        }
        NSColor(calibratedWhite:0.08,alpha:1).setFill();NSRect(x:0,y:viewport.maxY,width:bounds.width,height:104).fill()
        label("방향키 이동 · Shift 달리기 · X 누르고 놓기 슛 · Z 덩크\nSpace 점프 · C 스틸 / 블록 · Esc 일시정지",at:CGPoint(x:16,y:viewport.maxY+10),size:14,width:bounds.width-32)
        label("\(official.event.kind) · 스틸 \(p.steals) / 블록 \(p.blocks) / 리바운드 \(p.rebounds)",at:CGPoint(x:16,y:viewport.maxY+64),size:14,color:.lightGray,width:bounds.width-32)
        if [.countdown,.restart,.endingShot].contains(official.phase) {
            let title=official.phase == .countdown ? "\(max(1,Int(ceil(3-official.phaseTime))))" : official.phase == .restart ? "중앙 재개" : "마지막 슛 확인 중"
            label(title,at:CGPoint(x:bounds.midX-150,y:viewport.midY-40),size:42,width:350)
        }
    }
}

final class GameRootView:NSView,NSTextFieldDelegate {
    enum Screen { case home,lan,rooms,lobby,match,help }
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    let network=NetworkSession()
    var screen:Screen = .home
    var practice:CourtView?,match:LANMatchView?,stack:NSStackView?
    var buttons:[NSButton]=[],handlers:[()->Void]=[],selection=0
    var alias=UserDefaults.standard.string(forKey:"playerAlias") ?? "선수"
    var address="",room="농구 연습방",updateStatus="업데이트 확인 중…"
    var fieldAlias:NSTextField?,fieldAddress:NSTextField?,fieldRoom:NSTextField?
    var overlayKey=""
    override init(frame:NSRect) {
        super.init(frame:frame);network.onChange={ [weak self] in self?.networkChanged() }
        NotificationCenter.default.addObserver(self,selector:#selector(lostFocus),name:NSWindow.didResignKeyNotification,object:nil)
        showHome()
    }
    required init?(coder:NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc func lostFocus() { if screen == .match,network.latest?.phase == .playing { network.pause() } }
    override func draw(_ dirtyRect:NSRect) { NSColor(calibratedRed:0.06,green:0.08,blue:0.12,alpha:1).setFill();bounds.fill() }
    func clearMenu() { stack?.removeFromSuperview();stack=nil;buttons.removeAll();handlers.removeAll();selection=0;fieldAlias=nil;fieldAddress=nil;fieldRoom=nil }
    func menu(_ title:String,_ subtitle:String,overlay:Bool=false) {
        clearMenu()
        let s=NSStackView();s.orientation = .vertical;s.alignment = .centerX;s.spacing=12;s.translatesAutoresizingMaskIntoConstraints=false;stack=s;addSubview(s)
        NSLayoutConstraint.activate([s.centerXAnchor.constraint(equalTo:centerXAnchor),s.centerYAnchor.constraint(equalTo:centerYAnchor),s.widthAnchor.constraint(equalTo:widthAnchor,multiplier:0.88)])
        let heading=NSTextField(labelWithString:title);heading.font = .boldSystemFont(ofSize:28);heading.textColor = .white;s.addArrangedSubview(heading)
        let info=NSTextField(wrappingLabelWithString:subtitle);info.font = .systemFont(ofSize:14);info.textColor = .lightGray;info.alignment = .center;s.addArrangedSubview(info);info.widthAnchor.constraint(equalTo:s.widthAnchor).isActive=true
        if overlay { s.wantsLayer=true;s.layer?.backgroundColor=NSColor(calibratedWhite:0.05,alpha:0.95).cgColor;s.layer?.cornerRadius=14;s.edgeInsets=NSEdgeInsets(top:22,left:14,bottom:22,right:14) }
    }
    func field(_ value:String,placeholder:String,tag:Int)->NSTextField {
        let f=NSTextField(string:value);f.placeholderString=placeholder;f.tag=tag;f.delegate=self;f.font = .systemFont(ofSize:16);stack!.addArrangedSubview(f);f.widthAnchor.constraint(equalToConstant:320).isActive=true;return f
    }
    func controlTextDidChange(_ notification:Notification) {
        guard let f=notification.object as? NSTextField else { return }
        if f.tag==0 { alias=LANProtocol.name(f.stringValue);UserDefaults.standard.set(alias,forKey:"playerAlias") }
        if f.tag==1 { address=String(f.stringValue.prefix(80)) };if f.tag==2 { room=LANProtocol.name(f.stringValue) }
    }
    func button(_ title:String,_ handler:@escaping ()->Void) {
        let b=NSButton(title:title,target:self,action:#selector(pressed));b.tag=handlers.count;b.bezelStyle = .rounded;b.font = .systemFont(ofSize:16);stack!.addArrangedSubview(b);b.widthAnchor.constraint(equalToConstant:360).isActive=true;b.heightAnchor.constraint(equalToConstant:34).isActive=true;buttons.append(b);handlers.append(handler)
    }
    @objc func pressed(_ sender:NSButton) { guard handlers.indices.contains(sender.tag) else { return };handlers[sender.tag]() }
    func focusMenu() { highlight();window?.makeFirstResponder(self) }
    func highlight() { for (i,b) in buttons.enumerated() { b.bezelColor=i==selection ? .systemBlue : nil };needsDisplay=true }
    func showHome() {
        screen = .home;network.stop();practice?.timer?.invalidate();practice?.removeFromSuperview();practice=nil;match?.timer?.invalidate();match?.removeFromSuperview();match=nil;overlayKey=""
        menu("Full Court Stickman","같은 Wi-Fi의 맥북 두 대로 1대1 · LAN 테스트 버전\n\(updateStatus)")
        button("같은 Wi-Fi 대전") { [weak self] in self?.showLAN() }
        button("혼자 슛 연습") { [weak self] in self?.showPractice(defense:false) }
        button("혼자 수비 연습") { [weak self] in self?.showPractice(defense:true) }
        button("조작 안내") { [weak self] in self?.showHelp() };focusMenu()
    }
    func showLAN() {
        screen = .lan
        menu("같은 Wi-Fi 대전","로컬 네트워크 접근 요청을 허용해 주세요.\n같은 Wi-Fi라도 게스트망 격리·방화벽·서로 다른 서브넷에서는 연결되지 않을 수 있습니다.")
        fieldAlias=field(alias,placeholder:"내 별칭",tag:0);fieldRoom=field(room,placeholder:"방 이름",tag:2)
        button("방 만들기") { [weak self] in guard let self else { return };self.screen = .lobby;self.network.host(name:self.alias,room:self.room);self.showLobby() }
        button("방 찾기 / 주소로 참가") { [weak self] in guard let self else { return };self.screen = .rooms;self.network.browse();self.showRooms() }
        button("시작 메뉴") { [weak self] in self?.showHome() };focusMenu()
    }
    func showRooms() {
        screen = .rooms;menu("방 찾기",network.status)
        fieldAddress=field(address,placeholder:"방장의 IPv4:포트",tag:1)
        for room in network.rooms.prefix(4) { button("참가: \(room.name)") { [weak self] in guard let self else { return };self.screen = .lobby;self.network.join(room.endpoint,name:self.alias);self.showLobby() } }
        button("입력한 주소로 연결") { [weak self] in guard let self else { return };if self.network.direct(self.address,name:self.alias) { self.screen = .lobby;self.showLobby() } }
        button("뒤로") { [weak self] in self?.network.stop();self?.showLAN() };focusMenu()
    }
    func showLobby() {
        screen = .lobby
        let addresses=network.role == .host ? NetworkSession.addresses().prefix(3).map { "\($0):\(network.tcpPort ?? 0)" }.joined(separator:" / ") : ""
        let text="\(network.status)\n\(addresses)\n\(network.names[0]) [\(network.ready[0] ? "준비" : "대기")]   :   \(network.peerPresent ? network.names[1] : "참가자 없음") [\(network.ready[1] ? "준비" : "대기")]\nUDP \(network.udpReady ? "연결 완료" : "연결 대기") · 양쪽 앱/규칙 버전 일치 필요"
        menu(network.roomName,text)
        button(network.ready[network.localID] ? "준비 취소" : "준비") { [weak self] in self?.network.setReady() }
        if network.role == .host { button("경기 시작") { [weak self] in self?.network.startMatch() } }
        button("방 나가기") { [weak self] in self?.showHome() };focusMenu()
    }
    func showPractice(defense:Bool) {
        clearMenu();screen = .home
        let view=CourtView(frame:bounds);view.autoresizingMask=[.width,.height];view.defensePractice=defense;view.reset();view.updateStatus="Esc 시작 메뉴"
        view.exitToMenu={ [weak self] in self?.showHome() };practice=view;addSubview(view);window?.makeFirstResponder(view)
    }
    func showHelp() {
        screen = .help;menu("조작 안내","방향키 이동 · Shift 달리기 · X 누르고 놓기 슛\nSpace 점프 · Z 가까운 골대 덩크 · C 스틸/블록\n충전 중 Space로 점프슛 준비 · C→Space / Space→C 모두 블록\n대전 중 Esc: 전체 일시정지 요청 · 준비 후 방장이 재개\n방장: 오른쪽 공격 / 참가자: 왼쪽 공격\n3분 경기 · 14초 공격 제한 · 동점은 선득점 연장\n연습에서만 R 초기화 / Tab 모드 전환 · Command-Q 종료\n메뉴: ↑↓ 선택 / Return 실행 · Tab으로 입력칸 선택")
        button("시작 메뉴") { [weak self] in self?.showHome() };focusMenu()
    }
    func networkChanged() {
        if let phase=network.latest?.phase,network.role != .idle,phase != .lobby {
            if screen != .match {
                clearMenu();screen = .match;let view=LANMatchView(frame:bounds,network:network);view.autoresizingMask=[.width,.height];match=view;addSubview(view);view.onMenuKey={ [weak self] e in self?.keyDown(with:e) };window?.makeFirstResponder(view)
            }
            let key="\(phase.rawValue)\(network.ready)\(network.peerPresent)\(network.udpReady)"
            if overlayKey != key {
                overlayKey=key
                if phase == .paused { menu("일시정지",network.status,overlay:true);button(network.ready[network.localID] ? "준비 취소" : "재개 준비") { [weak self] in self?.network.setReady() };if network.role == .host { button("두 사람 준비 후 재개") { [weak self] in self?.network.startMatch() } };button("방 나가기") { [weak self] in self?.showHome() };highlight() }
                else if phase == .finished { let s=network.latest!,id=network.localID;menu(s.players[id].score>s.players[1-id].score ? "승리!" : "패배", "\(s.players[id].score) : \(s.players[1-id].score) · 스틸 \(s.players[id].steals) / 블록 \(s.players[id].blocks)\n두 사람이 재경기를 선택하면 첫 공격권을 바꿔 다시 시작합니다.",overlay:true);button(network.ready[id] ? "상대 재경기 선택 대기" : "재경기") { [weak self] in self?.network.rematch() };button("방 나가기") { [weak self] in self?.showHome() };highlight() }
                else { clearMenu();window?.makeFirstResponder(match) }
            }
        } else if screen == .lobby { showLobby() }
        else if screen == .rooms { showRooms() }
        else if screen == .match && network.role == .idle { showHome() }
        else if screen == .match && network.role == .host && network.latest?.phase == .lobby { match?.timer?.invalidate();match?.removeFromSuperview();match=nil;showLobby() }
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode==126 { selection=max(0,selection-1);highlight() }
        else if event.keyCode==125 { selection=min(buttons.count-1,selection+1);highlight() }
        else if event.keyCode==36 || event.keyCode==76 { if handlers.indices.contains(selection) { handlers[selection]() } }
        else if event.keyCode==53 && screen != .match { showHome() }
        else if event.keyCode==48 { if let field=fieldAlias ?? fieldAddress { window?.makeFirstResponder(field) } else { selection=(selection+1)%max(1,buttons.count);highlight() } }
        else { super.keyDown(with:event) }
    }
}
