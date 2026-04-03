import Foundation

enum LLMError: Error, LocalizedError {
    case invalidURL
    case noAPIKey
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case encodingError(Error)
    case rateLimited
    case modelNotAvailable

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .noAPIKey: return "No API key configured"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .invalidResponse: return "Invalid response from server"
        case .decodingError: return "Could not parse server response"
        case .encodingError: return "Could not encode request"
        case .rateLimited: return "Rate limited — try again later"
        case .modelNotAvailable: return "AI model not loaded. Download and load a model in Settings."
        }
    }
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

@MainActor
final class LLMService {
    static let shared = LLMService()
    
    private let baseURL = "https://router.huggingface.co/v1/chat/completions"
    private let defaultModel = "LiquidAI/LFM2.5-1.2B-Instruct"
    
    private init() {}
    
    func summarizeText(
        _ text: String,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        if !LocalLLMService.shared.isReady && LocalLLMService.shared.isLoading {
            await LocalLLMService.shared.waitUntilReady()
        }
        if !LocalLLMService.shared.isReady && !LocalLLMService.shared.isLoading {
            await LocalLLMService.shared.loadModel()
        }
        if LocalLLMService.shared.isReady {
            return try await LocalLLMService.shared.summarize(text, onToken: onToken)
        }

        // Fallback to remote API if local model unavailable
        let useLocal = UserDefaults.standard.object(forKey: "useLocalLLM") as? Bool ?? true
        if useLocal {
            throw LLMError.modelNotAvailable
        }
        
        // Get API key from settings
        let apiKey = UserDefaults.standard.string(forKey: "llmApiKey") ?? ""
        guard !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }
        
        let model = UserDefaults.standard.string(forKey: "llmModel") ?? defaultModel
        
        let messages = [
            LLMMessage(role: "system", content: summarizeSystemPrompt),
            LLMMessage(role: "user", content: text)
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
    
    private let summarizeSystemPrompt = "Summarize into 3-5 bullet points. Keep the main point and key details. Cut filler and repetition. If very short, use one sentence. No headings or commentary."
    
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
    
}
