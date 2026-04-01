import Foundation

enum LLMError: Error {
    case invalidURL
    case noAPIKey
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case encodingError(Error)
    case rateLimited
    case modelNotAvailable
}

struct LLMMessage: Codable {
    let role: String
    let content: String
}

struct LLMRequest: Codable {
    let model: String
    let messages: [LLMMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

struct LLMChoice: Codable {
    let message: LLMMessage
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

struct LLMResponse: Codable {
    let choices: [LLMChoice]
}

struct LLMSuggestedAction: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let actionType: String
    let template: String
    let confidence: Double
    let reason: String
}

// Separate struct for JSON decoding
private struct LLMSuggestedActionDTO: Codable {
    let name: String
    let description: String
    let actionType: String
    let template: String
    let confidence: Double
    let reason: String
}

@MainActor
final class LLMService {
    static let shared = LLMService()
    
    private let baseURL = "https://router.huggingface.co/v1/chat/completions"
    private let defaultModel = "LiquidAI/LFM2.5-350M"
    
    private init() {}
    
    func generateActionSuggestions(
        clipboardContext: ClipboardContext,
        apiKey: String,
        model: String? = nil
    ) async throws -> [LLMSuggestedAction] {
        // Check if local LLM should be used
        let useLocal = UserDefaults.standard.bool(forKey: "useLocalLLM")
        if useLocal {
            return try await LocalLLMService.shared.suggestActions(clipboardContext: clipboardContext)
        }
        
        guard !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }
        
        let prompt = buildPrompt(for: clipboardContext)
        let messages = [
            LLMMessage(role: "system", content: systemPrompt),
            LLMMessage(role: "user", content: prompt)
        ]
        
        let request = LLMRequest(
            model: model ?? defaultModel,
            messages: messages,
            temperature: 0.3,
            maxTokens: 800,
            stream: false
        )
        
        let response = try await makeRequest(request: request, apiKey: apiKey)
        return try parseSuggestions(from: response)
    }
    
    func summarizeText(_ text: String) async throws -> String {
        // Check if local LLM should be used
        let useLocal = UserDefaults.standard.bool(forKey: "useLocalLLM")
        if useLocal {
            // Ensure model is loaded
            if !LocalLLMService.shared.isReady && !LocalLLMService.shared.isLoading {
                await LocalLLMService.shared.loadModel()
            }
            return try await LocalLLMService.shared.summarize(text)
        }
        
        // Get API key from settings
        let apiKey = UserDefaults.standard.string(forKey: "llmApiKey") ?? ""
        guard !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }
        
        let model = UserDefaults.standard.string(forKey: "llmModel") ?? defaultModel
        
        let messages = [
            LLMMessage(role: "system", content: summarizeSystemPrompt),
            LLMMessage(role: "user", content: "Please summarize the following content:\n\n\(text)")
        ]
        
        let request = LLMRequest(
            model: model,
            messages: messages,
            temperature: 0.3,
            maxTokens: 500,
            stream: false
        )
        
        let response = try await makeRequest(request: request, apiKey: apiKey)
        return response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No summary generated."
    }
    
    private let summarizeSystemPrompt = """
    You are a professional summarization assistant. Your task is to summarize content with a professional, objective tone.
    
    Structure your response exactly as follows:
    
    **Executive Summary:**
    [2 concise sentences capturing the main point]
    
    **Key Takeaways:**
    • [First key point]
    • [Second key point]
    • [Third key point]
    • [Fourth key point]
    • [Fifth key point]
    
    **Next Steps:**
    [Actionable recommendations based on the content, or state "No specific next steps identified" if not applicable]
    
    Guidelines:
    - Use professional, objective language
    - Be concise but comprehensive
    - Focus on actionable insights
    - Maintain the original context and meaning
    """
    
