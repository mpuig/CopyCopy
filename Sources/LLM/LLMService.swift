import Foundation

@MainActor
final class LLMService {
    static let shared = LLMService()

    private init() {}

    func summarizeText(
        _ text: String,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await ensureModelReady()
        return try await LocalLLMService.shared.summarize(text, onToken: onToken)
    }

    private func ensureModelReady() async throws {
        if LocalLLMService.shared.isReady { return }
        if LocalLLMService.shared.isLoading {
            await LocalLLMService.shared.waitUntilReady()
        } else {
            await LocalLLMService.shared.loadModel()
        }
        guard LocalLLMService.shared.isReady else {
            throw LLMError.modelNotAvailable
        }
    }
}

enum LLMError: Error, LocalizedError {
    case modelNotAvailable

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "AI model not loaded. Download and load a model in Settings."
        }
    }
}
