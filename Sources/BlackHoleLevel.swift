import CoreAudio
import Foundation

/// BlackHole 2ch exposes a single shared gain through its input and output scopes.
final class BlackHoleLevel {
    static let uid = "BlackHole2ch_UID"
    private var device: AudioDeviceID?
    private var listener: AudioObjectPropertyListenerBlock?
    private var gain = AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyVolumeScalar,
        mScope:kAudioDevicePropertyScopeOutput, mElement:kAudioObjectPropertyElementMain)
    private(set) var corrections = 0
    private(set) var lastError: OSStatus = noErr

    func hold(_ id: AudioDeviceID?) {
        guard id != device else { return }
        if let old = device, let listener {
            AudioObjectRemovePropertyListenerBlock(old, &gain, .main, listener)
        }
        listener = nil
        device = id
        lastError = noErr
        guard let id else { return }
        let changed: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.device == id else { return }
            self.check()
        }
        if AudioObjectAddPropertyListenerBlock(id, &gain, .main, changed) == noErr {
            listener = changed
        }
        check()
    }
    func check() {
        guard let device else { return }
        var mute = AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyMute,
            mScope:kAudioDevicePropertyScopeOutput, mElement:kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue:muted))
        if AudioObjectGetPropertyData(device,&mute,0,nil,&size,&muted) == noErr && muted != 0 { return }
        var level: Float32 = 0
        size = UInt32(MemoryLayout.size(ofValue:level))
        lastError = AudioObjectGetPropertyData(device,&gain,0,nil,&size,&level)
        guard lastError == noErr && level < 0.999 else { return }
        level = 1
        lastError = AudioObjectSetPropertyData(device,&gain,0,nil,size,&level)
        if lastError == noErr { corrections += 1 }
    }
    deinit { hold(nil) }
}