    private func makeRequest(request: LLMRequest, apiKey: String) async throws -> LLMResponse {
        guard let url = URL(string: baseURL) else {
            throw LLMError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw LLMError.encodingError(error)
        }
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw LLMError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw LLMError.noAPIKey
        case 429:
            throw LLMError.rateLimited
        case 503, 504:
            throw LLMError.modelNotAvailable
        default:
            throw LLMError.invalidResponse
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(LLMResponse.self, from: data)
        } catch {
            throw LLMError.decodingError(error)
        }
    }
    
    private func buildPrompt(for context: ClipboardContext) -> String {
        let snapshot = context.snapshot
        var prompt = "Clipboard content:\n"
        
        // Content type
        prompt += "Type: \(snapshot.kind)\n"
        
        // Plain text content (truncated if too long)
        if let text = snapshot.plainText {
            let truncatedText = text.count > 500 ? String(text.prefix(500)) + "..." : text
            prompt += "Text: \(truncatedText)\n"
        }
        
        // URL if present
        if let url = snapshot.url {
            prompt += "URL: \(url.absoluteString)\n"
        }
        
        // File URLs
        if let fileURLs = snapshot.fileURLs {
            prompt += "Files: \(fileURLs.map { $0.lastPathComponent }.joined(separator: ", "))\n"
        }
        
        // Detected entity
        if snapshot.detectedEntity != .none {
            prompt += "Detected as: \(snapshot.detectedEntity.displayName)\n"
        }
        
        // Source app
        let sourceContext = context.sourceAppContext
        switch sourceContext {
        case .browser:
            prompt += "Source: Browser\n"
        case .ide:
            prompt += "Source: Code Editor\n"
        case .terminal:
            prompt += "Source: Terminal\n"
        case .other:
            prompt += "Source: Other app\n"
        }
        
        prompt += "\nBased on this clipboard content, suggest 2-3 useful actions the user might want to take."
        prompt += "\n\nRespond ONLY with a JSON array in this exact format:"
        prompt += "\n["
        prompt += "\n  {"
        prompt += "\n    \"name\": \"Action Name\","
        prompt += "\n    \"description\": \"Brief description\","
        prompt += "\n    \"actionType\": \"openURL|shellCommand|openApp|copyToClipboard\","
        prompt += "\n    \"template\": \"template with {text} or {text:encoded} variables\","
        prompt += "\n    \"confidence\": 0.95,"
        prompt += "\n    \"reason\": \"Why this action is relevant\""
        prompt += "\n  }"
        prompt += "\n]"
        
        return prompt
    }
    
    private let systemPrompt = """
    You are an intelligent assistant that suggests useful actions based on clipboard content.
    
    Available action types:
    - openURL: Opens a URL (e.g., search, maps, email)
    - shellCommand: Runs a shell command (e.g., ping, decode base64)
    - openApp: Opens an app with pasted text (e.g., ChatGPT, Claude)
    - copyToClipboard: Copies processed text back to clipboard
    
    Template variables:
    - {text}: The clipboard text content
    - {text:encoded}: URL-encoded text
    - {text:trimmed}: Trimmed text
    - {path}: File path (if files are copied)
    
    Guidelines:
    1. Suggest only genuinely useful actions
    2. Use appropriate template variables
    3. Provide confidence scores (0.0-1.0)
    4. Explain why each action is relevant
    5. Keep descriptions concise
    6. Return valid JSON only
    """
    
    private func parseSuggestions(from response: LLMResponse) throws -> [LLMSuggestedAction] {
        guard let firstChoice = response.choices.first else {
            return []
        }
        
        let content = firstChoice.message.content
        
        // Extract JSON from the response (it might be wrapped in markdown code blocks)
        let jsonString: String
        if let startRange = content.range(of: "["),
           let endRange = content.range(of: "]", range: startRange.upperBound..<content.endIndex) {
            jsonString = String(content[startRange.lowerBound...endRange.upperBound])
        } else {
            jsonString = content
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            let dtos = try decoder.decode([LLMSuggestedActionDTO].self, from: data)
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
            Logger.error("Failed to parse LLM suggestions: \(error)", category: .general)
            return []
        }
    }
}
