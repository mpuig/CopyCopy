import Foundation

struct ModelDefinition: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let repo: String
    let filename: String
    let sizeLabel: String
    let chatTemplate: ChatTemplate
    let defaultTemperature: Float
    let batchSize: UInt32
    let ubatchSize: UInt32
    let flashAttention: Bool
    let kvQuantized: Bool

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
            id: "gemma-4-e2b",
            name: "Gemma 4 E2B",
            repo: "unsloth/gemma-4-E2B-it-qat-GGUF",
            filename: "gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf",
            sizeLabel: "~2.4 GB",
            chatTemplate: .gemma,
            defaultTemperature: 0.3,
            batchSize: 2048,
            ubatchSize: 512,
            flashAttention: true,
            kvQuantized: false
        ),
    ]

    static let defaultId = "gemma-4-e2b"

    static func find(_ id: String) -> ModelDefinition? {
        all.first { $0.id == id }
    }
}

enum ChatTemplate: Equatable, Hashable {
    case gemma

    func format(systemPrompt: String, userPrompt: String) -> String {
        "<|turn>system\n\(systemPrompt)<turn|>\n<|turn>user\n\(userPrompt)<turn|>\n<|turn>model\n"
    }
}
