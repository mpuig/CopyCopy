import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon
import SwiftUI

@MainActor
final class LocalLLMService: ObservableObject {
    static let shared = LocalLLMService()
    
    @Published var isLoading = false
    @Published var isReady = false
    @Published var loadingProgress: String = ""
    @Published var downloadProgress: Double = 0
    @Published var errorMessage: String?
    
    private var modelContainer: ModelContainer?
    private let modelId = "mlx-community/LFM2.5-350M-8bit"
    
    private var modelConfiguration: ModelConfiguration {
        ModelConfiguration(id: modelId)
    }
    
    private init() {}
    
    func loadModel() async {
        guard !isReady && !isLoading else { return }
        
        isLoading = true
        loadingProgress = "Loading model..."
        errorMessage = nil
        downloadProgress = 0
        
        do {
            // Setup cache directory in app's Application Support
            let cacheDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("CopyCopy/Models")
            if let cacheDir = cacheDir {
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            }
            
            let hub = HubApi(downloadBase: cacheDir)
            
            // Download and load the model
            let container = try await LLMModelFactory.shared.loadContainer(
                hub: hub,
                configuration: modelConfiguration
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
            isReady = true
            loadingProgress = "Model ready ✓"
            Logger.info("Local LLM model loaded successfully", category: .general)
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
        maxTokens: Int = 500
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
        
        // Use perform to get a context and generate
        return try await container.perform { (context: ModelContext) async throws -> String in
            // Process user input to get LMInput
            let lmInput = try await context.processor.prepare(input: userInput)
            
            // Generate with streaming
            let stream = try MLXLMCommon.generate(
                input: lmInput,
                parameters: parameters,
                context: context
            )
            
            var output = ""
            for await generation in stream {
                if let text = generation.chunk {
                    output += text
                }
            }
            
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    func summarize(_ text: String) async throws -> String {
        let truncatedText = text.count > 3000 
            ? String(text.prefix(3000)) + "\n\n[Content truncated]"
            : text

        return try await generate(
            prompt: truncatedText,
            systemPrompt: "Summarize the clipboard text into a short, clear summary. Preserve the main point and the most important supporting details. Omit repetition, filler, and minor examples. Use a neutral professional tone. Default to 3-5 bullet points. If the source is very short, return a single sentence. Do not add headings, commentary, or information not present in the source.",
            temperature: 0.3,
            maxTokens: 500
        )
    }
    
}

enum LocalLLMError: Error {
    case modelNotLoaded
    case generationFailed(Error)
    case invalidResponse
}
