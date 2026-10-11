import AppKit
import Foundation

final class DummyAppDelegate: NSObject, NSApplicationDelegate {
    private var delayTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let pid = ProcessInfo.processInfo.processIdentifier
        print("DUMMY_READY_PID=\(pid)")
        fflush(stdout)

        if ProcessInfo.processInfo.arguments.contains("--delay-terminate") {
            delayTermination = true
            print("DUMMY_MODE=DELAY_TERMINATE")
            fflush(stdout)
        }

        // Safety self-termination after 60 seconds so it never lingers if a test runner crashes
        DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) {
            print("DUMMY_SELF_TIMEOUT_EXIT")
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        print("DUMMY_TERMINATE_REQUEST_RECEIVED")
        fflush(stdout)

        if delayTermination {
            print("DUMMY_DELAYING_TERMINATE_REPLY")
            fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                print("DUMMY_REPLY_TERMINATE_NOW")
                fflush(stdout)
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }

        return .terminateNow
    }
}

let app = NSApplication.shared
let delegate = DummyAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

