import Foundation

@MainActor
final class SharedAppState: ObservableObject {
    static let Shared = SharedAppState()

    @Published var IsGenerating = false

    private init() {}
}
