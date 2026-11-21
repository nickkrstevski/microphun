import Foundation
import CoreFoundation

let microphunPort = "com.nickkrstevski.microphun.control.\(getuid())" as CFString
let cliGuide = """
microphun open | status | presets | pads | devices
microphun preset NAME
microphun set pitch -12..12
microphun set reverb|amount|pad-level|monitor-level 0..100
microphun set effect NAME
microphun set isolation|monitor-voice|hold-send-level on|off
microphun route input|send|monitor DEVICE-NAME-OR-UID|off
microphun start | stop | test-monitor
microphun play PAD-NAME | stop-pad | import FILE

Example: microphun preset houston
Example: microphun play "Dolphin censor"
Sound pads always play on the monitor. 'route monitor off' mutes local voice only.
Device changes briefly reconnect live audio. 'route input off' selects soundboard only.
Commands print JSON. Preset and pad names are case-insensitive.
"""
