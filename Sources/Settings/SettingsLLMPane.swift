import SwiftUI

@MainActor
struct SettingsLLMPane: View {
    @ObservedObject var settings: AppSettings
    @State private var showingHelp = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                
                Divider()
                
                enableSection
                
                if settings.llmEnabled {
                    Divider()
                    
                    apiKeySection
                    
                    Divider()
                    
                    modelSection
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingHelp) {
            LLMHelpView()
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Features")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Enable AI-powered features like smart action suggestions and content summarization")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Button("How to get an API Key →") {
                showingHelp = true
            }
            .buttonStyle(.link)
        }
    }
    
    private var enableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable AI Features", isOn: $settings.llmEnabled)
                .toggleStyle(.switch)
                .font(.headline)
            
            if !settings.llmEnabled {
                Text("When enabled, CopyCopy can use AI to suggest relevant actions based on your clipboard content and summarize text with a professional format.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("API Key", systemImage: "key")
                .font(.headline)
            
            SecureField("Enter your HuggingFace API key", text: $settings.llmApiKey)
                .textFieldStyle(.roundedBorder)
            
            if settings.llmApiKey.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("API key required for AI features to work")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("API key configured")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            
            Text("Your API key is stored securely on your device and is only used to communicate with HuggingFace's AI service.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Model", systemImage: "cpu")
                .font(.headline)
            
            Picker("Model", selection: $settings.llmModel) {
                Text("LiquidAI/LFM2.5-350M (Recommended)")
                    .tag("LiquidAI/LFM2.5-350M")
                Text("Other HuggingFace Model")
                    .tag("custom")
            }
            .pickerStyle(.radioGroup)
            
            if settings.llmModel == "custom" {
                TextField("Enter model ID (e.g., meta-llama/Llama-2-7b-chat-hf)", text: Binding(
                    get: { settings.llmModel == "custom" ? "" : settings.llmModel },
                    set: { newValue in
                        if !newValue.isEmpty {
                            settings.llmModel = newValue
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            Text("The default model is optimized for fast responses and works well for action suggestions and summarization.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct LLMHelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Getting Started with AI Features")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    helpSection(
                        icon: "1.circle.fill",
                        title: "Create a HuggingFace Account",
                        description: "Visit huggingface.co and sign up for a free account."
                    )
                    
                    helpSection(
                        icon: "2.circle.fill",
                        title: "Generate an API Token",
                        description: "Go to Settings → Access Tokens → New Token. Create a read token with 'Make calls to Inference Providers' permission."
                    )
                    
                    helpSection(
                        icon: "3.circle.fill",
                        title: "Enter Your Token",
                        description: "Copy the token and paste it in the API Key field in CopyCopy Settings."
                    )
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's included in the free tier?")
                            .font(.headline)
                        
                        Text("• 1,000 requests per day\n• Access to most open-source models\n• No credit card required")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    Link("Open HuggingFace Settings →", destination: URL(string: "https://huggingface.co/settings/tokens")!)
                        .font(.body)
                }
                .padding()
            }
        }
        .padding()
        .frame(width: 500, height: 500)
    }
    
    private func helpSection(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
