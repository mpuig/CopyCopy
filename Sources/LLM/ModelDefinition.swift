import Foundation

struct ModelDefinition: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let repo: String
    let filename: String
    let sizeLabel: String
    let chatTemplate: ChatTemplate
    let defaultTemperature: Float

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(filename)")!
    }

    var localPath: URL {
        HFCache.resolvedPath(for: self) ?? HFCache.legacyPath(for: self)
    }

    var isDownloaded: Bool {
        HFCache.isDownloaded(self)
    }

    static let all: [ModelDefinition] = [
        ModelDefinition(
            id: "lfm-1.2b",
            name: "LFM 2.5 1.2B Instruct",
            repo: "LiquidAI/LFM2.5-1.2B-Instruct-GGUF",
            filename: "LFM2.5-1.2B-Instruct-Q8_0.gguf",
            sizeLabel: "~1.2 GB",
            chatTemplate: .lfm,
            defaultTemperature: 0.3
        ),
        ModelDefinition(
            id: "lfm-350m",
            name: "LFM 2.5 350M",
            repo: "LiquidAI/LFM2.5-350M-GGUF",
            filename: "LFM2.5-350M-Q8_0.gguf",
            sizeLabel: "~350 MB",
            chatTemplate: .lfm,
            defaultTemperature: 0.3
        ),
        ModelDefinition(
            id: "gemma-4-e2b",
            name: "Gemma 4 E2B Instruct",
            repo: "ggml-org/gemma-4-E2B-it-GGUF",
            filename: "gemma-4-e2b-it-Q8_0.gguf",
            sizeLabel: "~5 GB",
            chatTemplate: .gemma,
            defaultTemperature: 1.0
        ),
        ModelDefinition(
            id: "qwen-0.8b",
            name: "Qwen 3.5 0.8B",
            repo: "unsloth/Qwen3.5-0.8B-GGUF",
            filename: "Qwen3.5-0.8B-Q8_0.gguf",
            sizeLabel: "~0.8 GB",
            chatTemplate: .qwen,
            defaultTemperature: 0.7
        ),
        ModelDefinition(
            id: "qwen-2b",
            name: "Qwen 3.5 2B",
            repo: "unsloth/Qwen3.5-2B-GGUF",
            filename: "Qwen3.5-2B-Q8_0.gguf",
            sizeLabel: "~2 GB",
            chatTemplate: .qwen,
            defaultTemperature: 0.7
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
    case qwen

    func format(systemPrompt: String, userPrompt: String) -> String {
        switch self {
        case .lfm, .chatml:
            return "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(userPrompt)<|im_end|>\n<|im_start|>assistant\n"
        case .qwen:
            return "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(userPrompt)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
        case .gemma:
            return "<|turn>system\n\(systemPrompt)<turn|>\n<|turn>user\n\(userPrompt)<turn|>\n<|turn>model\n"
        }
    }
}
