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

@MainActor
final class LLMService {
    static let shared = LLMService()
    
    private let baseURL = "https://router.huggingface.co/v1/chat/completions"
    private let defaultModel = "LiquidAI/LFM2.5-350M"
    
    private init() {}
    
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
    
    private let summarizeSystemPrompt = """
    Summarize the clipboard text into a short, clear summary. Preserve the main point and the most important supporting details. Omit repetition, filler, and minor examples. Use a neutral professional tone. Default to 3-5 bullet points. If the source is very short, return a single sentence. Do not add headings, commentary, or information not present in the source.
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
    
}
