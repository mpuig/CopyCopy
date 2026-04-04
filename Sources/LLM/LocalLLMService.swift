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
            try await downloadToHFCache(definition: definition)
            Logger.info("Downloaded model: \(definition.name)", category: .general)
        } catch {
            Logger.error("Failed to download \(definition.name): \(error)", category: .general)
        }

        downloadingModels.removeValue(forKey: definition.id)
    }

    private func ensureModelDownloaded(_ definition: ModelDefinition) async throws -> URL {
        if let path = HFCache.resolvedPath(for: definition) {
            return path
        }

        loadingProgress = "Downloading \(definition.name)..."
        downloadingModels[definition.id] = 0

        try await downloadToHFCache(definition: definition)
        downloadingModels.removeValue(forKey: definition.id)

        guard let path = HFCache.resolvedPath(for: definition) else {
            throw LocalLLMError.modelNotLoaded
        }
        return path
    }

    private func downloadToHFCache(definition: ModelDefinition) async throws {
        let modelId = definition.id

        // Fetch metadata (SHA256, commit) via HEAD request
        loadingProgress = "Resolving \(definition.name)..."
        let metadata = try? await HFCache.fetchMetadata(for: definition)

        let downloader = ModelDownloader { [weak self] progress in
            Task { @MainActor in
                self?.downloadingModels[modelId] = progress
                self?.downloadProgress = progress
                let percent = Int(progress * 100)
                self?.loadingProgress = "Downloading: \(percent)%"
            }
        }

        if let metadata {
            // HF cache layout: download to blobs, symlink from snapshots
            let (blobPath, snapshotLink) = try HFCache.prepareCache(
                for: definition, sha256: metadata.sha256, commit: metadata.commit
            )

            if !FileManager.default.fileExists(atPath: blobPath.path) {
                try await downloader.download(from: definition.downloadURL, to: blobPath)
            }

            try HFCache.createSymlink(from: snapshotLink, to: blobPath)
        } else {
            // Fallback to legacy flat directory if HEAD request fails
            let cacheDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".copycopy/models")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let localPath = cacheDir.appendingPathComponent(definition.filename)

            try await downloader.download(from: definition.downloadURL, to: localPath)
        }
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
            systemPrompt: "Summarize as 3-5 bullet points starting with \"- \". Include only facts from the text. If very short, use one sentence. No headings or commentary. Output only the summary.",
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
    private static var backendInitialized = false

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let templateString: String?
    private let fallbackTemplate: ChatTemplate

    init(model: OpaquePointer, context: OpaquePointer, templateString: String?, fallbackTemplate: ChatTemplate) {
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        self.templateString = templateString
        self.fallbackTemplate = fallbackTemplate
    }

    deinit {
        llama_model_free(model)
        llama_free(context)
    }

    static func create(path: String, template: ChatTemplate) throws -> LlamaContext {
        // Initialize backend once
        if !backendInitialized {
            llama_backend_init()
            backendInitialized = true
        }

        // Model params: offload all layers to Metal GPU
        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #else
        modelParams.n_gpu_layers = 999
        #endif

        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw LocalLLMError.modelNotLoaded
        }

        // Read chat template from GGUF metadata
        let ggufTemplate = readChatTemplate(from: model)

        // Context params: dynamic size, flash attention, tuned threads
        let trainCtx = llama_model_n_ctx_train(model)
        let ctxSize = min(UInt32(trainCtx), 4096)

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = max(ctxSize, 2048)
        let nThreads = Int32(max(1, min(ProcessInfo.processInfo.processorCount, 8)))
        ctxParams.n_threads = nThreads
        ctxParams.n_threads_batch = nThreads

        guard let context = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            throw LocalLLMError.modelNotLoaded
        }

        return LlamaContext(model: model, context: context, templateString: ggufTemplate, fallbackTemplate: template)
    }

    private static func readChatTemplate(from model: OpaquePointer) -> String? {
        guard let ptr = llama_model_chat_template(model, nil) else { return nil }
        return String(cString: ptr)
    }

    private func formatPrompt(systemPrompt: String, userPrompt: String) -> String {
        // Try GGUF template via llama_chat_apply_template
        if let ggufFormatted = applyGGUFTemplate(systemPrompt: systemPrompt, userPrompt: userPrompt) {
            return ggufFormatted
        }
        // Fallback to hardcoded template
        return fallbackTemplate.format(systemPrompt: systemPrompt, userPrompt: userPrompt)
    }

    private func applyGGUFTemplate(systemPrompt: String, userPrompt: String) -> String? {
        guard let templateString else { return nil }

        var messages = [
            llama_chat_message(role: strdup("system"), content: strdup(systemPrompt)),
            llama_chat_message(role: strdup("user"), content: strdup(userPrompt)),
        ]
        defer {
            for msg in messages {
                free(UnsafeMutablePointer(mutating: msg.role))
                free(UnsafeMutablePointer(mutating: msg.content))
            }
        }

        let bufSize: Int32 = 8192
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: Int(bufSize))
        defer { buf.deallocate() }

        let len = templateString.withCString { tmpl in
            llama_chat_apply_template(tmpl, &messages, messages.count, true, buf, bufSize)
        }

        guard len > 0, len < bufSize else { return nil }
        return String(cString: buf)
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        temperature: Float,
        maxTokens: Int32,
        onToken: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let formatted = formatPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
        let tokens = tokenize(text: formatted, addBos: true)

        // Clear KV cache
        llama_memory_clear(llama_get_memory(context), true)

        // Build sampler chain: top_k → top_p → min_p → temp → dist
        let sparams = llama_sampler_chain_default_params()
        let sampler = llama_sampler_chain_init(sparams)!
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(64))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.05, 1))
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

        let count = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(nTokens), addBos, true)
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
