import Foundation
import Combine

@MainActor
final class LLMActionSuggester: ObservableObject {
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var lastSuggestions: [LLMSuggestedAction] = []
    
    private var cancellables = Set<AnyCancellable>()
    private let service = LLMService.shared
    
    func suggestActions(
        for context: ClipboardContext,
        apiKey: String,
        enabled: Bool
    ) async -> [LLMSuggestedAction] {
        guard enabled, !apiKey.isEmpty else {
            return []
        }
        
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        do {
            let suggestions = try await service.generateActionSuggestions(
                clipboardContext: context,
                apiKey: apiKey
            )
            lastSuggestions = suggestions
            Logger.info("LLM generated \(suggestions.count) suggestions", category: .general)
            return suggestions
        } catch LLMError.noAPIKey {
            lastError = "HuggingFace API key not configured"
            Logger.error("LLM suggestion failed: No API key", category: .general)
        } catch LLMError.rateLimited {
            lastError = "Rate limited. Please try again later."
            Logger.error("LLM suggestion failed: Rate limited", category: .general)
        } catch LLMError.modelNotAvailable {
            lastError = "Model temporarily unavailable"
            Logger.error("LLM suggestion failed: Model unavailable", category: .general)
        } catch LLMError.networkError(let error) {
            lastError = "Network error: \(error.localizedDescription)"
            Logger.error("LLM suggestion failed: Network error - \(error)", category: .general)
        } catch {
            lastError = "Failed to generate suggestions: \(error.localizedDescription)"
            Logger.error("LLM suggestion failed: \(error)", category: .general)
        }
        
        return []
    }
    
    func convertToSuggestedActions(
        llmSuggestions: [LLMSuggestedAction],
        context: ClipboardContext
    ) -> [SuggestedAction] {
        return llmSuggestions.map { suggestion in
            let actionType = ActionType(rawValue: suggestion.actionType) ?? .openURL
            
            // Create a CustomAction from the LLM suggestion
            let customAction = CustomAction(
                id: UUID(),
                name: "🤖 \(suggestion.name)",
                actionType: actionType,
                template: suggestion.template,
                contentFilter: .any,
                sourceFilter: .any,
                entityFilter: .any,
                systemImage: iconFor(actionType: actionType),
                isEnabled: true,
                isBuiltIn: false
            )
            
            return SuggestedAction(
                title: customAction.name,
                subtitle: suggestion.reason,
                systemImage: customAction.systemImage
            ) {
                // Execute the action
                Task { @MainActor in
                    let store = CustomActionsStore()
                    store.execute(customAction, with: context)
                }
            }
        }
    }
    
    private func iconFor(actionType: ActionType) -> String {
        switch actionType {
        case .openURL:
            return "link"
        case .shellCommand:
            return "terminal"
        case .openApp:
            return "app"
        case .copyToClipboard:
            return "doc.on.clipboard"
        default:
            return "sparkles"
        }
    }
}
