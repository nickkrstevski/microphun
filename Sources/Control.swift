import AppKit
import CoreFoundation

final class CommandServer {
    private var port: CFMessagePort?
    private var source: CFRunLoopSource?
    let studio: Studio
    init(studio: Studio) throws {
        self.studio = studio
        var context = CFMessagePortContext(version:0,info:Unmanaged.passUnretained(self).toOpaque(),retain:nil,release:nil,copyDescription:nil)
        let callback: CFMessagePortCallBack = { _,_,payload,info in
            guard let info else { return nil }
            let server = Unmanaged<CommandServer>.fromOpaque(info).takeUnretainedValue()
            var response: [String:Any]
            do {
                guard let payload, CFDataGetLength(payload) <= 16384,
                      let args = try JSONSerialization.jsonObject(with:payload as Data) as? [String] else {
                    throw AppError("Malformed command.")
                }
                response = ["ok":true,"result":try server.execute(args)]
            } catch { response = ["ok":false,"error":error.localizedDescription] }
            guard let data = try? JSONSerialization.data(withJSONObject:response) else { return nil }
            return Unmanaged.passRetained(data as CFData)
        }
        guard let port = CFMessagePortCreateLocal(nil,microphunPort,callback,&context,nil),
              let source = CFMessagePortCreateRunLoopSource(nil,port,0) else {
            throw AppError("Couldn’t register the local CLI. Another Microphun instance may be running.")
        }
        self.port=port; self.source=source
        CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
    }
    deinit {
        if let source { CFRunLoopSourceInvalidate(source) }
        if let port { CFMessagePortInvalidate(port) }
    }
    private func state() -> [String:Any] {
        let s=studio
        return ["hold-send-level":s.holdSendLevel,"gain-corrections":s.blackHoleLevel.corrections,"gain-error":s.blackHoleLevel.lastError,"isolation":s.isolation,"live":s.live,"pending":s.busy,"preset":s.activePreset,"effect":Preset.modes[s.mode],
                "pitch":s.pitch,"reverb":s.reverb*100,"amount":s.depth*100,
                "pad-level":s.padGain*100,"monitor-level":s.volume*100,
                "input":s.input,"send":s.sending ? s.send : "","monitor":s.monitor,"monitor-voice":s.monitoring,
                "pad":s.currentPad,"testing":s.testing,"message":s.notice]
    }
    private func key(_ name:String) -> String { name.lowercased().filter { $0.isLetter || $0.isNumber } }
    private func execute(_ args:[String]) throws -> Any {
        guard let command=args.first else { throw AppError(cliGuide) }
        let s=studio
        let values=Array(args.dropFirst())
        func count(_ expected:Int) throws {
            if values.count != expected { throw AppError("Incorrect arguments. Run microphun help.") }
        }
        let name=values.joined(separator:" ")
        func requireReady() throws {
            if s.routingLocked { throw AppError("An audio change is already in progress.") }
        }
        switch command {
        case "status": try count(0)
        case "presets": try count(0); return Preset.bank.map(\.name)
        case "pads": try count(0); return s.pads.map { ["name":$0.name,"bank":$0.bank,"id":$0.id] }
        case "devices":
            try count(0)
            return s.devices.map { ["name":$0.name,"id":$0.id,"inputs":$0.inputs,"outputs":$0.outputs,"virtual":$0.isVirtual] as [String:Any] }
        case "preset":
            let wanted=key(name) == "houston" ? "houstonradio" : key(name)
            guard let preset=Preset.bank.first(where:{ key($0.name) == wanted }) else { throw AppError("Unknown preset. Run microphun presets.") }
            s.apply(preset)
        case "set":
            guard let control=values.first, values.count>=2 else { throw AppError(cliGuide) }
            if ["isolation","monitor-voice","hold-send-level"].contains(control) {
                try count(2)
                guard ["on","off"].contains(values[1]) else { throw AppError("Choose on or off.") }
                if control == "isolation" { s.isolation = values[1]=="on" }
                else if control == "hold-send-level" { s.holdSendLevel = values[1]=="on" }
                else { try requireReady(); s.monitoring = values[1]=="on"; if !s.notice.isEmpty { throw AppError(s.notice) } }
            } else if control == "effect" {
                let name=key(values.dropFirst().joined(separator:" "))
                guard let mode=Preset.modes.firstIndex(where:{ key($0)==name }) else { throw AppError("Choose an effect from " + Preset.modes.joined(separator:", ")) }
                s.mode=mode
            } else {
                try count(2)
                let range: ClosedRange<Double> = control == "pitch" ? -12...12 : 0...100
                guard let value=Double(values[1]),value.isFinite,range.contains(value) else { throw AppError("Value must be in \(range).") }
                switch control {
                case "pitch": s.pitch=value
                case "reverb": s.reverb=value/100
                case "amount": s.depth=value/100
                case "pad-level": s.padGain=value/100
                case "monitor-level": s.volume=value/100
                default: throw AppError("Unknown control. Run microphun help.")
                }
            }
        case "route":
            try requireReady()
            guard let role=values.first,values.count>=2 else { throw AppError(cliGuide) }
            let choices: [Device]
            switch role {
            case "input": choices=s.inputChoices
            case "send": choices=s.sendChoices
            case "monitor": choices=s.monitorChoices
            default: throw AppError("Choose input, send, or monitor.")
            }
            let target=values.dropFirst().joined(separator:" ")
            let off=target.lowercased()=="off"
            let matches=choices.filter { $0.id==target || $0.name.caseInsensitiveCompare(target) == .orderedSame }
            guard off || matches.count==1 else { throw AppError("Choose a unique device name or UID from microphun devices.") }
            let uid=matches.first?.id ?? ""
            s.changeRoutes { next in
                switch role {
                case "input": next.input=uid
                case "send": if !off { next.send=uid }; next.sending = !off
                default: if off { next.monitoring=false } else { next.monitor=uid }
                }
            }
            if !s.notice.isEmpty { throw AppError(s.notice) }
        case "start","play":
            guard !s.busy else { throw AppError("An audio start is already pending.") }
            s.notice=""
            if command=="start" { try count(0); s.start() }
            else {
                let matches=s.pads.filter { $0.id==name || key($0.name)==key(name) }
                guard matches.count==1 else { throw AppError("Choose a unique pad name or file ID from microphun pads.") }
                s.play(matches[0],toggle:false)
            }
            if !s.notice.isEmpty { throw AppError(s.notice) }
        case "stop": try count(0); s.stop()
        case "stop-pad": try count(0); s.stopPad()
        case "test-monitor":
            try count(0); guard !s.testing else { return state() }
            s.testMonitor(); if !s.testing { throw AppError(s.notice) }
        case "import":
            try count(1)
            let url=URL(fileURLWithPath:values[0])
            try s.importFile(url)
        default: throw AppError("Unknown command. Run microphun help.")
        }
        return state()
    }
}
