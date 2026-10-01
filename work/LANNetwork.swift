import Foundation
import Network
import Darwin

enum LANProtocol {
    static let version=1,rules=2
    static let content="stickman-lan-1"
    static let service="_fullcourt._tcp"
    static let maxControl=8192,maxDatagram=1400
    static func name(_ text:String)->String { String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(20)) }
    static func diagnostic(_ error:NWError,operation:String)->String {
        if case .dns(let code)=error,code == -65570 { return "로컬 네트워크 접근이 거부됐습니다 · 시스템 설정에서 이 앱의 허용 여부를 확인하세요" }
        if case .posix(let code)=error,[.EPERM,.EACCES].contains(code) { return "네트워크 권한이 거부됐습니다 · 로컬 네트워크/방화벽 설정을 확인하세요" }
        return "\(operation) · 네트워크/방화벽을 확인하세요 (\(error))"
    }
}
enum ControlKind:String,Codable { case hello,welcome,lobby,ready,start,pause,rematch,leave,ping,pong,error,event }
struct LANControl:Codable {
    var kind:ControlKind
    var version:Int=LANProtocol.version
    var rules:Int=LANProtocol.rules
    var content:String=LANProtocol.content
    var identity:String?
    var playerID:Int?
    var token:String?
    var name:String?
    var port:UInt16?
    var names:[String]?
    var ready:[Bool]?
    var flag:Bool?
    var text:String?
    var stamp:Double?
    var snapshot:MatchSnapshot?
    var event:MatchEvent?
    var compatible:Bool { version==LANProtocol.version && rules==LANProtocol.rules && content==LANProtocol.content }
}
struct LANDatagram:Codable {
    var v:Int=LANProtocol.version
    var token:String
    var kind:String
    var input:InputFrame?
    var snapshot:MatchSnapshot?
    var stamp:Double?
    enum CodingKeys:String,CodingKey { case v,token="k",kind="t",input="i",snapshot="s",stamp="p" }
}

/// TCP framing/decoding lives on the network queue. Callbacks mutate state on main.
final class TCPWire {
    let connection:NWConnection
    let queue:DispatchQueue
    var onMessage:((LANControl)->Void)?
    var onClose:(()->Void)?
    var onReady:(()->Void)?
    var problem:String?
    private var buffer=Data(),ended=false,rateStart=ProcessInfo.processInfo.systemUptime,rateCount=0
    init(_ connection:NWConnection,queue:DispatchQueue) { self.connection=connection;self.queue=queue }
    func start() {
        connection.stateUpdateHandler={ [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:DispatchQueue.main.async { self.onReady?() };self.receive()
            case .failed(let error):DispatchQueue.main.async { self.problem=LANProtocol.diagnostic(error,operation:"연결 실패") };self.close()
            case .waiting(let error):DispatchQueue.main.async { self.problem=LANProtocol.diagnostic(error,operation:"연결 대기") }
            case .cancelled:self.close()
            default:break
            }
        }
        connection.start(queue:queue)
    }
    func send(_ message:LANControl) {
        guard let data=try? JSONEncoder().encode(message),data.count<=LANProtocol.maxControl else { return }
        let n=UInt32(data.count)
        var frame=Data([UInt8(n>>24),UInt8((n>>16)&255),UInt8((n>>8)&255),UInt8(n&255)]);frame.append(data)
        connection.send(content:frame,completion:.contentProcessed { [weak self] error in if error != nil { self?.close() } })
    }
    func receive() {
        connection.receive(minimumIncompleteLength:1,maximumLength:LANProtocol.maxControl) { [weak self] data,_,complete,error in
            guard let self,!self.ended else { return }
            if let data { self.buffer.append(data) }
            while self.buffer.count>=4 {
                let bytes=Array(self.buffer.prefix(4)),n=bytes.reduce(0) { $0*256+Int($1) }
                guard n>0,n<=LANProtocol.maxControl,self.buffer.count<=LANProtocol.maxControl*3 else { self.close();return }
                if self.buffer.count<4+n { break }
                let payload=Data(self.buffer.dropFirst(4).prefix(n));self.buffer.removeFirst(4+n)
                let now=ProcessInfo.processInfo.systemUptime
                if now-self.rateStart>1 { self.rateStart=now;self.rateCount=0 };self.rateCount += 1
                guard self.rateCount<=90,let message=try? JSONDecoder().decode(LANControl.self,from:payload) else { self.close();return }
                DispatchQueue.main.async { [weak self] in self?.onMessage?(message) }
            }
            if complete || error != nil { self.close() } else { self.receive() }
        }
    }
    func close() {
        queue.async { [weak self] in guard let self,!self.ended else { return };self.ended=true;self.connection.cancel();DispatchQueue.main.async { self.onClose?() } }
    }
}

