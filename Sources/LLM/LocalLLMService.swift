import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon
import SwiftUI

@MainActor
final class LocalLLMService: ObservableObject {
    static let shared = LocalLLMService()

    static let defaultModelId = "LiquidAI/LFM2.5-1.2B-Instruct-MLX-8bit"

    @Published var isLoading = false
    @Published var isReady = false
    @Published var loadingProgress: String = ""
    @Published var downloadProgress: Double = 0
    @Published var errorMessage: String?

    private var modelContainer: ModelContainer?
    private(set) var loadedModelId: String?

    private init() {}

    func waitUntilReady() async {
        while isLoading && !isReady {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    var currentModelId: String {
        UserDefaults.standard.string(forKey: "llmModel") ?? Self.defaultModelId
    }

    func loadModel() async {
        let modelId = currentModelId

        // If already loaded with the same model, skip
        if isReady, loadedModelId == modelId { return }
        guard !isLoading else { return }

        // Unload previous model if switching
        if loadedModelId != nil, loadedModelId != modelId {
            modelContainer = nil
            loadedModelId = nil
            isReady = false
        }

        isLoading = true
        loadingProgress = "Loading model..."
        errorMessage = nil
        downloadProgress = 0

        do {
            let configuration = ModelConfiguration(id: modelId)

            let container = try await LLMModelFactory.shared.loadContainer(
                hub: HubApi(),
                configuration: configuration
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress.fractionCompleted
                    let percent = Int(progress.fractionCompleted * 100)
                    if progress.fractionCompleted < 1.0 {
                        self?.loadingProgress = "Downloading: \(percent)%"
                    } else {
                        self?.loadingProgress = "Loading model..."
                    }
                }
            }

            modelContainer = container
            loadedModelId = modelId
            isReady = true
            loadingProgress = "Model ready"
            Logger.info("Local LLM model loaded: \(modelId)", category: .general)
        } catch {
            isReady = false
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            Logger.error("Failed to load local LLM: \(error)", category: .general)
        }

        isLoading = false
    }

    func generate(
        prompt: String,
        systemPrompt: String = "You are a helpful assistant.",
        temperature: Float = 0.3,
        maxTokens: Int = 500,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard let container = modelContainer else {
            throw LocalLLMError.modelNotLoaded
        }

        let messages: [Chat.Message] = [
            .system(systemPrompt),
            .user(prompt)
        ]

        let userInput = UserInput(prompt: .chat(messages))

        let parameters = GenerateParameters(
            maxTokens: maxTokens,
            temperature: temperature
        )

        return try await Task.detached(priority: .userInitiated) {
            try await Self.runGeneration(
                container: container,
                userInput: userInput,
                parameters: parameters,
                onToken: onToken
            )
        }.value
    }

    func summarize(
        _ text: String,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let truncatedText = text.count > 3000
            ? String(text.prefix(3000)) + "\n\n[Content truncated]"
            : text

        return try await generate(
            prompt: truncatedText,
            systemPrompt: "Summarize into 3-5 bullet points. Keep the main point and key details. Cut filler and repetition. If very short, use one sentence. No headings or commentary.",
            temperature: 0.3,
            maxTokens: 500,
            onToken: onToken
        )
    }

    func cleanChatTranscript(_ text: String) async throws -> String {
        let truncatedText = text.count > 5000
            ? String(text.prefix(5000)) + "\n\n[Content truncated]"
            : text

        return try await generate(
            prompt: truncatedText,
            systemPrompt: """
            Clean up the copied chat transcript.

            Keep:
            - all authors
            - all timestamps
            - all real message content

            Remove:
            - navigation UI
            - search bars
            - counts and badges
            - composer and footer text
            - buttons, labels, and app chrome
            - decorative standalone tokens that are not part of a real message

            Rules:
            - Do not summarize.
            - Do not rewrite.
            - Do not omit any real message content.
            - Preserve the original language.
            - Return only the cleaned chat transcript as plain text.
            """,
            temperature: 0.0,
            maxTokens: 1200
        )
    }

    func classifyTextEntities(_ text: String) async throws -> [DetectedEntityType] {
        let truncatedText = text.count > 2500
            ? String(text.prefix(2500)) + "\n\n[Content truncated]"
            : text

        let response = try await generate(
            prompt: truncatedText,
            systemPrompt: """
            Classify the clipboard text using only these labels when they apply:
            ["codeSnippet","markdown","emailDraft","slackDraft","shellCommand","logOutput","sql","foreignLanguage"].

            Rules:
            - Return a JSON array of zero or more labels from that exact list.
            - Do not invent labels.
            - Prefer [] when unsure.
            - "emailDraft" means the text reads like an email body or reply draft.
            - "slackDraft" means the text reads like a Slack or chat message draft.
            - "shellCommand" means the text is primarily a shell command or short shell script.
            - "logOutput" means the text is primarily logs, stack traces, or command output.
            - "sql" means the text is primarily SQL code or queries.
            - "codeSnippet" means the text is primarily source code.
            - "markdown" means the text is primarily Markdown content.
            - "foreignLanguage" means the dominant language is not English.
            Return JSON only.
            """,
            temperature: 0.0,
            maxTokens: 80
        )

        return Self.parseDetectedEntities(from: response)
    }

    nonisolated static func parseDetectedEntities(from response: String) -> [DetectedEntityType] {
        let candidate = extractJSONArray(from: response) ?? response
        guard let data = candidate.data(using: .utf8),
              let labels = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        var seen = Set<DetectedEntityType>()
        var result: [DetectedEntityType] = []

        for label in labels {
            guard let entity = DetectedEntityType(rawValue: label), entity != .none else { continue }
            if seen.insert(entity).inserted {
                result.append(entity)
            }
        }

        return result
    }

    private nonisolated static func extractJSONArray(from text: String) -> String? {
        guard let start = text.firstIndex(of: "["),
              let end = text[start...].lastIndex(of: "]") else {
            return nil
        }

        return String(text[start...end])
    }

    private nonisolated static func runGeneration(
        container: ModelContainer,
        userInput: UserInput,
        parameters: GenerateParameters,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await container.perform { (context: ModelContext) async throws -> String in
            let lmInput = try await context.processor.prepare(input: userInput)

            let stream = try MLXLMCommon.generate(
                input: lmInput,
                parameters: parameters,
                context: context
            )

            var output = ""
            for await generation in stream {
                if Task.isCancelled { break }
                if let text = generation.chunk {
                    output += text
                    onToken?(text)
                }
            }

            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

}

enum LocalLLMError: Error, LocalizedError {
    case modelNotLoaded
    case generationFailed(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "The AI model is not loaded"
        case .generationFailed(let error):
            return "AI generation failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "The AI model returned an invalid response"
        }
    }
}
