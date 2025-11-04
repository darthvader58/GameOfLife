import Cocoa
import MetalKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create window
        let windowRect = NSRect(x: 100, y: 100, width: 1200, height: 900)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Conway's Game of Life on Steroids - Metal GPU"
        window.center()
        
        // Create Metal view
        let metalView = GameOfLifeView(frame: window.contentView!.bounds)
        window.contentView = metalView
        
        window.makeKeyAndOrderFront(nil)
        
        // Quit when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: nil
        ) { _ in
            NSApp.terminate(nil)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}