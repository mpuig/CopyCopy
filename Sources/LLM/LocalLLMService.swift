import Foundation
import llama
import SwiftUI

@MainActor
final class LocalLLMService: ObservableObject {
    static let shared = LocalLLMService()

    @Published var isLoading = false
    @Published var isReady = false
    @Published var loadingProgress: String = ""
    @Published var downloadProgress: Double = 0
    @Published var errorMessage: String?
    @Published var downloadingModels: [String: Double] = [:]

    private var llamaContext: LlamaContext?
    private(set) var loadedModelId: String?

    private init() {}

    func waitUntilReady() async {
        while isLoading && !isReady {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    var currentModelId: String {
        UserDefaults.standard.string(forKey: "llmModel") ?? ModelDefinition.defaultId
    }

    var currentModelDefinition: ModelDefinition? {
        ModelDefinition.find(currentModelId)
    }

    func loadModel() async {
        guard let definition = currentModelDefinition else {
            errorMessage = "Unknown model: \(currentModelId)"
            return
        }

        if isReady, loadedModelId == definition.id { return }

        // Unload previous model
        if loadedModelId != nil, loadedModelId != definition.id {
            llamaContext = nil
            loadedModelId = nil
            isReady = false
        }

        let alreadyDownloaded = definition.isDownloaded
        isLoading = true
        isReady = false
        loadingProgress = alreadyDownloaded ? "Loading model..." : "Preparing model..."
        errorMessage = nil
        downloadProgress = 0

        do {
            let localPath = alreadyDownloaded ? definition.localPath : try await ensureModelDownloaded(definition)
            loadingProgress = "Loading model..."

            let context = try await Task.detached(priority: .userInitiated) {
                try LlamaContext.create(path: localPath.path, template: definition.chatTemplate)
            }.value

            llamaContext = context
            loadedModelId = definition.id
            isReady = true
            loadingProgress = "Model ready"
            Logger.info("Loaded model: \(definition.name)", category: .general)
        } catch {
            isReady = false
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            Logger.error("Failed to load model: \(error)", category: .general)
        }

        isLoading = false
    }

    /// Download a model without loading it. Can be called for multiple models concurrently.
    func downloadModel(_ definition: ModelDefinition) async {
        guard !definition.isDownloaded else { return }
        guard downloadingModels[definition.id] == nil else { return }

        downloadingModels[definition.id] = 0

        do {
            let localPath = try await downloadGGUF(definition: definition)
            Logger.info("Downloaded model: \(definition.name) → \(localPath.path)", category: .general)
        } catch {
            Logger.error("Failed to download \(definition.name): \(error)", category: .general)
        }

        downloadingModels.removeValue(forKey: definition.id)
    }

    private func ensureModelDownloaded(_ definition: ModelDefinition) async throws -> URL {
        if definition.isDownloaded {
            return definition.localPath
        }

        loadingProgress = "Downloading \(definition.name)..."
        downloadingModels[definition.id] = 0

        let localPath = try await downloadGGUF(definition: definition)
        downloadingModels.removeValue(forKey: definition.id)
        return localPath
    }

    private func downloadGGUF(definition: ModelDefinition) async throws -> URL {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/copycopy/models")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let localPath = cacheDir.appendingPathComponent(definition.filename)
        let modelId = definition.id

        let tempURL: URL = try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadingModels[modelId] = progress
                        self?.downloadProgress = progress
                        let percent = Int(progress * 100)
                        self?.loadingProgress = "Downloading: \(percent)%"
                    }
                },
                onComplete: { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: LocalLLMError.modelNotLoaded)
                    }
                }
            )

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            session.downloadTask(with: definition.downloadURL).resume()
        }

        try FileManager.default.moveItem(at: tempURL, to: localPath)
        return localPath
    }

    func generate(
        prompt: String,
        systemPrompt: String = "You are a helpful assistant.",
        temperature: Float = 0.3,
        maxTokens: Int = 500,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard let context = llamaContext else {
            throw LocalLLMError.modelNotLoaded
        }

        return try await Task.detached(priority: .userInitiated) {
            try await context.generate(
                systemPrompt: systemPrompt,
                userPrompt: prompt,
                temperature: temperature,
                maxTokens: Int32(maxTokens),
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
            systemPrompt: """
            You are a summarization assistant. Your task:
            1. Read the text carefully
            2. Identify the main point and 2-4 supporting details
            3. Write a concise summary as bullet points

            Rules:
            - Use 3-5 short bullet points (one line each)
            - Start each bullet with "- "
            - Include only facts from the text, never invent
            - If the text is very short (under 50 words), write one sentence instead
            - No headings, no commentary, no introduction
            - Output only the summary
            """,
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
            systemPrompt: "Clean up the chat transcript. Keep all authors, timestamps, and message content. Remove navigation UI, search bars, badges, composer text, buttons, and app chrome. Do not summarize or rewrite. Return only the cleaned transcript.",
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
            Classify using only these labels: ["codeSnippet","markdown","emailDraft","slackDraft","shellCommand","logOutput","sql","foreignLanguage"].
            Return a JSON array. Prefer [] when unsure. JSON only.
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
}

// MARK: - LlamaContext (Swift actor wrapping llama.cpp C API)

actor LlamaContext {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let chatTemplate: ChatTemplate

    init(model: OpaquePointer, context: OpaquePointer, template: ChatTemplate) {
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        self.chatTemplate = template
    }

    deinit {
        llama_model_free(model)
        llama_free(context)
    }

    static func create(path: String, template: ChatTemplate) throws -> LlamaContext {
        llama_backend_init()

        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #endif

        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw LocalLLMError.modelNotLoaded
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 2048
        let nThreads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
        ctxParams.n_threads = nThreads
        ctxParams.n_threads_batch = nThreads

        guard let context = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            throw LocalLLMError.modelNotLoaded
        }

        return LlamaContext(model: model, context: context, template: template)
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        temperature: Float,
        maxTokens: Int32,
        onToken: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let formatted = chatTemplate.format(systemPrompt: systemPrompt, userPrompt: userPrompt)
        let tokens = tokenize(text: formatted, addBos: true)

        // Clear KV cache
        llama_memory_clear(llama_get_memory(context), true)

        // Build sampler chain: top_k → top_p → temp → dist
        let sparams = llama_sampler_chain_default_params()
        let sampler = llama_sampler_chain_init(sparams)!
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(64))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        defer { llama_sampler_free(sampler) }

        // Initial prompt processing
        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }

        for (i, token) in tokens.enumerated() {
            batch.token[i] = token
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 0
        }
        batch.n_tokens = Int32(tokens.count)
        batch.logits[Int(batch.n_tokens) - 1] = 1

        guard llama_decode(context, batch) == 0 else {
            throw LocalLLMError.generationFailed(NSError(domain: "llama", code: -1, userInfo: [NSLocalizedDescriptionKey: "Initial decode failed"]))
        }

        // Token generation loop
        var output = ""
        var nCur = batch.n_tokens
        var invalidCChars: [CChar] = []

        for _ in 0..<maxTokens {
            if Task.isCancelled { break }

            let newTokenId = llama_sampler_sample(sampler, context, batch.n_tokens - 1)

            if llama_vocab_is_eog(vocab, newTokenId) { break }

            let piece = tokenToPiece(token: newTokenId)
            invalidCChars.append(contentsOf: piece)

            if let str = String(validatingUTF8: invalidCChars + [0]) {
                invalidCChars.removeAll()
                output += str
                onToken?(str)
            }

            // Prepare next batch
            batch.n_tokens = 0
            batch.token[0] = newTokenId
            batch.pos[0] = nCur
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            batch.n_tokens = 1

            nCur += 1

            guard llama_decode(context, batch) == 0 else { break }
        }

        // Flush remaining bytes
        if !invalidCChars.isEmpty {
            let remaining = String(cString: invalidCChars + [0])
            output += remaining
            onToken?(remaining)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenize(text: String, addBos: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let nTokens = utf8Count + (addBos ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: nTokens)
        defer { tokens.deallocate() }

        let count = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(nTokens), addBos, false)
        return (0..<Int(count)).map { tokens[$0] }
    }

    private func tokenToPiece(token: llama_token) -> [CChar] {
        let bufSize = 8
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: bufSize)
        buf.initialize(repeating: 0, count: bufSize)
        defer { buf.deallocate() }

        let n = llama_token_to_piece(vocab, token, buf, Int32(bufSize), 0, false)
        if n < 0 {
            let newBuf = UnsafeMutablePointer<CChar>.allocate(capacity: Int(-n))
            newBuf.initialize(repeating: 0, count: Int(-n))
            defer { newBuf.deallocate() }
            let n2 = llama_token_to_piece(vocab, token, newBuf, -n, 0, false)
            return Array(UnsafeBufferPointer(start: newBuf, count: Int(n2)))
        }
        return Array(UnsafeBufferPointer(start: buf, count: Int(n)))
    }
}

// MARK: - Download Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: (Double) -> Void
    let onComplete: (URL?, Error?) -> Void

    init(
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (URL?, Error?) -> Void
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Copy to a temp location that won't be cleaned up when this method returns
        let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gguf")
        try? FileManager.default.copyItem(at: location, to: tempCopy)
        onComplete(tempCopy, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onComplete(nil, error)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}

// MARK: - Errors

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
