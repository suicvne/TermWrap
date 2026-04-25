import AppKit
import Foundation
import SwiftTerm

enum HostLogger {
    static func Write(_ Message: String) {
        let FileManagerValue = FileManager.default
        guard let LogsURL = FileManagerValue.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Logs/TermWrap", isDirectory: true) else {
            return
        }

        try? FileManagerValue.createDirectory(at: LogsURL, withIntermediateDirectories: true)
        let LogURL = LogsURL.appendingPathComponent("TermWrapHost.log")
        let AppName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Unknown"
        let Line = "[\(Date())] [\(AppName)] \(Message)\n"

        if let DataValue = Line.data(using: .utf8) {
            if FileManagerValue.fileExists(atPath: LogURL.path), let Handle = try? FileHandle(forWritingTo: LogURL) {
                _ = try? Handle.seekToEnd()
                try? Handle.write(contentsOf: DataValue)
                try? Handle.close()
            } else {
                try? DataValue.write(to: LogURL, options: .atomic)
            }
        }
    }
}

struct HostConfiguration: Decodable {
    let CommandPath: String
    let CommandArguments: [String]
    let FontName: String
    let FontSize: Double

    static func Load() throws -> HostConfiguration {
        guard
            let URL = Bundle.main.url(forResource: "WrapperConfiguration", withExtension: "plist"),
            let Data = try? Data(contentsOf: URL)
        else {
            throw HostError.MissingConfiguration
        }

        return try PropertyListDecoder().decode(HostConfiguration.self, from: Data)
    }
}

enum HostError: LocalizedError {
    case MissingConfiguration

    var errorDescription: String? {
        switch self {
        case .MissingConfiguration:
            return "WrapperConfiguration.plist is missing from the application bundle."
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var WindowController: TerminalWindowController?

    func applicationWillFinishLaunching(_ Notification: Notification) {
        HostLogger.Write("applicationWillFinishLaunching")
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ Notification: Notification) {
        HostLogger.Write("applicationDidFinishLaunching")
        NSWindow.allowsAutomaticWindowTabbing = false
        WindowController = TerminalWindowController(ConfigurationResult: Result { try HostConfiguration.Load() })
        WindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ Sender: NSApplication) -> Bool {
        !(WindowController?.IsJobRunning ?? false)
    }
}

final class TerminalWindowController: NSWindowController, LocalProcessTerminalViewDelegate {
    private let ConfigurationResult: Result<HostConfiguration, Error>
    private var TerminalView: LocalProcessTerminalView?

    var IsJobRunning: Bool {
        TerminalView?.process.running ?? false
    }

    init(ConfigurationResult: Result<HostConfiguration, Error>) {
        self.ConfigurationResult = ConfigurationResult
        let Window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        Window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Terminal Wrapper"
        Window.center()
        Window.isReleasedWhenClosed = false
        super.init(window: Window)
        ConfigureView()
        Window.makeKeyAndOrderFront(nil)
        Window.orderFrontRegardless()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func ConfigureView() {
        switch ConfigurationResult {
        case .success(let Configuration):
            ConfigureTerminalView(Configuration: Configuration)
        case .failure(let ErrorValue):
            HostLogger.Write("configuration load failed: \(ErrorValue.localizedDescription)")
            ConfigureErrorView(Message: "Failed to load wrapper configuration: \(ErrorValue.localizedDescription)")
        }
    }

    private func ConfigureTerminalView(Configuration: HostConfiguration) {
        guard let Window = window else { return }

        let View = LocalProcessTerminalView(frame: Window.contentView?.bounds ?? .zero)
        View.autoresizingMask = [.width, .height]
        View.processDelegate = self
        View.font = NSFont(name: Configuration.FontName, size: Configuration.FontSize) ?? NSFont.userFixedPitchFont(ofSize: Configuration.FontSize) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        View.nativeForegroundColor = .textColor
        View.nativeBackgroundColor = .textBackgroundColor
        View.caretColor = .textColor
        View.optionAsMetaKey = true
        View.allowMouseReporting = true

        Window.contentView = View
        Window.initialFirstResponder = View
        Window.makeFirstResponder(View)
        TerminalView = View

        let CommandLine = ([Configuration.CommandPath] + Configuration.CommandArguments).joined(separator: " ")
        HostLogger.Write("launching \(CommandLine)")
        View.startProcess(
            executable: Configuration.CommandPath,
            args: Configuration.CommandArguments,
            environment: Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        )
    }

    private func ConfigureErrorView(Message: String) {
        guard let Window = window else { return }

        let TextView = NSTextView(frame: Window.contentView?.bounds ?? .zero)
        TextView.autoresizingMask = [.width, .height]
        TextView.font = NSFont.userFixedPitchFont(ofSize: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        TextView.textColor = .textColor
        TextView.backgroundColor = .textBackgroundColor
        TextView.isEditable = false
        TextView.string = Message + "\n"

        let ScrollView = NSScrollView(frame: Window.contentView?.bounds ?? .zero)
        ScrollView.autoresizingMask = [.width, .height]
        ScrollView.borderType = .noBorder
        ScrollView.hasVerticalScroller = true
        ScrollView.documentView = TextView
        Window.contentView = ScrollView
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        guard !title.isEmpty else { return }
        window?.title = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        HostLogger.Write("process exited with status \(exitCode.map(String.init) ?? "unknown")")
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}

let Application = NSApplication.shared
let Delegate = AppDelegate()
Application.delegate = Delegate
Application.setActivationPolicy(.regular)
Application.run()
