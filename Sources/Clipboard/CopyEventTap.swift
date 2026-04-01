import Cocoa
import ApplicationServices

struct CopyKeyEvent {
    let timestamp: TimeInterval
    let appName: String
    let bundleID: String?
    let pid: pid_t
}

final class CopyEventTap {
    var doublePressThreshold: TimeInterval = 0.28

    var onCopyKeyDown: ((CopyKeyEvent) -> Void)?
    var onDoubleCopy: ((CopyKeyEvent) -> Void)?

    private enum Constants {
        static let cKeyCode: Int64 = 8
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastCopyTimestamp: TimeInterval?

    deinit {
        stop()
    }

    func start() -> Bool {
        guard eventTap == nil else {
            Logger.info("[CopyEventTap] Already running", category: .clipboard)
            return true
        }

        Logger.info("[CopyEventTap] Starting event tap...", category: .clipboard)
        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }

            let tap = Unmanaged<CopyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                tap.enableIfNeeded()
            case .keyDown:
                tap.handleKeyDown(event)
            default:
                break
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            Logger.error("[CopyEventTap] ❌ Failed to create event tap - check Accessibility/Input Monitoring permissions", category: .clipboard)
            return false
        }
        Logger.info("[CopyEventTap] ✅ Event tap created successfully", category: .clipboard)

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        self.eventTap = nil
    }

    private func enableIfNeeded() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handleKeyDown(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        guard keyCode == Constants.cKeyCode else { return }
        guard flags.contains(.maskCommand) else { return }

        let now = CACurrentMediaTime()
        Logger.debug("[CopyEventTap] ⌘C detected at \(now)", category: .clipboard)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let frontmost = NSWorkspace.shared.frontmostApplication
            let copyEvent = CopyKeyEvent(
                timestamp: now,
                appName: frontmost?.localizedName ?? "Unknown App",
                bundleID: frontmost?.bundleIdentifier,
                pid: frontmost?.processIdentifier ?? 0
            )

            self.onCopyKeyDown?(copyEvent)

            if let last = self.lastCopyTimestamp, (now - last) <= self.doublePressThreshold {
                let interval = now - last
                Logger.info("[CopyEventTap] 🎯 Double ⌘C detected! Interval: \(String(format: "%.0f", interval * 1000))ms (threshold: \(String(format: "%.0f", self.doublePressThreshold * 1000))ms)", category: .clipboard)
                self.onDoubleCopy?(copyEvent)
                self.lastCopyTimestamp = nil
            } else {
                if let last = self.lastCopyTimestamp {
                    let interval = now - last
                    Logger.debug("[CopyEventTap] Too slow: \(String(format: "%.0f", interval * 1000))ms > \(String(format: "%.0f", self.doublePressThreshold * 1000))ms threshold", category: .clipboard)
                }
                self.lastCopyTimestamp = now
            }
        }
    }
}
