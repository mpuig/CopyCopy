import Foundation

enum ExecuteFunction: String, CaseIterable {
    case openURL
    case openURLTemplate
    case openApp
    case openFile
    case revealInFinder
    case saveImage
    case saveTempFile
    case copyToClipboard
    case formatJSON
    case decodeBase64
    case decodeURL
    case stripANSI
    case htmlToMarkdown
    case revealPath
    case openInTerminal
    case ping
    case llmPrompt
    case llmAgent
    case summarize
    case openStaticURL

    var displayName: String {
        switch self {
        case .openURL: return "Open URL"
        case .openURLTemplate: return "Open URL"
        case .openApp: return "Open App"
        case .openFile: return "Open File"
        case .revealInFinder: return "Reveal in Finder"
        case .saveImage: return "Save Image"
        case .saveTempFile: return "Save Temp File"
        case .copyToClipboard: return "Copy to Clipboard"
        case .formatJSON: return "Format JSON"
        case .decodeBase64: return "Decode Base64"
        case .decodeURL: return "Decode URL"
        case .stripANSI: return "Strip ANSI"
        case .htmlToMarkdown: return "HTML to Markdown"
        case .revealPath: return "Reveal Path"
        case .openInTerminal: return "Open in Terminal"
        case .ping: return "Ping Host"
        case .llmPrompt: return "AI"
        case .llmAgent: return "AI Agent"
        case .summarize: return "Summarize"
        case .openStaticURL: return "Open URL"
        }
    }
}