struct LANRoom { var name:String;var endpoint:NWEndpoint }

final class SnapshotBuffer {
    var frames:[MatchSnapshot]=[]
    var receivedAt:Double=0
    var lastEvent=0
    @discardableResult func accept(_ s:MatchSnapshot)->Bool {
        guard s.valid else { return false }
        if let last=frames.last,s.matchID==last.matchID && (s.epoch<last.epoch || (s.epoch==last.epoch && s.tick<=last.tick)) { return false }
        if frames.last?.matchID != s.matchID || frames.last?.epoch != s.epoch { frames.removeAll();lastEvent=0 }
        frames.append(s);if frames.count>12 { frames.removeFirst(frames.count-12) };receivedAt=ProcessInfo.processInfo.systemUptime;lastEvent=max(lastEvent,s.event.id);return true
    }
    func rendered()->MatchSnapshot? {
        guard let last=frames.last else { return nil }
        let target=Double(last.tick)-5+min(2,(ProcessInfo.processInfo.systemUptime-receivedAt)*60)
        guard let a=frames.last(where:{ Double($0.tick)<=target }),let b=frames.first(where:{Double($0.tick)>=target}),b.tick>a.tick,a.phase==b.phase else { return last }
        let t=CGFloat((target-Double(a.tick))/Double(b.tick-a.tick));var out=b
        for i in 0..<2 { out.players[i].position=CGPoint(x:a.players[i].position.x+(b.players[i].position.x-a.players[i].position.x)*t,y:a.players[i].position.y+(b.players[i].position.y-a.players[i].position.y)*t) }
        if a.ball.owner==b.ball.owner { out.ball.ground=CGPoint(x:a.ball.ground.x+(b.ball.ground.x-a.ball.ground.x)*t,y:a.ball.ground.y+(b.ball.ground.y-a.ball.ground.y)*t);out.ball.height=a.ball.height+(b.ball.height-a.ball.height)*t }
        return out
    }
}

