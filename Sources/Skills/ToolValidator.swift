import Foundation

enum ToolValidator {
    static let allowedURLSchemes: Set<String> = [
        "http",
        "https",
        "mailto",
        "tel",
        "sms",
        "facetime",
        "maps",
        "dict",
        "calshow",
        "addressbook",
        "x-web-search",
    ]

    static let allowedApps: [String: String] = [
        "chatgpt": "com.openai.chat",
        "claude": "com.anthropic.claudefordesktop",
        "cursor": "com.todesktop.230313mzl4w4u92",
        "copilot": "com.github.copilot.chat",
        "safari": "com.apple.Safari",
    ]

    static func validateExecuteFunction(_ name: String) throws -> ExecuteFunction {
        guard let function = ExecuteFunction(rawValue: name) else {
            throw ValidationError.unsupportedExecuteFunction(name)
        }
        return function
    }

    static func validateJSONObjectParameters(_ parameters: ToolParameters) throws {
        guard parameters.type == "object" else {
            throw ValidationError.invalidParameters("Tool parameters must use type 'object'")
        }

        for key in parameters.required where parameters.properties[key] == nil {
            throw ValidationError.invalidParameters("Missing required property definition for '\(key)'")
        }
    }

    static func validateOpenableURL(_ urlString: String) throws -> URL {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased() else {
            throw ValidationError.invalidURL(urlString)
        }
        guard allowedURLSchemes.contains(scheme) else {
            throw ValidationError.disallowedURLScheme(scheme)
        }
        return url
    }

    static func validateHostname(_ rawValue: String) throws -> String {
        let host = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw ValidationError.invalidHostname(rawValue)
        }

        if isValidIPv4(host) || host == "localhost" {
            return host
        }

        let labels = host.split(separator: ".")
        guard labels.count >= 2 else {
            throw ValidationError.invalidHostname(rawValue)
        }

        for label in labels {
            guard !label.isEmpty, label.count <= 63 else {
                throw ValidationError.invalidHostname(rawValue)
            }
            guard label.first?.isLetter == true || label.first?.isNumber == true else {
                throw ValidationError.invalidHostname(rawValue)
            }
            guard label.last?.isLetter == true || label.last?.isNumber == true else {
                throw ValidationError.invalidHostname(rawValue)
            }
            guard label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
                throw ValidationError.invalidHostname(rawValue)
            }
        }

        return host
    }

    static func validateJSON(_ text: String) throws {
        guard let data = text.data(using: .utf8) else {
            throw ValidationError.invalidJSON
        }

        _ = try JSONSerialization.jsonObject(with: data)
    }

    static func resolveExistingPath(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError.invalidPath(rawValue)
        }

        let expanded = NSString(string: trimmed).expandingTildeInPath
        let candidate: URL
        if let parsed = URL(string: expanded), parsed.isFileURL {
            candidate = parsed
        } else {
            candidate = URL(fileURLWithPath: expanded)
        }

        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            throw ValidationError.pathNotFound(resolved.path)
        }
        return resolved
    }

    static func allowlistedBundleIdentifier(for appName: String) throws -> String {
        let normalized = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let bundleIdentifier = allowedApps[normalized] {
            return bundleIdentifier
        }

        let compact = normalized.replacingOccurrences(of: " ", with: "")
        if let bundleIdentifier = allowedApps[compact] {
            return bundleIdentifier
        }

        throw ValidationError.disallowedApp(appName)
    }

    private static func isValidIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".")
        guard octets.count == 4 else { return false }

        for octet in octets {
            guard let value = Int(octet), (0...255).contains(value) else {
                return false
            }
        }

        return true
    }
}

enum ValidationError: LocalizedError {
    case unsupportedExecuteFunction(String)
    case invalidParameters(String)
    case invalidURL(String)
    case disallowedURLScheme(String)
    case invalidHostname(String)
    case invalidJSON
    case invalidPath(String)
    case pathNotFound(String)
    case disallowedApp(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedExecuteFunction(name):
            return "Unsupported execute function '\(name)'"
        case let .invalidParameters(message):
            return message
        case let .invalidURL(value):
            return "Invalid URL '\(value)'"
        case let .disallowedURLScheme(scheme):
            return "Disallowed URL scheme '\(scheme)'"
        case let .invalidHostname(value):
            return "Invalid hostname '\(value)'"
        case .invalidJSON:
            return "Clipboard text is not valid JSON"
        case let .invalidPath(value):
            return "Invalid path '\(value)'"
        case let .pathNotFound(path):
            return "Path does not exist: \(path)"
        case let .disallowedApp(app):
            return "App '\(app)' is not on the allowlist"
        }
    }
}
