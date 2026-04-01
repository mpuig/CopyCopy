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
        
        let prompt = """
        Please summarize the following text. Use a professional, objective tone. Structure the response with an Executive Summary (2 sentences), followed by a bulleted list of the top 5 key takeaways, and finally a 'Next Steps' section if applicable.
        
        Text to summarize:
        \(truncatedText)
        """
        
        return try await generate(
            prompt: prompt,
            systemPrompt: "You are a professional summarization assistant. Create structured, professional summaries.",
            temperature: 0.3,
            maxTokens: 800
        )
    }
    
    func suggestActions(clipboardContext: ClipboardContext) async throws -> [LLMSuggestedAction] {
        let snapshot = clipboardContext.snapshot
        
        var contextDescription = ""
        if let text = snapshot.plainText {
            let truncated = text.count > 800 ? String(text.prefix(800)) + "..." : text
            contextDescription += "Text: \(truncated)\n"
        }
        if snapshot.detectedEntity != .none {
            contextDescription += "Type: \(snapshot.detectedEntity.displayName)\n"
        }
        
        let prompt = """
        Based on this clipboard content, suggest 2-3 useful actions:
        
        \(contextDescription)
        
        Respond with ONLY a JSON array in this format:
        [
          {
            "name": "Action Name",
            "description": "Brief description",
            "actionType": "openURL|shellCommand|openApp|copyToClipboard",
            "template": "template with {text} variables",
            "confidence": 0.9,
            "reason": "Why this is useful"
          }
        ]
        """
        
        let response = try await generate(
            prompt: prompt,
            systemPrompt: "You are an intelligent assistant that suggests useful actions based on clipboard content.",
            temperature: 0.3,
            maxTokens: 600
        )
        
        // Parse JSON response
        guard let jsonStart = response.range(of: "[")?.lowerBound,
              let jsonEnd = response.range(of: "]", range: jsonStart..<response.endIndex)?.upperBound else {
            return []
        }
        
        let jsonString = String(response[jsonStart..<jsonEnd])
        guard let data = jsonString.data(using: .utf8) else {
            return []
        }
        
        do {
            let dtos = try JSONDecoder().decode([LLMSuggestedActionDTO].self, from: data)
            return dtos.map { dto in
                LLMSuggestedAction(
                    name: dto.name,
                    description: dto.description,
                    actionType: dto.actionType,
                    template: dto.template,
                    confidence: dto.confidence,
                    reason: dto.reason
                )
            }
        } catch {
            Logger.error("Failed to parse local LLM suggestions: \(error)", category: .general)
            return []
        }
    }
}

enum LocalLLMError: Error {
    case modelNotLoaded
    case generationFailed(Error)
    case invalidResponse
}

// DTO for JSON parsing
private struct LLMSuggestedActionDTO: Codable {
    let name: String
    let description: String
    let actionType: String
    let template: String
    let confidence: Double
    let reason: String
}
