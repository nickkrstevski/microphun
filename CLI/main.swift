import AppKit
import CoreFoundation

func fail(_ message:String,code:Int32=1) -> Never {
    FileHandle.standardError.write(Data(("microphun: " + message + "\n").utf8))
    exit(code)
}
func availablePort(within seconds: TimeInterval) -> CFMessagePort? {
    let end = ProcessInfo.processInfo.systemUptime + seconds
    repeat {
        if let port = CFMessagePortCreateRemote(nil,microphunPort) { return port }
        Thread.sleep(forTimeInterval:0.05)
    } while ProcessInfo.processInfo.systemUptime < end
    return nil
}
var args=Array(CommandLine.arguments.dropFirst())
guard let command=args.first else { print(cliGuide); exit(0) }
if ["help","-h","--help"].contains(command) { print(cliGuide); exit(0) }
if command=="open" {
    guard args.count==1 else { fail("Use microphun open.") }
    guard let executable=Bundle.main.executableURL else { fail("Could not locate the bundled CLI.") }
    var app=executable.standardizedFileURL.resolvingSymlinksInPath()
    while app.pathExtension != "app" && app.path != "/" { app.deleteLastPathComponent() }
    guard app.pathExtension=="app",NSWorkspace.shared.open(app) else { fail("Open Microphun.app from Finder.") }
    guard availablePort(within:8) != nil else { fail("Microphun opened but its control port is unavailable.") }
    print("{\"opened\":true}"); exit(0)
}
if command=="import",args.count==2 {
    args[1]=URL(fileURLWithPath:(args[1] as NSString).expandingTildeInPath).standardizedFileURL.path
}
guard let port=availablePort(within:1) else { fail("Microphun is unavailable. Run microphun open first.") }
func request(_ arguments:[String]) -> Any {
    do {
        let data=try JSONSerialization.data(withJSONObject:arguments)
        var reply: Unmanaged<CFData>?
        let status=CFMessagePortSendRequest(port,1,data as CFData,2,8,CFRunLoopMode.defaultMode.rawValue,&reply)
        guard status==0,let value=reply?.takeRetainedValue(),
              let response=try JSONSerialization.jsonObject(with:value as Data) as? [String:Any] else { fail("The app did not respond (\(status)).") }
        guard response["ok"] as? Bool == true,let result=response["result"] else { fail(response["error"] as? String ?? "Command failed.") }
        return result
    } catch { fail(error.localizedDescription) }
}
var result=request(args)
if ["start","play","route","set"].contains(command), (result as? [String:Any])?["pending"] as? Bool == true {
    let deadline=Date().addingTimeInterval(60)
    repeat {
        Thread.sleep(forTimeInterval:0.15)
        result=request(["status"])
        guard let state=result as? [String:Any] else { fail("Invalid audio state.") }
        if state["pending"] as? Bool == false {
            guard state["live"] as? Bool == true, (state["message"] as? String ?? "").isEmpty else {
                fail((state["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Audio start cancelled.")
            }
            break
        }
        if Date()>=deadline { fail("Microphone permission is still pending. Check the app and run microphun status.",code:2) }
    } while true
}
do {
    let json=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
    print(String(decoding:json,as:UTF8.self))
} catch { fail(error.localizedDescription) }
