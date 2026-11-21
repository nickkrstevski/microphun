import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct Preset: Identifiable {
    var id: String { name }
    let name: String, icon: String
    let pitch: Double, reverb: Double, mode: Int, depth: Double
    static let modes = ["Off","Robot","Wobble","Bit crush","Houston radio","Ghost choir","Tape deck"]
    static let bank: [Preset] = [
        .init(name:"Houston radio",icon:"antenna.radiowaves.left.and.right",pitch:0,reverb:0,mode:4,depth:1),
        .init(name:"Ghost choir",icon:"person.3.fill",pitch:-3,reverb:0.54,mode:5,depth:1),
        .init(name:"Tape deck",icon:"hifispeaker.fill",pitch:-1,reverb:0.12,mode:6,depth:0.96),
        .init(name:"Clean",icon:"waveform",pitch:0,reverb:0,mode:0,depth:0),
        .init(name:"Helium",icon:"balloon.2.fill",pitch:8,reverb:0.05,mode:0,depth:0),
        .init(name:"Cave troll",icon:"mountain.2.fill",pitch:-7,reverb:0.58,mode:0,depth:0),
        .init(name:"Tin bot",icon:"cpu.fill",pitch:-2,reverb:0.10,mode:1,depth:0.83),
        .init(name:"Sea legs",icon:"water.waves",pitch:2,reverb:0.18,mode:2,depth:0.87),
        .init(name:"8-bit",icon:"gamecontroller.fill",pitch:3,reverb:0.02,mode:3,depth:0.92)
    ]
}
final class Studio: ObservableObject {
    let blackHoleLevel = BlackHoleLevel()
    @Published var holdSendLevel = true { didSet {
        defaults.set(holdSendLevel,forKey:"holdSendLevel")
        updateSendLevel()
    } }
    private func updateSendLevel() {
        let enabled = live && sending && holdSendLevel && send == BlackHoleLevel.uid
        let target = enabled ? sendChoices.first { $0.id == send }?.objectID : nil
        blackHoleLevel.hold(target)
    }
    private let engine = mic_create()!
    private let preview = mic_create()!
    private var heldAudio: NSData?, testAudio: NSData?
    private var startID = UUID()
    private var clock: Timer?, ticks = 0, testTicks = 0
    private let defaults = UserDefaults.standard
    private let clipsDir = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("Microphun/Clips")
    @Published var tab = 0
    @Published var notice = ""
    @Published var live = false { didSet { updateSendLevel() } }
    @Published var busy = false
    @Published var testing = false
    @Published var level: Float = 0
    @Published var currentPad = ""
    @Published var devices: [Device] = []
    @Published var pads: [Pad] = []
    @Published private(set) var routes = Routes()
    var input: String { get { routes.input } set { changeRoutes { $0.input = newValue } } }
    var send: String { get { routes.send } set { changeRoutes { $0.send = newValue } } }
    var monitor: String { get { routes.monitor } set { changeRoutes { $0.monitor = newValue } } }
    var sending: Bool { get { routes.sending } set { changeRoutes { $0.sending = newValue } } }
    var monitoring: Bool { get { routes.monitoring } set { changeRoutes { $0.monitoring = newValue } } }
    @Published var isolation = true { didSet {
        defaults.set(isolation,forKey:"isolation"); mic_isolate(engine,isolation ? 1 : 0)
    } }
    @Published var pitch = 0.0 { didSet { adjust() } }
    @Published var reverb = 0.0 { didSet { adjust() } }
    @Published var mode = 0 { didSet { adjust() } }
    @Published var depth = 0.7 { didSet { adjust() } }
    @Published var padGain = 0.75 { didSet { adjust() } }
    @Published var volume = 0.4 { didSet { adjust() } }
    var onAirChanged: ((Bool)->Void)?
    var inputChoices: [Device] { devices.filter { $0.inputs > 0 } }
    var sendChoices: [Device] { devices.filter { $0.id == Routes.micUID || ($0.isVirtual && $0.inputs > 0 && $0.outputs > 0) } }
    var monitorChoices: [Device] { devices.filter { $0.outputs > 0 && $0.id != Routes.sendUID } }
    var activePreset: String {
        Preset.bank.first { $0.pitch == pitch && abs($0.reverb-reverb)<0.001 && $0.mode == mode && (mode == 0 || abs($0.depth-depth)<0.001) }?.name ?? "Custom"
    }
    var routingLocked: Bool { busy }
    init() {
        holdSendLevel = defaults.object(forKey:"holdSendLevel") as? Bool ?? true
        devices = Device.list()
        let systemInput = Device.defaultUID(input:true), systemOutput = Device.defaultUID(input:false)
        routes.input = defaults.string(forKey:"input") ?? (inputChoices.first { $0.id == systemInput && !$0.isVirtual } ?? inputChoices.first { !$0.isVirtual })?.id ?? ""
        routes.monitor = defaults.string(forKey:"monitor") ?? (monitorChoices.first { $0.id == systemOutput && !$0.isVirtual } ?? monitorChoices.first { !$0.isVirtual })?.id ?? ""
        routes.send = defaults.string(forKey:"send") ?? sendChoices.first { $0.id == Routes.micUID }?.id ?? sendChoices.first { $0.name == "BlackHole 2ch" }?.id ?? ""
        routes.sending = defaults.object(forKey:"sending") as? Bool ?? true
        routes.monitoring = defaults.bool(forKey:"monitoring")
        if let knobs = defaults.array(forKey:"knobs") as? [Double], knobs.count == 6 {
            pitch = knobs[0]; reverb = knobs[1]; mode = Int(knobs[2]); depth = knobs[3]; padGain = knobs[4]; volume = knobs[5]
        }
        mic_monitor_voice(engine,monitoring ? 1 : 0)
        isolation = defaults.object(forKey:"isolation") as? Bool ?? true
        mic_isolate(engine,isolation ? 1 : 0)
        adjust()
        reloadPads()
        clock = Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in self?.tick() }
    }
    deinit { clock?.invalidate(); mic_destroy(engine); mic_destroy(preview) }
    func apply(_ p: Preset) { pitch = p.pitch; reverb = p.reverb; mode = p.mode; depth = p.depth }
    private func adjust() {
        mic_adjust(engine,Float(pitch),Float(reverb),Int32(mode),Float(depth),Float(padGain),Float(volume))
        mic_adjust(preview,0,0,0,0,1,Float(volume))
        defaults.set([pitch,reverb,Double(mode),depth,padGain,volume],forKey:"knobs")
    }
    func reloadPads() {
        let folder = Bundle.main.resourceURL!.appendingPathComponent("Sounds")
        let files = (try? FileManager.default.contentsOfDirectory(at:clipsDir,includingPropertiesForKeys:nil,options:.skipsHiddenFiles)) ?? []
        pads = Pad.bundled(folder) + files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.map { Pad(name:$0.deletingPathExtension().lastPathComponent,symbol:"waveform",url:$0) }
    }
    private func tick() {
        ticks += 1
        if live {
            level = mic_peak(engine)
            if !currentPad.isEmpty && mic_playing(engine) == 0 { currentPad = "" }
        }
        if testing {
            testTicks += 1
            if testTicks > 3 && (mic_playing(preview) == 0 || testTicks > 30) { endTest() }
        }
        if ticks % 20 == 0 {
            let list = Device.list()
            if list != devices { devices = list; updateSendLevel() }
            blackHoleLevel.check()
            if live, let error = routingError(routes) { stop(); notice = error }
            if live && mic_health(engine) != 0 { stop(); notice = "An audio device stopped. Check your routes and start again." }
        }
    }
    private func routingError(_ r: Routes) -> String? {
        let (sending,monitoring,input,send,monitor) = (r.sending,r.monitoring,r.input,r.send,r.monitor)
        if (sending || monitoring) && !input.isEmpty && !inputChoices.contains(where: { $0.id == input }) { return "Your input is disconnected. Choose another microphone in Routing." }
        if sending && !sendChoices.contains(where: { $0.id == send }) { return "Choose an available loopback device for calls in Routing." }
        if !monitorChoices.contains(where: { $0.id == monitor }) { return "Choose an available monitor output in Routing." }
        if sending && (input == send || send == monitor) { return "Choose different devices for the virtual microphone and your input or monitor." }
        if (sending || monitoring) && input == monitor && devices.first(where: { $0.id == input })?.isVirtual == true { return "Choose a different monitor to avoid a loop through your input." }
        return nil
    }
    private func commit(_ next: Routes) {
        routes = next
        defaults.set(next.input,forKey:"input")
        defaults.set(next.send,forKey:"send")
        defaults.set(next.monitor,forKey:"monitor")
        defaults.set(next.sending,forKey:"sending")
        defaults.set(next.monitoring,forKey:"monitoring")
        mic_monitor_voice(engine,next.monitoring ? 1 : 0)
        updateSendLevel()
    }

    func changeRoutes(_ edit: (inout Routes) -> Void) {
        guard !busy else { notice = "An audio change is already in progress."; return }
        let previous = routes
        var next = previous
        edit(&next)
        notice = ""
        guard next != previous else { return }
        if !live { commit(next); return }
        if let error = routingError(next) { notice = error; return }
        if previous.usesSameDevices(as:next) { commit(next); return }

        busy = true
        endTest()
        let id = UUID()
        startID = id
        let reconnect = { [weak self] in
            guard let self, self.startID == id else { return }
            defer { self.busy = false }
            let status = mic_reconnect(self.engine,next.capture,next.destination,next.monitor)
            if status == 0 { self.commit(next); return }
            let stage = String(cString:mic_failure_stage(self.engine)!)
            let rollback = mic_reconnect(self.engine,previous.capture,previous.destination,previous.monitor)
            if rollback == 0 {
                self.notice = "Couldn’t open the "+stage+" ("+String(status)+"). Your previous route is live."
            } else {
                self.stop()
                self.notice = "Both the new and previous routes failed. Choose an available device and start audio."
            }
        }
        if next.capture == nil || AVCaptureDevice.authorizationStatus(for:.audio) == .authorized {
            reconnect()
        } else {
            AVCaptureDevice.requestAccess(for:.audio) { [weak self] allowed in DispatchQueue.main.async {
                guard let self, self.startID == id else { return }
                if allowed { reconnect() }
                else { self.busy = false; self.notice = "Microphone access is required. Your previous route is live." }
            }}
        }
    }

    func start(then: (() -> Void)? = nil) {
        if live { then?(); return }
        guard !busy else { return }
        if let error = routingError(routes) { tab = 2; notice = error; return }
        let capture = (sending || monitoring) && !input.isEmpty
        endTest(); notice = ""; busy = true
        let requestID = UUID(); startID = requestID
        let begin = { [weak self] in
            guard let self, self.startID == requestID else { return }
            self.busy = false
            let status = mic_start(self.engine,capture ? self.input : nil,self.routes.destination,self.monitor)
            if status == 0 { self.live = true; self.onAirChanged?(true); then?() }
            else { self.tab = 2; self.notice = "Couldn’t open the \(String(cString:mic_failure_stage(self.engine)!)) (\(status)). Check your device selection." }
        }
        if !capture || AVCaptureDevice.authorizationStatus(for:.audio) == .authorized { begin(); return }
        AVCaptureDevice.requestAccess(for:.audio) { [weak self] ok in DispatchQueue.main.async {
            guard self?.startID == requestID else { return }
            if ok { begin() } else {
                self?.busy = false; self?.tab = 2
                self?.notice = "Allow microphone access in System Settings › Privacy & Security › Microphone, or select Soundboard only."
            }
        }}
    }
    func stop() {
        startID = UUID(); busy = false
        mic_stop(engine); live = false; level = 0; currentPad = ""; heldAudio = nil; onAirChanged?(false)
    }
    func play(_ pad: Pad, toggle: Bool = true) {
        if toggle && currentPad == pad.id { stopPad(); return }
        start { [weak self] in
            guard let self else { return }
            do {
                let audio = try decodeClip(pad.url)
                mic_play(self.engine,audio.bytes.assumingMemoryBound(to:Float.self),Int32(audio.length/4))
                self.heldAudio = audio; self.currentPad = pad.id; self.notice = ""
            } catch { self.notice = error.localizedDescription }
        }
    }
    func stopPad() { mic_play(engine,nil,0); currentPad = ""; heldAudio = nil }
    func endTest() { mic_stop(preview); testing = false; testAudio = nil }
    func testMonitor() {
        if testing { endTest(); return }
        guard monitorChoices.contains(where: { $0.id == monitor }), monitor != send || !sending else {
            notice = "Choose a separate monitor output for the test tone."; return
        }
        let status = mic_start(preview,nil,nil,monitor)
        guard status == 0 else { notice = "Couldn’t open the monitor (\(status))."; return }
        let count = 28800
        let samples: [Float] = (0..<count).map { i in
            let t = Double(i)/48000
            let hz: Double = i < count/2 ? 523.25 : 659.25
            let u = Double(i % (count/2))/48000
            let envelope = min(1.0, u / 0.015, (0.3 - u) / 0.04) * exp(-2 * u)
            let tone = sin(2 * Double.pi * hz * t)
            return Float(0.38 * tone * envelope)
        }
        let audio = samples.withUnsafeBytes { NSData(bytes:$0.baseAddress!,length:$0.count) }
        testAudio = audio; testTicks = 0; testing = true; notice = ""
        mic_play(preview,audio.bytes.assumingMemoryBound(to:Float.self),Int32(count))
    }
    @discardableResult func importPad() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.prompt = "Add sound"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do { try importFile(url); return true } catch { notice = error.localizedDescription; return false }
    }
    func importFile(_ url: URL) throws {
            _ = try decodeClip(url)
            try FileManager.default.createDirectory(at:clipsDir,withIntermediateDirectories:true)
            var name = url.deletingPathExtension().lastPathComponent
            if name.isEmpty { name = "Clip" }
            var target = clipsDir.appendingPathComponent(url.lastPathComponent)
            var index = 1
            while FileManager.default.fileExists(atPath:target.path) || pads.contains(where:{ $0.id == target.lastPathComponent }) {
                index += 1; target = clipsDir.appendingPathComponent("\(name) \(index)").appendingPathExtension(url.pathExtension)
            }
            try FileManager.default.copyItem(at:url,to:target); reloadPads(); notice = ""
    }
}
