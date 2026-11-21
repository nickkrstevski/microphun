import AppKit
import AudioToolbox
import CoreAudio

struct Device: Identifiable, Equatable {
    let id: String
    let name: String
    let objectID: AudioDeviceID
    let inputs: Int
    let outputs: Int
    let isVirtual: Bool

    private static func value<T>(_ device: AudioObjectID, _ key: AudioObjectPropertySelector, _ initial: T) -> T {
        var address = AudioObjectPropertyAddress(mSelector: key, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var result = initial
        var size = UInt32(MemoryLayout<T>.size)
        _ = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0) }
        return result
    }
    private static func string(_ device: AudioObjectID, _ key: AudioObjectPropertySelector) -> String {
        let cf: Unmanaged<CFString>? = value(device, key, nil as Unmanaged<CFString>?)
        return cf?.takeRetainedValue() as String? ?? ""
    }
    static func defaultUID(input: Bool) -> String {
        let id = value(AudioObjectID(kAudioObjectSystemObject), input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, AudioDeviceID(0))
        return id == 0 ? "" : string(id, kAudioDevicePropertyDeviceUID)
    }
    static func list() -> [Device] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size)/4)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.prefix(Int(size)/4).compactMap { id in
            func channels(_ scope: AudioObjectPropertyScope) -> Int {
                var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
                var bytes: UInt32 = 0
                guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &bytes) == noErr, bytes >= MemoryLayout<UInt32>.size else { return 0 }
                let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(bytes), alignment: MemoryLayout<AudioBufferList>.alignment)
                defer { storage.deallocate() }
                guard AudioObjectGetPropertyData(id, &a, 0, nil, &bytes, storage) == noErr else { return 0 }
                return UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
            }
            let uid = string(id, kAudioDevicePropertyDeviceUID)
            guard !uid.isEmpty else { return nil }
            return Device(id: uid, name: string(id, kAudioObjectPropertyName), objectID:id, inputs: channels(kAudioDevicePropertyScopeInput), outputs: channels(kAudioDevicePropertyScopeOutput), isVirtual: value(id,kAudioDevicePropertyTransportType,UInt32(0)) == kAudioDeviceTransportTypeVirtual)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func decodeClip(_ url: URL) throws -> NSData {
    var file: ExtAudioFileRef?
    guard ExtAudioFileOpenURL(url as CFURL, &file) == noErr, let file else {
        throw AppError("Couldn’t read \(url.lastPathComponent). Try WAV, MP3, AIFF or M4A.")
    }
    defer { ExtAudioFileDispose(file) }
    var format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagsNativeFloatPacked, mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
    guard ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: format)), &format) == noErr else { throw AppError("This audio format couldn’t be converted for playback.") }
    let audio = NSMutableData()
    var chunk = [Float](repeating: 0, count: 8192)
    while true {
        var count: UInt32 = 8192
        try chunk.withUnsafeMutableBytes { bytes in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            guard ExtAudioFileRead(file, &count, &list) == noErr else { throw AppError("Couldn’t decode this audio clip.") }
            if count > 0 { audio.append(bytes.baseAddress!, length: Int(count)*4) }
        }
        if count == 0 { break }
        if audio.length > 48000*4*120 { throw AppError("Choose a soundboard clip under two minutes.") }
    }
    guard audio.length > 0 else { throw AppError("This clip contains no audio.") }
    return audio
}

struct Pad: Identifiable, Equatable {
    var id: String { url.lastPathComponent }
    let name: String
    let symbol: String
    let url: URL
    var bank: String = "Imports"
    static let spongeBob = [
        ("Boo-womp","waveform.path","BooWomp.mp3"),
        ("Dolphin censor","water.waves","DolphinCensor.mp3"),
        ("My leg!","figure.fall","MyLeg.mp3"),
        ("Squidward steps","shoeprints.fill","SquidwardSteps.mp3"),
        ("Mr. Krabs walk","figure.walk","MrKrabsWalk.mp3"),
        ("Moments later","hourglass","MomentsLater.mp3"),
        ("SpongeBob laugh","face.smiling","SpongeLaugh.mp3"),
        ("Bubble wipe","bubbles.and.sparkles","BubbleTransition.mp3")
    ]
    static let originals = [
        ("Anvil delivery","shippingbox.fill","Anvil.wav"),
        ("Awkward crickets","leaf.fill","Crickets.wav"),
        ("Printer tantrum","printer.fill","Printer.wav"),
        ("Squeaky boots","shoeprints.fill","Boots.wav"),
        ("Bubble break","bubbles.and.sparkles","Bubbles.wav"),
        ("Fog horn","ferry.fill","Foghorn.wav"),
        ("Lagoon slide","guitars.fill","Lagoon.wav"),
        ("Bonk","hammer.fill","Bonk.wav"),
        ("Sad trombone","music.note","Womp.wav"),
        ("Rimshot","drum.fill","Rimshot.wav"),
        ("Game over","gamecontroller.fill","GameOver.wav"),
        ("Houston","moon.stars.fill","Houston.mp3")
    ]
    static func bundled(_ folder: URL) -> [Pad] {
        [("SpongeBob",spongeBob),("Reactions",originals)].flatMap { bank, clips in
            clips.map { Pad(name:$0.0,symbol:$0.1,url:folder.appendingPathComponent($0.2),bank:bank) }
        }
    }
}
