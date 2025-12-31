import Cocoa
import SwiftUI

private class ActionEditorWindow: NSWindow {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

@MainActor
final class ActionEditorWindowController: NSObject {
    static let shared = ActionEditorWindowController()
    private var window: ActionEditorWindow?

    private override init() {
        super.init()
    }

    func show(
        action: CustomAction,
        isNew: Bool,
        onSave: @escaping (CustomAction) -> Void,
        onCancel: @escaping () -> Void
    ) {
        if let existingWindow = window {
            existingWindow.close()
        }

        let editorView = ActionEditorView(
            action: action,
            isNew: isNew,
            onSave: { [weak self] savedAction in
                onSave(savedAction)
                self?.window?.close()
                self?.window = nil
            },
            onCancel: { [weak self] in
                onCancel()
                self?.window?.close()
                self?.window = nil
            }
        )

        let hostingController = NSHostingController(rootView: editorView)

        let newWindow = ActionEditorWindow(contentViewController: hostingController)
        newWindow.title = isNew ? "New Action" : "Edit Action"
        newWindow.styleMask = [.titled, .closable]
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.delegate = self

        newWindow.onEscape = { [weak self, weak newWindow] in
            onCancel()
            newWindow?.close()
            self?.window = nil
        }

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
    }
}

extension ActionEditorWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
