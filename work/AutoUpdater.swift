import AppKit

enum AutoUpdater {
    static func check(status: @escaping (String) -> Void) {
        let installed=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""
        if installed.contains("-beta") { status("LAN 베타 \(installed) · 실제 두 맥북 검증 필요");return }
        let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let brew else { status("자동 업데이트: Homebrew 설치가 필요합니다"); return }
        let url=URL(string:"https://api.github.com/repos/SONSY12/full-court-stickman/releases/latest")!
        var request=URLRequest(url:url,timeoutInterval:15)
        request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
        URLSession.shared.dataTask(with:request) { data,response,error in
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
                  let data, let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
                  let tag=json["tag_name"] as? String else {
                DispatchQueue.main.async { status("업데이트 확인 실패 · 플레이는 가능합니다") }; return
            }
            let latest=tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let current=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.1.0"
            guard latest.compare(current,options:.numeric) == .orderedDescending else {
                DispatchQueue.main.async { status("최신 버전 \(current)") }; return
            }
            DispatchQueue.main.async { status("새 버전 \(latest) 자동 설치 중…") }
            DispatchQueue.global(qos:.utility).async {
                // Only upgrade this app, using Homebrew's checksum-verified release archive.
                guard run(brew,["list","--cask","full-court-stickman"]) else {
                    DispatchQueue.main.async { status("자동 업데이트는 Homebrew로 설치한 앱에서 지원됩니다") }; return
                }
                let ok=run(brew,["update"]) && run(brew,["upgrade","--cask","sonsy12/bk/full-court-stickman"])
                DispatchQueue.main.async {
                    status(ok ? "업데이트 설치 완료 · 앱을 다시 열면 적용됩니다" : "업데이트 실패 · 기존 버전으로 플레이 가능합니다")
                }
            }
        }.resume()
    }
    private static func run(_ executable: String, _ arguments: [String]) -> Bool {
        let task=Process(); task.executableURL=URL(fileURLWithPath:executable); task.arguments=arguments
        var environment=ProcessInfo.processInfo.environment
        environment["PATH"]="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOMEBREW_NO_AUTO_UPDATE"]="1"
        task.environment=environment
        task.standardOutput=FileHandle.nullDevice; task.standardError=FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit(); return task.terminationStatus == 0 }
        catch { return false }
    }
}
