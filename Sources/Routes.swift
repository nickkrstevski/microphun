import Foundation

struct Routes: Equatable {
    static let micUID = "com.nickkrstevski.microphun.mic"
    static let sendUID = "com.nickkrstevski.microphun.send"
    var input = ""
    var send = ""
    var monitor = ""
    var sending = true
    var monitoring = false

    var capture: String? { (sending || monitoring) && !input.isEmpty ? input : nil }
    var destination: String? { sending ? (send == Self.micUID ? Self.sendUID : send) : nil }
    func usesSameDevices(as other: Routes) -> Bool {
        capture == other.capture && destination == other.destination && monitor == other.monitor
    }
}
