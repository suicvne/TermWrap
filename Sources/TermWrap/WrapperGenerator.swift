import AppKit
import Foundation

enum WrapperGenerationError: LocalizedError {
    case MissingAppName
    case MissingCommand
    case MissingOutputDirectory
    case CommandDoesNotExist(String)
    case OutputDirectoryDoesNotExist(String)
    case MissingBundledTermWrapHost
    case MissingTemplate(String)
    case MissingTool(String)
    case CodeSignFailed(String)

    var errorDescription: String? {
        switch self {
        case .MissingAppName:
            return "Enter an application name."
        case .MissingCommand:
            return "Choose a terminal application to wrap."
        case .MissingOutputDirectory:
            return "Choose where the wrapper application should be saved."
        case .CommandDoesNotExist(let Path):
            return "The command does not exist at \(Path)."
        case .OutputDirectoryDoesNotExist(let Path):
            return "The output directory does not exist at \(Path)."
        case .MissingBundledTermWrapHost:
            return "The bundled TermWrapHost executable is missing. Rebuild TermWrap before generating wrappers."
        case .MissingTemplate(let Name):
            return "The bundled template is missing: \(Name). Rebuild TermWrap before generating wrappers."
        case .MissingTool(let Tool):
            return "The required system tool is missing: \(Tool)."
        case .CodeSignFailed(let Output):
            return "The wrapper application was created, but sandbox signing failed.\n\n\(Output)"
        }
    }
}

struct WrapperGenerationResult {
    let AppURL: URL
}

struct WrapperGenerator {
    func Generate(Configuration: WrapperConfiguration, Progress: @escaping @MainActor (String) -> Void) async throws -> WrapperGenerationResult {
        try await Task.detached(priority: .userInitiated) {
            let Validated = try Validate(Configuration)
            await Progress("Preparing bundle")

            let FileManager = FileManager.default
            let AppURL = Validated.OutputDirectoryURL.appendingPathComponent("\(Validated.AppName).app", isDirectory: true)
            let StagingURL = Validated.OutputDirectoryURL.appendingPathComponent(".\(Validated.AppName)-\(UUID().uuidString).app", isDirectory: true)
            let ContentsURL = StagingURL.appendingPathComponent("Contents", isDirectory: true)
            let MacOSURL = ContentsURL.appendingPathComponent("MacOS", isDirectory: true)
            let ResourcesURL = ContentsURL.appendingPathComponent("Resources", isDirectory: true)

            do {
                try FileManager.createDirectory(at: MacOSURL, withIntermediateDirectories: true)
                try FileManager.createDirectory(at: ResourcesURL, withIntermediateDirectories: true)

                let ExecutableName = "TermWrapHost"
                let BundleIdentifier = "local.terminal-wrapper.\(SanitizeBundleIdentifier(Validated.AppName))"
                let IconFileName = try PrepareIconIfNeeded(from: Validated.IconURL, to: ResourcesURL)
                let InfoPlist = try RenderInfoPlist(
                    AppName: Validated.AppName,
                    BundleIdentifier: BundleIdentifier,
                    ExecutableName: ExecutableName,
                    IconFileName: IconFileName
                )
                try InfoPlist.write(to: ContentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

                await Progress("Writing wrapper configuration")
                try WriteHostConfiguration(Configuration: Validated, to: ResourcesURL.appendingPathComponent("WrapperConfiguration.plist"))

                await Progress("Installing wrapper runtime")
                let ExecutableURL = MacOSURL.appendingPathComponent(ExecutableName)
                try InstallTermWrapHost(to: ExecutableURL)
                try InstallSwiftTermResourceBundle(to: ResourcesURL)

                if Validated.EnablesSandbox {
                    await Progress("Signing sandboxed app")
                    try WriteEntitlements(to: ContentsURL.appendingPathComponent("Entitlements.plist"))
                    guard FileManager.isExecutableFile(atPath: "/usr/bin/codesign") else {
                        throw WrapperGenerationError.MissingTool("/usr/bin/codesign")
                    }
                    let SignOutput = RunProcess(
                        LaunchPath: "/usr/bin/codesign",
                        Arguments: [
                            "--force",
                            "--sign", "-",
                            "--entitlements", ContentsURL.appendingPathComponent("Entitlements.plist").path,
                            StagingURL.path
                        ]
                    )

                    guard SignOutput.ExitCode == 0 else {
                        throw WrapperGenerationError.CodeSignFailed(SignOutput.CombinedOutput)
                    }
                }

                try ReplaceExistingBundle(at: AppURL, with: StagingURL)
            } catch {
                try? FileManager.removeItem(at: StagingURL)
                throw error
            }

            await Progress("Finished")
            return WrapperGenerationResult(AppURL: AppURL)
        }.value
    }
}

private struct HostConfigurationPlist: Encodable {
    let CommandPath: String
    let CommandArguments: [String]
    let FontName: String
    let FontSize: Double
}

private struct ValidatedWrapperConfiguration {
    let AppName: String
    let CommandPath: String
    let CommandArguments: String
    let IconURL: URL?
    let OutputDirectoryURL: URL
    let FontName: String
    let FontSize: Double
    let EnablesSandbox: Bool
}

private struct ProcessOutput {
    let ExitCode: Int32
    let CombinedOutput: String
}

private func Validate(_ Configuration: WrapperConfiguration) throws -> ValidatedWrapperConfiguration {
    let AppName = Configuration.AppName.trimmingCharacters(in: .whitespacesAndNewlines)
    let CommandPath = Configuration.CommandPath.trimmingCharacters(in: .whitespacesAndNewlines)
    let OutputDirectoryPath = Configuration.OutputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !AppName.isEmpty else { throw WrapperGenerationError.MissingAppName }
    guard !CommandPath.isEmpty else { throw WrapperGenerationError.MissingCommand }
    guard !OutputDirectoryPath.isEmpty else { throw WrapperGenerationError.MissingOutputDirectory }

    var IsDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: CommandPath, isDirectory: &IsDirectory), !IsDirectory.boolValue else {
        throw WrapperGenerationError.CommandDoesNotExist(CommandPath)
    }

