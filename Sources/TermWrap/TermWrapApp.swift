import AppKit
import SwiftUI

@main
struct TermWrapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var AppDelegateAdapter

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 760, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ Sender: NSApplication) -> Bool {
        !SharedAppState.Shared.IsGenerating
    }

    func applicationShouldTerminate(_ Sender: NSApplication) -> NSApplication.TerminateReply {
        guard SharedAppState.Shared.IsGenerating else {
            return .terminateNow
        }

        let Alert = NSAlert()
        Alert.messageText = "Application generation is still in progress."
        Alert.informativeText = "Quitting now may leave a partial wrapper application on disk."
        Alert.alertStyle = .warning
        Alert.addButton(withTitle: "Keep Working")
        Alert.addButton(withTitle: "Quit Anyway")

        return Alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
