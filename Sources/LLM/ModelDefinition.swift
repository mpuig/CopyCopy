import Foundation

struct ModelDefinition: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let repo: String
    let filename: String
    let sizeLabel: String
    let chatTemplate: ChatTemplate

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(filename)")!
    }

    var localPath: URL {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/copycopy/models")
        return cacheDir.appendingPathComponent(filename)
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localPath.path)
    }

    static let all: [ModelDefinition] = [
        ModelDefinition(
            id: "lfm-1.2b",
            name: "LFM 2.5 1.2B Instruct",
            repo: "LiquidAI/LFM2.5-1.2B-Instruct-GGUF",
            filename: "LFM2.5-1.2B-Instruct-Q8_0.gguf",
            sizeLabel: "~1.2 GB",
            chatTemplate: .lfm
        ),
        ModelDefinition(
            id: "lfm-350m",
            name: "LFM 2.5 350M",
            repo: "LiquidAI/LFM2.5-350M-GGUF",
            filename: "LFM2.5-350M-Q8_0.gguf",
            sizeLabel: "~350 MB",
            chatTemplate: .lfm
        ),
        ModelDefinition(
            id: "gemma-4-e2b",
            name: "Gemma 4 E2B Instruct",
            repo: "ggml-org/gemma-4-E2B-it-GGUF",
            filename: "gemma-4-e2b-it-Q8_0.gguf",
            sizeLabel: "~2 GB",
            chatTemplate: .gemma
        ),
        ModelDefinition(
            id: "gemma-4-e4b",
            name: "Gemma 4 E4B Instruct",
            repo: "ggml-org/gemma-4-E4B-it-GGUF",
            filename: "gemma-4-e4b-it-Q8_0.gguf",
            sizeLabel: "~4 GB",
            chatTemplate: .gemma
        ),
    ]

    static let defaultId = "lfm-1.2b"

    static func find(_ id: String) -> ModelDefinition? {
        all.first { $0.id == id }
    }
}

enum ChatTemplate: Equatable, Hashable {
    case lfm
    case gemma
    case chatml

    func format(systemPrompt: String, userPrompt: String) -> String {
        switch self {
        case .lfm, .chatml:
            return "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(userPrompt)<|im_end|>\n<|im_start|>assistant\n"
        case .gemma:
            return "<|turn>system\n\(systemPrompt)<turn|>\n<|turn>user\n\(userPrompt)<turn|>\n<|turn>model\n"
        }
    }
}