    guard FileManager.default.fileExists(atPath: OutputDirectoryPath, isDirectory: &IsDirectory), IsDirectory.boolValue else {
        throw WrapperGenerationError.OutputDirectoryDoesNotExist(OutputDirectoryPath)
    }

    let OutputDirectoryURL = URL(fileURLWithPath: OutputDirectoryPath, isDirectory: true)
    let IconURL = Configuration.IconPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(fileURLWithPath: Configuration.IconPath)

    return ValidatedWrapperConfiguration(
        AppName: AppName,
        CommandPath: CommandPath,
        CommandArguments: Configuration.CommandArguments,
        IconURL: IconURL,
        OutputDirectoryURL: OutputDirectoryURL,
        FontName: Configuration.FontName,
        FontSize: Configuration.FontSize,
        EnablesSandbox: Configuration.EnablesSandbox
    )
}

private func PrepareIconIfNeeded(from IconURL: URL?, to ResourcesURL: URL) throws -> String? {
    guard let IconURL else { return nil }

    if IconURL.pathExtension.lowercased() == "icns" {
        let DestinationName = "AppIcon.icns"
        let DestinationURL = ResourcesURL.appendingPathComponent(DestinationName)
        try FileManager.default.copyItem(at: IconURL, to: DestinationURL)
        return DestinationName
    }

    let DestinationName = "AppIcon.icns"
    let DestinationURL = ResourcesURL.appendingPathComponent(DestinationName)
    let IconSetURL = ResourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: IconSetURL, withIntermediateDirectories: true)
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sips") else {
        throw WrapperGenerationError.MissingTool("/usr/bin/sips")
    }
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/iconutil") else {
        throw WrapperGenerationError.MissingTool("/usr/bin/iconutil")
    }

    let Sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png")
    ]

    for (Size, FileName) in Sizes {
        let OutputURL = IconSetURL.appendingPathComponent(FileName)
        _ = RunProcess(
            LaunchPath: "/usr/bin/sips",
            Arguments: [
                "-z", "\(Size)", "\(Size)",
                IconURL.path,
                "--out", OutputURL.path
            ]
        )
    }

    let IconOutput = RunProcess(
        LaunchPath: "/usr/bin/iconutil",
        Arguments: [
            "-c", "icns",
            IconSetURL.path,
            "-o", DestinationURL.path
        ]
    )

    try? FileManager.default.removeItem(at: IconSetURL)

    guard IconOutput.ExitCode == 0 else {
        try FileManager.default.copyItem(at: IconURL, to: ResourcesURL.appendingPathComponent("OriginalIcon.\(IconURL.pathExtension)"))
        return nil
    }

    return DestinationName
}

private func RenderInfoPlist(AppName: String, BundleIdentifier: String, ExecutableName: String, IconFileName: String?) throws -> String {
    let IconKey = IconFileName.map { "<key>CFBundleIconFile</key>\n\t<string>\($0.XmlEscaped)</string>" } ?? ""
    return try LoadTemplate(named: "Info.plist")
        .replacingOccurrences(of: "{{APP_NAME}}", with: AppName.XmlEscaped)
        .replacingOccurrences(of: "{{EXECUTABLE_NAME}}", with: ExecutableName.XmlEscaped)
        .replacingOccurrences(of: "{{ICON_PLIST_ENTRY}}", with: IconKey)
        .replacingOccurrences(of: "{{BUNDLE_IDENTIFIER}}", with: BundleIdentifier.XmlEscaped)
}

private func ParseArguments(_ RawValue: String) -> [String] {
    var Results: [String] = []
    var Current = ""
    var Quote: Character?
    var IsEscaped = false

    for CharacterValue in RawValue {
        if IsEscaped {
            Current.append(CharacterValue)
            IsEscaped = false
            continue
        }

        if CharacterValue == "\\" {
            IsEscaped = true
            continue
        }

        if let ActiveQuote = Quote {
            if CharacterValue == ActiveQuote {
                Quote = nil
            } else {
                Current.append(CharacterValue)
            }
            continue
        }

        if CharacterValue == "\"" || CharacterValue == "'" {
            Quote = CharacterValue
            continue
        }

        if CharacterValue.isWhitespace {
            if !Current.isEmpty {
                Results.append(Current)
                Current = ""
            }
        } else {
            Current.append(CharacterValue)
        }
    }

    if !Current.isEmpty {
        Results.append(Current)
    }

    return Results
}

