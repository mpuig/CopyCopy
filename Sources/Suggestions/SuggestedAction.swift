import Foundation

struct SuggestedAction: Identifiable {
    typealias ResultCallback = (_ text: String, _ isInClipboard: Bool) -> Void

    let id = UUID()
    let title: String
    let subtitle: String?
    let systemImage: String
    let perform: (@escaping ResultCallback) -> Void
}

