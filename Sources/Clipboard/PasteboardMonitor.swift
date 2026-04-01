import Cocoa

final class PasteboardMonitor {
    var pollInterval: TimeInterval = 0.2
    var onChange: ((Int) -> Void)?

    private let pasteboard: NSPasteboard
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let current = self.pasteboard.changeCount
            guard current != self.lastChangeCount else { return }
            self.lastChangeCount = current
            self.onChange?(current)
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit {
        stop()
    }
}
