import IOKit.hid
import SwiftUI

@main
struct LogiSwipeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("LogiSwipe", systemImage: "computermouse") {
            StatusView(t630: .shared)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ask for both permissions up front; the system shows its own prompts.
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        T630.shared.start()
    }
}

struct StatusView: View {
    @ObservedObject var t630: T630

    var body: some View {
        Form {
            LabeledContent("T630", value: t630.connected ? "Connected" : "Not connected")
            Button("Quit LogiSwipe") { NSApp.terminate(nil) }
        }
        .formStyle(.grouped)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
    }
}
