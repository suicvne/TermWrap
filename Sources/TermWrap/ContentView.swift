import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var ViewModel = WrapperMakerViewModel()
    @ObservedObject private var Coordinator = SharedAppState.Shared

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HeaderView()
                Divider()
                Form {
                    Section("Application") {
                        TextField("Name", text: $ViewModel.Configuration.AppName)
                        PathRow(
                            Title: "Command",
                            Placeholder: "/usr/bin/vim",
                            Path: $ViewModel.Configuration.CommandPath,
                            ActionTitle: "Choose",
                            Action: ViewModel.ChooseCommand
                        )
                        TextField("Arguments", text: $ViewModel.Configuration.CommandArguments)
                    }

                    Section("Appearance") {
                        PathRow(
                            Title: "Icon",
                            Placeholder: "Optional .icns, .png, or .jpg",
                            Path: $ViewModel.Configuration.IconPath,
                            ActionTitle: "Choose",
                            Action: ViewModel.ChooseIcon
                        )
                        HStack {
                            Text("Terminal Font")
                            Spacer()
                            Text(ViewModel.FontDisplayName)
                                .foregroundStyle(.secondary)
                            Button("Choose Font", action: ViewModel.ChooseFont)
                        }
                    }

                    Section("Output") {
                        PathRow(
                            Title: "Save To",
                            Placeholder: "~/Documents",
                            Path: $ViewModel.Configuration.OutputDirectoryPath,
                            ActionTitle: "Choose",
                            Action: ViewModel.ChooseOutputDirectory
                        )
                        Toggle("Enable App Sandbox for generated wrapper", isOn: $ViewModel.Configuration.EnablesSandbox)
                    }
                }
                .formStyle(.grouped)
                .disabled(Coordinator.IsGenerating)

                Divider()

                HStack {
                    Button("Load Configuration", action: ViewModel.LoadConfiguration)
                        .disabled(Coordinator.IsGenerating)
                    Button("Save Configuration", action: ViewModel.SaveConfiguration)
                        .disabled(Coordinator.IsGenerating)

                    Spacer()

                    if !ViewModel.StatusText.isEmpty {
                        Text(ViewModel.StatusText)
                            .foregroundStyle(ViewModel.StatusIsError ? .red : .secondary)
                            .lineLimit(1)
                    }

                    Button {
                        Task { await ViewModel.Generate() }
                    } label: {
                        Label("Generate App", systemImage: "hammer")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(Coordinator.IsGenerating)
                }
                .padding()
            }

            if Coordinator.IsGenerating {
                Rectangle()
                    .fill(.black.opacity(0.08))
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(ViewModel.ProgressText)
                        .font(.headline)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 12)
            }
        }
    }
}

private struct HeaderView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text("TermWrap")
                    .font(.title2.weight(.semibold))
                Text("Create local macOS apps for command-line tools.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}

private struct PathRow: View {
    let Title: String
    let Placeholder: String
    @Binding var Path: String
    let ActionTitle: String
    let Action: () -> Void

    var body: some View {
        HStack {
            Text(Title)
            TextField(Placeholder, text: $Path)
                .textFieldStyle(.roundedBorder)
            Button(ActionTitle, action: Action)
        }
    }
}

@MainActor
final class WrapperMakerViewModel: NSObject, ObservableObject, NSFontChanging {
    @Published var Configuration = WrapperConfiguration.Fresh
    @Published var ProgressText = ""
    @Published var StatusText = ""
    @Published var StatusIsError = false

    private static let MinimumProgressDuration: TimeInterval = 2.5
    private let Generator = WrapperGenerator()

    var FontDisplayName: String {
        "\(Configuration.FontName) \(Int(Configuration.FontSize)) pt"
    }

    func ChooseCommand() {
        let Panel = NSOpenPanel()
        Panel.title = "Choose Terminal Application"
        Panel.canChooseFiles = true
        Panel.canChooseDirectories = false
        Panel.allowsMultipleSelection = false
        Panel.treatsFilePackagesAsDirectories = true
        Panel.directoryURL = URL(fileURLWithPath: "/usr/bin", isDirectory: true)

        if Panel.runModal() == .OK, let URL = Panel.url {
            Configuration.CommandPath = URL.path
            if Configuration.AppName.isEmpty {
                Configuration.AppName = URL.deletingPathExtension().lastPathComponent
            }
        }
    }

    func ChooseIcon() {
        let Panel = NSOpenPanel()
        Panel.title = "Choose Icon"
        Panel.allowedContentTypes = [.icns, .png, .jpeg]
        Panel.canChooseFiles = true
        Panel.canChooseDirectories = false
        Panel.allowsMultipleSelection = false

        if Panel.runModal() == .OK, let URL = Panel.url {
            Configuration.IconPath = URL.path
        }
    }

    func ChooseOutputDirectory() {
        let Panel = NSOpenPanel()
        Panel.title = "Choose Save Location"
        Panel.canChooseFiles = false
        Panel.canChooseDirectories = true
        Panel.allowsMultipleSelection = false
        Panel.canCreateDirectories = true

        if Panel.runModal() == .OK, let URL = Panel.url {
            Configuration.OutputDirectoryPath = URL.path
        }
    }

    func ChooseFont() {
        let Manager = NSFontManager.shared
        Manager.target = self
        Manager.setSelectedFont(CurrentFont, isMultiple: false)
        Manager.orderFrontFontPanel(nil)
    }

    func changeFont(_ Sender: NSFontManager?) {
        guard let Sender else { return }
        let Font = Sender.convert(CurrentFont)
        Configuration.FontName = Font.fontName
        Configuration.FontSize = Double(Font.pointSize)
    }

    func SaveConfiguration() {
        do {
            try ConfigurationStore.Save(Configuration)
            SetStatus("Configuration saved.", IsError: false)
        } catch {
            SetStatus(error.localizedDescription, IsError: true)
        }
    }

    func LoadConfiguration() {
        do {
            if let Loaded = try ConfigurationStore.Load() {
                Configuration = Loaded
                SetStatus("Configuration loaded.", IsError: false)
            }
        } catch {
            SetStatus(error.localizedDescription, IsError: true)
        }
    }

    func Generate() async {
        let StartedAt = Date()
        SharedAppState.Shared.IsGenerating = true
        StatusText = ""
        StatusIsError = false
        ProgressText = "Starting"

        do {
            let Result = try await Generator.Generate(Configuration: Configuration) { [weak self] Text in
                self?.ProgressText = Text
            }
            SetStatus("Created \(Result.AppURL.lastPathComponent)", IsError: false)
        } catch {
            SetStatus(error.localizedDescription, IsError: true)
        }

        let RemainingDuration = Self.MinimumProgressDuration - Date().timeIntervalSince(StartedAt)
        if RemainingDuration > 0 {
            try? await Task.sleep(nanoseconds: UInt64(RemainingDuration * 1_000_000_000))
        }
        ProgressText = ""
        SharedAppState.Shared.IsGenerating = false
    }

    private var CurrentFont: NSFont {
        NSFont(name: Configuration.FontName, size: Configuration.FontSize) ?? NSFont.userFixedPitchFont(ofSize: Configuration.FontSize) ?? .monospacedSystemFont(ofSize: Configuration.FontSize, weight: .regular)
    }

    private func SetStatus(_ Text: String, IsError: Bool) {
        StatusText = Text
        StatusIsError = IsError
    }
}

private extension UTType {
    static let icns = UTType(filenameExtension: "icns")!
}