private func RunProcess(LaunchPath: String, Arguments: [String]) -> ProcessOutput {
    let ProcessValue = Process()
    let PipeValue = Pipe()
    ProcessValue.executableURL = URL(fileURLWithPath: LaunchPath)
    ProcessValue.arguments = Arguments
    ProcessValue.standardOutput = PipeValue
    ProcessValue.standardError = PipeValue

    do {
        try ProcessValue.run()
        ProcessValue.waitUntilExit()
    } catch {
        return ProcessOutput(ExitCode: 1, CombinedOutput: error.localizedDescription)
    }

    let DataValue = PipeValue.fileHandleForReading.readDataToEndOfFile()
    let Output = String(data: DataValue, encoding: .utf8) ?? ""
    return ProcessOutput(ExitCode: ProcessValue.terminationStatus, CombinedOutput: Output)
}

private func InstallTermWrapHost(to DestinationURL: URL) throws {
    let FileManager = FileManager.default
    let CandidateURLs = [
        Bundle.main.resourceURL?.appendingPathComponent("TermWrapHost"),
        Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("TermWrapHost")
    ].compactMap { $0 }

    guard let SourceURL = CandidateURLs.first(where: { FileManager.isExecutableFile(atPath: $0.path) }) else {
        throw WrapperGenerationError.MissingBundledTermWrapHost
    }

    try FileManager.copyItem(at: SourceURL, to: DestinationURL)
    try FileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: DestinationURL.path)
}

private func InstallSwiftTermResourceBundle(to ResourcesURL: URL) throws {
    let FileManager = FileManager.default
    let BundleName = "SwiftTerm_SwiftTerm.bundle"
    let CandidateURLs = [
        Bundle.main.bundleURL.appendingPathComponent(BundleName, isDirectory: true),
        Bundle.main.resourceURL?.appendingPathComponent(BundleName, isDirectory: true),
        Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(BundleName, isDirectory: true)
    ].compactMap { $0 }

    guard let SourceURL = CandidateURLs.first(where: { FileManager.fileExists(atPath: $0.path) }) else {
        return
    }

    let DestinationURL = ResourcesURL.appendingPathComponent(BundleName, isDirectory: true)
    try FileManager.copyItem(at: SourceURL, to: DestinationURL)
}

private func ReplaceExistingBundle(at AppURL: URL, with StagingURL: URL) throws {
    let FileManager = FileManager.default

    guard FileManager.fileExists(atPath: AppURL.path) else {
        try FileManager.moveItem(at: StagingURL, to: AppURL)
        return
    }

    let ReplacementURL = AppURL.deletingLastPathComponent().appendingPathComponent(".\(AppURL.deletingPathExtension().lastPathComponent)-replaced-\(UUID().uuidString).app", isDirectory: true)
    try FileManager.moveItem(at: AppURL, to: ReplacementURL)

    do {
        try FileManager.moveItem(at: StagingURL, to: AppURL)
        try? FileManager.removeItem(at: ReplacementURL)
    } catch {
        try? FileManager.moveItem(at: ReplacementURL, to: AppURL)
        throw error
    }
}

private func WriteHostConfiguration(Configuration: ValidatedWrapperConfiguration, to URLValue: URL) throws {
    let Plist = HostConfigurationPlist(
        CommandPath: Configuration.CommandPath,
        CommandArguments: ParseArguments(Configuration.CommandArguments),
        FontName: Configuration.FontName,
        FontSize: Configuration.FontSize
    )
    let DataValue = try PropertyListEncoder.Xml.encode(Plist)
    try DataValue.write(to: URLValue, options: .atomic)
}

private func LoadTemplate(named Name: String) throws -> String {
    let CandidateURLs = [
        Bundle.main.resourceURL?.appendingPathComponent("Templates/\(Name).template"),
        Bundle.module.url(forResource: Name, withExtension: "template", subdirectory: "Templates")
    ].compactMap { $0 }

    guard let URL = CandidateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
        throw WrapperGenerationError.MissingTemplate("\(Name).template")
    }

    return try String(contentsOf: URL, encoding: .utf8)
}

private func WriteEntitlements(to URLValue: URL) throws {
    let Text = try LoadTemplate(named: "Entitlements.plist")
    try Text.write(to: URLValue, atomically: true, encoding: .utf8)
}

private func SanitizeBundleIdentifier(_ Value: String) -> String {
    let Allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
    let Scalars = Value.lowercased().unicodeScalars.map { Allowed.contains($0) ? Character($0) : "-" }
    return String(Scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

private extension PropertyListEncoder {
    static var Xml: PropertyListEncoder {
        let Encoder = PropertyListEncoder()
        Encoder.outputFormat = .xml
        return Encoder
    }
}

private extension String {
    var XmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

}
