import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var item: NSStatusItem!
    private var panel: NSPanel!
    private var studio: Studio!
    private var commands: CommandServer?
    private var activity: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification:Notification) {
        studio = Studio()
        do { commands = try CommandServer(studio:studio) } catch { studio.notice = error.localizedDescription }
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item.button?.action = #selector(clicked); item.button?.target = self
        item.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        updateIcon(false)
        studio.onAirChanged = { [weak self] live in
            guard let self else { return }
            self.updateIcon(live)
            if live { self.activity = ProcessInfo.processInfo.beginActivity(options:[.userInitiatedAllowingIdleSystemSleep,.latencyCritical],reason:"Live voice processing") }
            else if let a = self.activity { ProcessInfo.processInfo.endActivity(a); self.activity = nil }
        }
        panel = NSPanel(contentRect:NSRect(x:0,y:0,width:404,height:554),styleMask:[.titled,.fullSizeContentView,.closable],backing:.buffered,defer:false)
        panel.title = "Microphun"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        for b: NSWindow.ButtonType in [.closeButton,.miniaturizeButton,.zoomButton] { panel.standardWindowButton(b)?.isHidden = true }
        panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.hidesOnDeactivate = false; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:Console(s:studio,dismiss:{ [weak self] in self?.panel.orderOut(nil) }))
        panel.delegate = self
        show()
    }
    func updateIcon(_ live:Bool) {
        let icon = NSImage(systemSymbolName:live ? "waveform.circle.fill" : "waveform.circle",accessibilityDescription:live ? "Microphun live" : "Microphun")
        icon?.isTemplate = true; item.button?.image = icon
        item.button?.toolTip = live ? "Microphun · Audio running" : "Microphun · Open voice controls"
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool { show(); return true }
    @objc func show() {
        guard let panel else { return }
        if let b = item.button, let w = b.window, let screen = w.screen {
            let anchor = w.convertToScreen(b.convert(b.bounds,to:nil))
            let rect = screen.visibleFrame
            let x = min(max(rect.minX+6,anchor.midX-panel.frame.width/2),rect.maxX-panel.frame.width-6)
            panel.setFrameTopLeftPoint(NSPoint(x:x,y:min(rect.maxY,anchor.minY)-5))
        } else { panel.center() }
        NSApp.activate(ignoringOtherApps:true); panel.makeKeyAndOrderFront(nil)
    }
    @objc func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            func add(_ title:String,_ action:Selector) { let i=menu.addItem(withTitle:title,action:action,keyEquivalent:""); i.target=self }
            add("Open Microphun",#selector(show))
            if studio.live { add("Stop audio",#selector(stopAudio)) }
            menu.addItem(.separator()); add("Quit Microphun",#selector(quit))
            if let button = item.button { menu.popUp(positioning:nil,at:NSPoint(x:0,y:button.bounds.minY-4),in:button) }
        } else if panel.isVisible { panel.orderOut(nil) } else { show() }
    }
    @objc func stopAudio() { studio.stop() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification:Notification) { studio.stop(); studio.endTest() }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory); app.delegate = delegate; app.run()
