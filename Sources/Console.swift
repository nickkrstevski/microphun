import SwiftUI

private let ink = Color(red:0.074,green:0.083,blue:0.078)
private let card = Color(red:0.119,green:0.132,blue:0.121)
private let line = Color.white.opacity(0.105)
private let quiet = Color(red:0.68,green:0.71,blue:0.66)
private let lime = Color(red:0.77,green:0.95,blue:0.45)
private let peach = Color(red:1,green:0.69,blue:0.47)
private let mono = Font.system(size:10,weight:.semibold,design:.monospaced)
private let columns = Array(repeating:GridItem(.flexible(),spacing:7),count:3)

struct Console: View {
    @ObservedObject var s: Studio
    @State private var bank = "SpongeBob"
    var dismiss: () -> Void
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                ZStack { RoundedRectangle(cornerRadius:9).fill(lime); Image(systemName:"waveform").font(.system(size:21,weight:.heavy)).foregroundStyle(ink) }.frame(width:35,height:35)
                Text("Microphun").font(.system(size:26,weight:.bold,design:.rounded)).tracking(-1.1)
                Spacer()
                HStack(spacing:6) { Circle().fill(s.live ? lime : quiet).frame(width:6,height:6); Text(s.live ? "LIVE" : "IDLE").font(mono).tracking(1) }
                    .foregroundStyle(s.live ? lime : quiet).padding(.vertical,6).padding(.horizontal,9).overlay(Capsule().stroke(line))
                Button(action:dismiss) { Image(systemName:"chevron.down").frame(width:20,height:24) }.buttonStyle(.plain).foregroundStyle(quiet).help("Hide controls")
            }.padding(.horizontal,19).padding(.top,19).padding(.bottom,17)
            HStack(spacing:3) {
                ForEach(Array(["Voice","Soundboard","Routing"].enumerated()),id:\.offset) { i,name in
                    Button { s.tab = i } label: {
                        HStack(spacing:6) { Image(systemName:["waveform","square.grid.2x2.fill","point.3.connected.trianglepath.dotted"][i]); Text(name) }
                            .font(.system(size:12,weight:.semibold)).frame(maxWidth:.infinity).padding(.vertical,8)
                            .background(s.tab == i ? Color.white.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:6))
                    }.buttonStyle(.plain).foregroundStyle(s.tab == i ? .white : quiet)
                }
            }.padding(3).background(.black.opacity(0.23),in:RoundedRectangle(cornerRadius:8)).padding(.horizontal,18)
            ScrollView {
                VStack(alignment:.leading,spacing:15) {
                    if s.tab == 0 { voice }
                    if s.tab == 1 { soundboard }
                    if s.tab == 2 { routing }
                }.padding(.horizontal,19).padding(.vertical,17).frame(maxWidth:.infinity,alignment:.leading)
            }
            if !s.notice.isEmpty {
                HStack(alignment:.top,spacing:8) {
                    Image(systemName:"info.circle"); Text(s.notice).font(.system(size:12)).fixedSize(horizontal:false,vertical:true)
                    Spacer(); Button { s.notice = "" } label:{ Image(systemName:"xmark").font(.system(size:10)) }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
                }.foregroundStyle(peach).padding(.horizontal,18).padding(.vertical,8).background(peach.opacity(0.06))
            }
            Rectangle().fill(line).frame(height:1)
            HStack(spacing:14) {
                VStack(alignment:.leading,spacing:6) {
                    Text("MIX LEVEL").font(mono).tracking(1.0).foregroundStyle(quiet)
                    HStack(spacing:2) {
                        ForEach(0..<20,id:\.self) { i in
                            let db = 20 * log10(max(Double(s.level),0.0001))
                            RoundedRectangle(cornerRadius:1).fill(s.live && db > Double(i)*2.4-48 ? (i>16 ? peach : lime) : Color.white.opacity(0.12)).frame(width:4,height:8)
                        }
                    }.accessibilityLabel("Mix level")
                }
                Spacer()
                Button { if s.live { s.stop() } else { s.start() } } label: {
                    HStack(spacing:7) { Image(systemName:s.live ? "stop.fill" : "play.fill").font(.system(size:10)); Text(s.live ? "Stop audio" : s.busy ? "Opening…" : "Start audio").font(.system(size:13,weight:.bold)) }
                        .frame(width:118,height:34).foregroundStyle(ink).background(s.live ? peach : lime,in:RoundedRectangle(cornerRadius:8))
                }.buttonStyle(.plain).disabled(s.busy)
            }.padding(.horizontal,19).padding(.vertical,13)
        }.frame(width:404,height:554).background(ink).foregroundStyle(.white).tint(lime).preferredColorScheme(.dark)
    }
    private func label(_ text:String) -> some View { Text(text.uppercased()).font(mono).tracking(1.4).foregroundStyle(quiet) }
    private func slider(_ title:String,_ binding:Binding<Double>,_ range:ClosedRange<Double>,_ step:Double,_ value:String) -> some View {
        VStack(spacing:3) {
            HStack { Text(title).font(.system(size:13,weight:.medium)); Spacer(); Text(value).font(.system(size:11,weight:.medium,design:.monospaced)).foregroundStyle(lime) }
            Slider(value:binding,in:range,step:step).controlSize(.small).accessibilityLabel(title)
        }
    }
    private var voice: some View {
        Group {
            HStack { label("Voice presets"); Spacer(); Text(s.activePreset).font(.caption).foregroundStyle(lime) }
            LazyVGrid(columns:columns,spacing:7) {
                ForEach(Preset.bank) { p in
                    let chosen = s.activePreset == p.name
                    Button { s.apply(p) } label: {
                        HStack(spacing:7) { Image(systemName:p.icon).frame(width:21); Text(p.name).font(.system(size:12,weight:.semibold)); Spacer(minLength:0) }.padding(.horizontal,9).frame(height:36)
                            .foregroundStyle(chosen ? lime : .white).background(chosen ? lime.opacity(0.10) : card,in:RoundedRectangle(cornerRadius:7))
                            .overlay(RoundedRectangle(cornerRadius:7).stroke(chosen ? lime.opacity(0.58) : line))
                    }.buttonStyle(.plain)
                }
            }
            Toggle("Voice isolation",isOn:$s.isolation).toggleStyle(.switch).controlSize(.small)
                .help("Reduce typing and background noise before voice effects.")
            label("Fine tune")
            VStack(spacing:10) {
                slider("Pitch",$s.pitch,-12...12,1,String(format:"%+.0f st",s.pitch))
                slider("Reverb",$s.reverb,0...1,0.01,"\(Int((s.reverb*100).rounded()))%")
                Divider()
                HStack { Text("Modulation").font(.system(size:13,weight:.medium)); Spacer()
                    Picker("Modulation",selection:$s.mode) {
                        ForEach(Array(Preset.modes.enumerated()),id:\.offset) { i,n in Text(n).tag(i) }
                    }.labelsHidden().frame(width:107)
                }
                if s.mode != 0 { slider("Amount",$s.depth,0...1,0.01,"\(Int((s.depth*100).rounded()))%") }
            }.padding(13).background(card,in:RoundedRectangle(cornerRadius:10))
        }
    }
    private var soundboard: some View {
        Group {
            HStack { label("Sound pads"); Spacer()
                Button { if s.importPad() { bank = "Imports" } } label:{ Label("Import",systemImage:"plus").font(.system(size:12,weight:.semibold)) }.buttonStyle(.plain).foregroundStyle(lime)
            }
            Picker("Sound bank",selection:$bank) {
                ForEach(["SpongeBob","Reactions","Imports"],id:\.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            if bank == "Imports" && !s.pads.contains(where:{ $0.bank == bank }) {
                Text("Import an audio clip to add your first pad.").foregroundStyle(quiet).font(.caption)
            }
            LazyVGrid(columns:columns,spacing:7) {
                ForEach(Array(s.pads.filter { $0.bank == bank }.enumerated()),id:\.element.id) { i,pad in
                    let selected = s.currentPad == pad.id
                    let color = [lime,Color.cyan,peach,Color.purple][i%4]
                    Button { s.play(pad) } label: {
                        VStack(alignment:.leading,spacing:9) {
                            HStack { Image(systemName:selected ? "speaker.wave.2.fill" : pad.symbol).foregroundStyle(color); Spacer(); Image(systemName:selected ? "stop.fill" : "play.fill").font(.system(size:8)).foregroundStyle(quiet) }
                            Text(pad.name).font(.system(size:12,weight:.semibold)).lineLimit(1)
                        }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(selected ? color.opacity(0.16) : card,in:RoundedRectangle(cornerRadius:8))
                        .overlay(RoundedRectangle(cornerRadius:8).stroke(selected ? color : line))
                    }.buttonStyle(.plain).help(selected ? "Stop this sound" : (s.live ? "Play \(pad.name)" : "Start audio and play \(pad.name)"))
                }
            }
            slider("Soundboard level",$s.padGain,0...1,0.01,"\(Int((s.padGain*100).rounded()))%")
            if !s.currentPad.isEmpty { Button("Stop sound",action:s.stopPad).controlSize(.small) }
            if !s.live { Text("Playing a pad starts audio with your selected routes.").font(.caption).foregroundStyle(quiet) }
        }
    }
    private func selector(_ title:String,_ selection:Binding<String>,_ choices:[Device],_ empty:String) -> some View {
        Picker(title,selection:selection) {
            Text(empty).tag("")
            if !selection.wrappedValue.isEmpty && !choices.contains(where: { $0.id == selection.wrappedValue }) { Text("Disconnected device").tag(selection.wrappedValue) }
            ForEach(choices) { d in Text(d.name).tag(d.id) }
        }.labelsHidden().frame(maxWidth:.infinity).accessibilityLabel(title)
    }
    private var routing: some View {
        Group {
            VStack(alignment:.leading,spacing:7) {
                label("Input microphone")
                selector("Input microphone",$s.input,s.inputChoices,"Soundboard only")
            }.disabled(s.routingLocked)
            VStack(alignment:.leading,spacing:7) {
                Toggle("Send to calls",isOn:$s.sending).toggleStyle(.switch).controlSize(.small)
                if s.sending {
                    selector("Virtual microphone",$s.send,s.sendChoices,"Choose a loopback device")
                    Text("In Zoom or Discord, select \(s.sendChoices.first(where:{ $0.id == s.send })?.name ?? "the same loopback device") as your microphone.").font(.caption).foregroundStyle(quiet)
                }
            }.disabled(s.routingLocked)
            if s.sending && s.send == BlackHoleLevel.uid {
                Toggle("Keep BlackHole at full volume",isOn:$s.holdSendLevel)
                    .toggleStyle(.switch).controlSize(.small)
                    .help("Hold the shared device gain while sending audio to BlackHole.")
            }
            Divider()
            VStack(alignment:.leading,spacing:8) {
                Toggle("Monitor voice",isOn:$s.monitoring).toggleStyle(.switch).controlSize(.small).disabled(s.routingLocked)
                Text("Sound pads always play on this output.").font(.caption).foregroundStyle(quiet)
                selector("Monitor output",$s.monitor,s.monitorChoices,"Choose headphones or speakers").disabled(s.routingLocked || s.testing)
                HStack { Text("Headphones avoid mic feedback.").font(.caption).foregroundStyle(quiet); Spacer()
                    Button(s.testing ? "Stop test" : "Test monitor",action:s.testMonitor).controlSize(.small).disabled(s.monitor.isEmpty || s.busy)
                }
                slider("Monitor level",$s.volume,0...1,0.01,"\(Int((s.volume*100).rounded()))%")
            }

        }
    }
}