final class NetworkSession {
    enum Role { case idle,host,client }
    var role:Role = .idle
    var onChange:(()->Void)?
    var rooms:[LANRoom]=[]
    var status="같은 Wi-Fi에 연결하세요"
    var names=["방장","참가자"]
    var ready=[false,false]
    var localID:Int { role == .client ? 1 : 0 }
    var roomName="농구 연습방"
    var tcpPort:UInt16?
    var udpReady=false
    var peerPresent=false
    var rttMS:Double=0
    var game=GameSession()
    var snapshots=SnapshotBuffer()
    var input=InputController()
    var latest:MatchSnapshot? { role == .host ? game.snapshot() : snapshots.frames.last }
    var estimatedTick:Int { role == .host ? game.tick : (snapshots.frames.last?.tick ?? 0)+Int(min(0.25,ProcessInfo.processInfo.systemUptime-snapshots.receivedAt+rttMS/2000)*60) }
    var debugDropEvery=0
    var debugDelayMS=0,debugJitterMS=0
    private let queue=DispatchQueue(label:"fullcourt.lan.io")
    private var listener:NWListener?,udpListener:NWListener?,browser:NWBrowser?,wire:TCPWire?,pendingWire:TCPWire?,udp:NWConnection?
    private var candidates:[NWConnection]=[]
    private var udpPort:UInt16?
    private var token="",identity=UUID().uuidString,peerIdentity=""
    private var clientEndpoint:NWEndpoint?
    private var clientName="참가자"
    private var expectedMatch="",expectedEpoch=0
    private var lastPeer=ProcessInfo.processInfo.systemUptime,connectedAt=ProcessInfo.processInfo.systemUptime,lostAt:Double?
    private var timer:Timer?,lastStep=ProcessInfo.processInfo.systemUptime,accumulator:Double=0,lastPing:Double=0
    private var lastSentEvent=0,sentPackets=0,leaving=false,connecting=false,reconnectAt:Double=0
    init() {
        timer=Timer(timeInterval:1/60,repeats:true) { [weak self] _ in self?.pump() }
        RunLoop.main.add(timer!,forMode:.common)
    }
    deinit { timer?.invalidate() }
    func changed() { onChange?() }
    func stop() {
        leaving=true;wire?.send(LANControl(kind:.leave));wire?.onClose=nil;wire?.close();wire=nil
        pendingWire?.onClose=nil;pendingWire?.close();pendingWire=nil
        listener?.cancel();udpListener?.cancel();browser?.cancel();udp?.cancel();candidates.forEach { $0.cancel() };candidates.removeAll()
        listener=nil;udpListener=nil;browser=nil;udp=nil;role = .idle;peerPresent=false;udpReady=false;ready=[false,false];tcpPort=nil;udpPort=nil;token="";peerIdentity="";lostAt=nil;connecting=false;clientEndpoint=nil
        input.reset();snapshots=SnapshotBuffer();game=GameSession();expectedMatch="";expectedEpoch=0;changed()
    }
    static func addresses()->[String] {
        var first:UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first)==0,let first else { return [] };defer { freeifaddrs(first) }
        var pointer:UnsafeMutablePointer<ifaddrs>?=first,result:[String]=[]
        while let p=pointer {
            defer { pointer=p.pointee.ifa_next }
            guard let addr=p.pointee.ifa_addr,Int32(addr.pointee.sa_family)==AF_INET,(p.pointee.ifa_flags&UInt32(IFF_LOOPBACK))==0,(p.pointee.ifa_flags&UInt32(IFF_UP)) != 0 else { continue }
            var buffer=[CChar](repeating:0,count:Int(NI_MAXHOST))
            if getnameinfo(addr,socklen_t(addr.pointee.sa_len),&buffer,socklen_t(buffer.count),nil,0,NI_NUMERICHOST)==0 { result.append(String(cString:buffer)) }
        }
        return Array(Set(result)).sorted()
    }
    func browse() {
        stop();leaving=false;status="방 검색 중 · 로컬 네트워크 접근을 허용해 주세요"
        let b=NWBrowser(for:.bonjour(type:LANProtocol.service,domain:nil),using:.tcp);browser=b
        b.browseResultsChangedHandler={ [weak self,weak b] results,_ in DispatchQueue.main.async {
            guard let self,self.browser === b else { return };self.rooms=results.compactMap { result in
                if case let .service(name,_,_,_)=result.endpoint { return LANRoom(name:LANProtocol.name(name),endpoint:result.endpoint) };return nil
            }.sorted { $0.name<$1.name };self.status=self.rooms.isEmpty ? "방이 없습니다 · 방장을 실행하거나 주소로 연결하세요" : "방을 선택해 참가하세요";self.changed()
        } }
        b.stateUpdateHandler={ [weak self,weak b] state in
            switch state { case .failed(let error),.waiting(let error):DispatchQueue.main.async { guard let self,self.browser === b else { return };self.status=LANProtocol.diagnostic(error,operation:"방 검색 실패/대기");self.changed() };default:break }
        }
        b.start(queue:queue);changed()
    }
    func host(name:String,room:String,advertise:Bool=true) {
        stop();leaving=false;role = .host;names[0]=LANProtocol.name(name);roomName=LANProtocol.name(room);status="방을 만드는 중…"
        do {
            let u=try NWListener(using:.udp,on:.any);udpListener=u
            u.newConnectionHandler={ [weak self,weak u] connection in DispatchQueue.main.async { guard let self,self.udpListener === u else { connection.cancel();return };self.acceptUDP(connection) } }
            u.stateUpdateHandler={ [weak self,weak u] state in DispatchQueue.main.async {
                guard let self,let u,self.udpListener === u,self.role == .host else { return }
                if case .ready=state { self.udpPort=u.port?.rawValue;self.startTCP(advertise:advertise) }
                if case .failed(let error)=state { self.status="UDP 준비 실패 · 네트워크 권한을 확인하세요 (\(error))";self.changed() }
            } };u.start(queue:queue)
        } catch { status="방 생성 실패: \(error)";changed() }
    }
    private func startTCP(advertise:Bool) {
        do {
            let l=try NWListener(using:.tcp,on:.any);listener=l
            if advertise { l.service=NWListener.Service(name:roomName,type:LANProtocol.service) }
            l.newConnectionHandler={ [weak self,weak l] c in DispatchQueue.main.async { guard let self,self.listener === l else { c.cancel();return };self.acceptTCP(c) } }
            l.stateUpdateHandler={ [weak self,weak l] state in DispatchQueue.main.async {
                guard let self,let l,self.listener === l,self.role == .host else { return }
                if case .ready=state { self.tcpPort=l.port?.rawValue;self.status="방 생성 완료 · 상대의 참가를 기다립니다";self.changed() }
                if case .failed(let error)=state { self.status="방 생성 실패 · 권한/방화벽을 확인하세요 (\(error))";self.changed() }
            } };l.start(queue:queue)
        } catch { status="TCP 준비 실패: \(error)";changed() }
    }
    func join(_ endpoint:NWEndpoint,name:String) {
        stop();leaving=false;role = .client;clientEndpoint=endpoint;clientName=LANProtocol.name(name);status="방에 연결 중…";connectClient();changed()
    }
    func direct(_ address:String,name:String)->Bool {
        let parts=address.split(separator:":")
        guard parts.count==2,let p=UInt16(parts[1]),p>0,!parts[0].isEmpty else { status="주소는 IPv4:포트 형식으로 입력하세요";changed();return false }
        join(.hostPort(host:NWEndpoint.Host(String(parts[0])),port:NWEndpoint.Port(rawValue:p)!),name:name);return true
    }
    private func connectClient() {
        guard role == .client,!connecting,let endpoint=clientEndpoint else { return };connecting=true;connectedAt=ProcessInfo.processInfo.systemUptime
        let connection=NWConnection(to:endpoint,using:.tcp),w=TCPWire(connection,queue:queue);wire=w
        w.onReady={ [weak self,weak w] in guard let self else { return };var hello=LANControl(kind:.hello);hello.identity=self.identity;hello.playerID=1;hello.name=self.clientName;hello.token=self.token;w?.send(hello) }
        w.onMessage={ [weak self] message in self?.clientControl(message) }
        w.onClose={ [weak self,weak w] in guard let self,self.wire === w,!self.leaving else { return };self.wire=nil;self.connecting=false;self.connectionLost();if let problem=w?.problem { self.status=problem;self.changed() } }
        w.start()
    }
    private func acceptTCP(_ connection:NWConnection) {
        let w=TCPWire(connection,queue:queue)
        if wire != nil || pendingWire != nil { w.onReady={ [weak w] in var error=LANControl(kind:.error);error.text="이미 두 명이 참가한 방입니다";w?.send(error) };w.start();DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { w.close() };return }
        pendingWire=w
        w.onMessage={ [weak self,weak w] message in
            guard let self,let w else { return }
            if self.wire === w { self.hostControl(message);return }
            guard self.pendingWire === w,message.kind == .hello else { w.close();return }
            guard message.compatible else { var error=LANControl(kind:.error);error.text="앱/경기 규칙 버전이 다릅니다. 같은 테스트 빌드를 설치하세요";w.send(error);DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { w.close() };return }
            guard message.playerID==1,let id=message.identity,UUID(uuidString:id) != nil,self.peerIdentity.isEmpty || (id==self.peerIdentity && message.token==self.token) else { var error=LANControl(kind:.error);error.text="기존 참가자의 재연결을 기다리는 방입니다";w.send(error);DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { w.close() };return }
            self.pendingWire=nil;self.wire=w;self.peerIdentity=id;self.peerPresent=true;self.names[1]=LANProtocol.name(message.name ?? "참가자")
            self.game.resetInputEpoch();self.input.reset()
            self.token=UUID().uuidString
            self.lastPeer=ProcessInfo.processInfo.systemUptime;self.ready=[false,false]
            var reply=LANControl(kind:.welcome);reply.playerID=1;reply.token=self.token;reply.port=self.udpPort;reply.names=self.names;reply.text=self.roomName;reply.snapshot=self.game.snapshot();w.send(reply);self.sendLobby();self.changed()
        }
        w.onClose={ [weak self,weak w] in guard let self else { return };if self.pendingWire === w { self.pendingWire=nil };if self.wire === w { self.wire=nil;self.connectionLost() } }
        w.start();DispatchQueue.main.asyncAfter(deadline:.now()+5) { [weak self,weak w] in if self?.pendingWire === w { w?.close() } }
    }
    private func acceptUDP(_ c:NWConnection) {
        guard candidates.count<4 else { c.cancel();return };candidates.append(c)
        c.start(queue:queue);receiveUDP(c)
        DispatchQueue.main.asyncAfter(deadline:.now()+3) { [weak self,weak c] in guard let self,let c,self.udp !== c else { return };c.cancel();self.candidates.removeAll { $0 === c } }
    }
    private func receiveUDP(_ c:NWConnection) {
        c.receiveMessage { [weak self,weak c] data,_,_,error in
            guard let self,let c else { return }
            if let data,data.count<=LANProtocol.maxDatagram,let packet=try? JSONDecoder().decode(LANDatagram.self,from:data) {
                DispatchQueue.main.async { self.datagram(packet,from:c) }
            }
            if error==nil { self.receiveUDP(c) }
        }
    }
    private func datagram(_ p:LANDatagram,from c:NWConnection) {
        guard p.v==LANProtocol.version,!token.isEmpty,p.token==token,wire != nil else { return }
        if role == .host {
            if udp == nil { guard p.kind=="probe" else { return };udp=c;udpReady=true;candidates.removeAll { $0 === c };sendUDP(LANDatagram(token:token,kind:"probe"));status="UDP 연결 완료 · 양쪽 준비 후 방장이 시작하세요";sendLobby();changed() }
            guard udp === c else { return }
            lastPeer=ProcessInfo.processInfo.systemUptime
            if p.kind=="probe" { lostAt=nil;sendUDP(LANDatagram(token:token,kind:"probe"));return }
            if p.kind=="ping" { sendUDP(LANDatagram(token:token,kind:"pong",stamp:p.stamp));return }
            if p.kind=="pong",let stamp=p.stamp { rttMS=max(0,(ProcessInfo.processInfo.systemUptime-stamp)*1000);return }
            if let frame=p.input,p.kind=="input" { game.ingest(frame,player:1) }
        } else if role == .client,udp === c {
            lastPeer=ProcessInfo.processInfo.systemUptime
            if p.kind=="ping" { sendUDP(LANDatagram(token:token,kind:"pong",stamp:p.stamp));return }
            if p.kind=="pong",let stamp=p.stamp { rttMS=max(0,(ProcessInfo.processInfo.systemUptime-stamp)*1000);return }
            if p.kind=="probe" { udpReady=true;connecting=false;lostAt=nil;status="연결 완료 · 준비를 선택하세요";changed() }
            if let s=p.snapshot,p.kind=="snapshot",s.matchID==expectedMatch,s.epoch==expectedEpoch,snapshots.accept(s) {
                input.acknowledge(seq:s.players[1].ackSeq,action:s.players[1].ackAction)
                changed()
            }
        }
    }
    private func sendUDP(_ packet:LANDatagram) {
        guard let udp,let data=try? JSONEncoder().encode(packet),data.count<=LANProtocol.maxDatagram else { return }
        sentPackets += 1;if debugDropEvery>0 && sentPackets%debugDropEvery==0 { return }
        let jitter=debugJitterMS>0 ? Int.random(in:0...debugJitterMS) : 0
        if debugDelayMS+jitter>0 { queue.asyncAfter(deadline:.now()+Double(debugDelayMS+jitter)/1000) { udp.send(content:data,completion:.contentProcessed { _ in }) } }
        else { udp.send(content:data,completion:.contentProcessed { _ in }) }
    }
    private func clientControl(_ message:LANControl) {
        guard message.compatible else { status="앱/경기 규칙 버전 불일치";wire?.onClose=nil;wire?.close();wire=nil;connecting=false;clientEndpoint=nil;changed();return }
        switch message.kind {
        case .welcome:
            guard message.playerID==1,let token=message.token,UUID(uuidString:token) != nil,let port=message.port,port>0,let snapshot=message.snapshot,snapshot.valid else { return }
            self.token=token;peerPresent=true;names=message.names?.count==2 ? message.names! : names;snapshots.accept(snapshot);input.reset();ready=[false,false]
            expectedMatch=snapshot.matchID;expectedEpoch=snapshot.epoch
            roomName=LANProtocol.name(message.text ?? "농구 대전방")
            udp?.cancel()
            let host:NWEndpoint.Host
            if case let .hostPort(h,_)=wire!.connection.currentPath?.remoteEndpoint { host=h }
            else { status="UDP 주소를 얻지 못했습니다. IPv4 주소로 직접 연결해 주세요";changed();return }
            let c=NWConnection(host:host,port:NWEndpoint.Port(rawValue:port)!,using:.udp);udp=c
            c.stateUpdateHandler={ [weak self,weak c] state in if case .ready=state { DispatchQueue.main.async { guard let self,let c,self.udp === c else { return };self.receiveUDP(c);self.sendUDP(LANDatagram(token:self.token,kind:"probe")) } } }
            c.start(queue:queue);lastPeer=ProcessInfo.processInfo.systemUptime
        case .lobby:if let r=message.ready,r.count==2 { ready=r };if let n=message.names,n.count==2 { names=n.map(LANProtocol.name) };changed()
        case .start:
            guard let s=message.snapshot,s.valid else { return };input.reset();snapshots=SnapshotBuffer();snapshots.accept(s);status="경기 시작 · 나는 왼쪽 골대로 공격";changed()
            expectedMatch=s.matchID;expectedEpoch=s.epoch
        case .pause:input.clear();ready=[false,false];if let s=message.snapshot { snapshots.accept(s) };status="일시정지 · 두 사람 준비 후 방장이 재개";changed()
        case .leave:stop();status="상대가 나갔습니다 · 경기 종료";changed()
        case .error:status=String((message.text ?? "연결 실패").prefix(160));wire?.onClose=nil;wire?.close();wire=nil;udp?.cancel();udp=nil;udpReady=false;connecting=false;clientEndpoint=nil;changed()
        case .ping:var pong=LANControl(kind:.pong);pong.stamp=message.stamp;wire?.send(pong)
        case .pong:if !udpReady,let stamp=message.stamp { rttMS=max(0,(ProcessInfo.processInfo.systemUptime-stamp)*1000) }
        default:break
        }
    }
    private func hostControl(_ message:LANControl) {
        guard message.compatible else { return }
        switch message.kind {
        case .ready:ready[1]=message.flag ?? false;sendLobby();changed()
        case .rematch:if game.phase == .finished { ready[1]=true;sendLobby();if ready[0] { startMatch() } }
        case .pause:pause()
        case .leave:releasePeer()
        case .ping:var pong=LANControl(kind:.pong);pong.stamp=message.stamp;wire?.send(pong)
        case .pong:if !udpReady,let stamp=message.stamp { rttMS=max(0,(ProcessInfo.processInfo.systemUptime-stamp)*1000) }
        default:break
        }
    }
    private func sendLobby() { var m=LANControl(kind:.lobby);m.names=names;m.ready=ready;wire?.send(m) }
    func setReady() { ready[localID].toggle();if role == .host { sendLobby() } else { var m=LANControl(kind:.ready);m.flag=ready[1];wire?.send(m) };changed() }
    func startMatch() {
        guard role == .host,wire != nil,udpReady,ready.allSatisfy({$0}) else { status="두 사람 준비와 UDP 연결 완료 후 시작할 수 있습니다";changed();return }
        if game.phase == .paused { game.resume() }
        else { let first=game.phase == .finished ? 1-game.firstServe : 0;game.begin(firstServe:first) }
        input.reset();ready=[false,false];lastSentEvent=game.event.id
        var m=LANControl(kind:.start);m.snapshot=game.snapshot();wire?.send(m);sendLobby();status="나는 오른쪽 골대로 공격";changed()
    }
    func rematch() { guard latest?.phase == .finished else { return };ready[localID]=true;if role == .host { sendLobby();if ready[1] { startMatch() } } else { wire?.send(LANControl(kind:.rematch)) };changed() }
    func pause() {
        input.clear()
        if role == .host { game.pause();ready=[false,false];var m=LANControl(kind:.pause);m.snapshot=game.snapshot();wire?.send(m);sendLobby();status="일시정지 · 두 사람 준비 후 재개" }
        else if role == .client { wire?.send(LANControl(kind:.pause));status="일시정지 승인 대기…" }
        changed()
    }
    func sendInputNow() {
        guard let state=latest,udpReady else { return }
        if let last=input.history.last,last.matchID != state.matchID || last.epoch != state.epoch { input.reset() }
        let f=input.frame(matchID:state.matchID,tick:estimatedTick+2,epoch:state.epoch)
        if role == .host { game.ingest(f,player:0) } else { sendUDP(LANDatagram(token:token,kind:"input",input:f)) }
    }
    private func connectionLost() {
        guard role != .idle,!leaving else { return }
        input.clear();udp?.cancel();udp=nil;udpReady=false;ready=[false,false]
        if role == .host { game.pause() }
        if lostAt==nil { lostAt=ProcessInfo.processInfo.systemUptime };reconnectAt=ProcessInfo.processInfo.systemUptime+1
        status="연결 끊김 · 최대 10초 재연결 대기";changed()
    }
    private func releasePeer() {
        wire?.onClose=nil;wire?.close();wire=nil;udp?.cancel();udp=nil;peerIdentity="";token="";peerPresent=false;udpReady=false;ready=[false,false];lostAt=nil;game=GameSession();input.reset();status="상대가 나갔습니다 · 새 참가자를 기다립니다";changed()
    }
    private func pump() {
        let now=ProcessInfo.processInfo.systemUptime,delta=min(0.1,now-lastStep);lastStep=now
        guard role != .idle else { return }
        if let lostAt,now-lostAt>=10 {
            if role == .host { releasePeer();status="재연결 시간 초과 · 경기 종료" }
            else { stop();status="재연결 시간 초과 · 방장 종료/네트워크를 확인하세요" };changed();return
        }
        if role == .client,wire==nil,!connecting,clientEndpoint != nil,now>=reconnectAt { connectClient() }
        if connecting && now-connectedAt>8 { wire?.close();connecting=false;status="연결 시간 초과 · 주소/방화벽/게스트 Wi-Fi 격리를 확인하세요";changed() }
        if role == .host && peerPresent && !udpReady && wire != nil && now-lastPeer>8 { wire?.close();status="UDP 연결 시간 초과 · 방화벽/네트워크 격리를 확인하세요";changed() }
        if udpReady && now-lastPeer>1 && lostAt==nil {
            if role == .host { game.pause();ready=[false,false];var m=LANControl(kind:.pause);m.snapshot=game.snapshot();wire?.send(m);status="통신 지연으로 경기 정지 · 준비 후 재개";lostAt=now;changed() }
            else { pause();lostAt=now }
        }
        if lostAt != nil && udpReady && now-lastPeer<0.5 { lostAt=nil;status="연결 회복 · 두 사람 준비 후 재개";changed() }
        accumulator += delta
        while accumulator>=GameSession.step {
            accumulator -= GameSession.step
            if udpReady { sendInputNow() }
            if role == .host {
                game.step();input.acknowledge(seq:game.players[0].ackSeq,action:game.players[0].ackAction)
                if udpReady && game.tick%2==0 { sendUDP(LANDatagram(token:token,kind:"snapshot",snapshot:game.snapshot())) }
                if game.event.id>lastSentEvent { lastSentEvent=game.event.id;var m=LANControl(kind:.event);m.event=game.event;wire?.send(m) }
            } else if !udpReady,udp != nil { sendUDP(LANDatagram(token:token,kind:"probe")) }
        }
        if now-lastPing>1 { lastPing=now;if udpReady { sendUDP(LANDatagram(token:token,kind:"ping",stamp:now)) } else { var ping=LANControl(kind:.ping);ping.stamp=now;wire?.send(ping) } }
    }
    func disconnectForTest() { wire?.close() }
}
