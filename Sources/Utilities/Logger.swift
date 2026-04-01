import Foundation
import os.log

enum Logger {
    private static let subsystem = "com.copycopy.app"
    
    private static let generalLog = OSLog(subsystem: subsystem, category: "General")
    private static let clipboardLog = OSLog(subsystem: subsystem, category: "Clipboard")
    private static let actionsLog = OSLog(subsystem: subsystem, category: "Actions")
    private static let permissionsLog = OSLog(subsystem: subsystem, category: "Permissions")
    
    static func debug(_ message: String, category: LogCategory = .general) {
        #if DEBUG
        os_log("%{public}@", log: logFor(category), type: .debug, message)
        #endif
    }
    
    static func info(_ message: String, category: LogCategory = .general) {
        os_log("%{public}@", log: logFor(category), type: .info, message)
    }
    
    static func warning(_ message: String, category: LogCategory = .general) {
        os_log("%{public}@", log: logFor(category), type: .default, message)
    }
    
    static func error(_ message: String, category: LogCategory = .general) {
        os_log("%{public}@", log: logFor(category), type: .error, message)
    }
    
    private static func logFor(_ category: LogCategory) -> OSLog {
        switch category {
        case .general: return generalLog
        case .clipboard: return clipboardLog
        case .actions: return actionsLog
        case .permissions: return permissionsLog
        }
    }
}

enum LogCategory {
    case general
    case clipboard
    case actions
    case permissions
}
