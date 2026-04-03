import Foundation

struct SuggestedAction: Identifiable {
    typealias ResultCallback = (_ text: String, _ isInClipboard: Bool) -> Void
    typealias StreamCallback = (_ token: String) -> Void

    let id = UUID()
    let skillId: String
    let title: String
    let subtitle: String?
    let systemImage: String
    /// Returns an optional cancel closure. Non-LLM actions return nil.
    let perform: (
        _ completion: @escaping ResultCallback,
        _ onToken: @escaping StreamCallback
    ) -> (() -> Void)?
}
