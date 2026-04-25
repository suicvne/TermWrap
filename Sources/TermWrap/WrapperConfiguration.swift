import AppKit
import Foundation

struct WrapperConfiguration: Codable, Equatable {
    var AppName: String
    var CommandPath: String
    var CommandArguments: String
    var IconPath: String
    var OutputDirectoryPath: String
    var FontName: String
    var FontSize: Double
    var EnablesSandbox: Bool

    static var Fresh: WrapperConfiguration {
        let DocumentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let Font = NSFont.userFixedPitchFont(ofSize: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        return WrapperConfiguration(
            AppName: "",
            CommandPath: "",
            CommandArguments: "",
            IconPath: "",
            OutputDirectoryPath: DocumentsURL?.path ?? NSHomeDirectory(),
            FontName: Font.fontName,
            FontSize: Double(Font.pointSize),
            EnablesSandbox: false
        )
    }
}

