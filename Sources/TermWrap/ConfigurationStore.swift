import AppKit
import Foundation

enum ConfigurationStore {
    static let FileExtension = "terminalwrapperconfig"

    static func Save(_ Configuration: WrapperConfiguration) throws {
        let Panel = NSSavePanel()
        Panel.allowedContentTypes = [.json]
        Panel.canCreateDirectories = true
        Panel.nameFieldStringValue = SuggestedConfigurationFileName(for: Configuration)
        Panel.title = "Save Configuration"

        guard Panel.runModal() == .OK, let URL = Panel.url else {
            return
        }

        let Data = try JSONEncoder.PrettyPrinted.encode(Configuration)
        try Data.write(to: URL, options: .atomic)
    }

    static func Load() throws -> WrapperConfiguration? {
        let Panel = NSOpenPanel()
        Panel.allowedContentTypes = [.json]
        Panel.allowsMultipleSelection = false
        Panel.canChooseDirectories = false
        Panel.canChooseFiles = true
        Panel.title = "Load Configuration"

        guard Panel.runModal() == .OK, let URL = Panel.url else {
            return nil
        }

        let Data = try Data(contentsOf: URL)
        return try JSONDecoder().decode(WrapperConfiguration.self, from: Data)
    }

    private static func SuggestedConfigurationFileName(for Configuration: WrapperConfiguration) -> String {
        let BaseName = Configuration.AppName.isEmpty ? "Wrapper" : Configuration.AppName
        return "\(BaseName).\(FileExtension).json"
    }
}

private extension JSONEncoder {
    static var PrettyPrinted: JSONEncoder {
        let Encoder = JSONEncoder()
        Encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return Encoder
    }
}

