import AppKit
import Combine

@MainActor
final class LyricsStatusBarController {
    private let viewModel: LyricsOverlayViewModel
    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(viewModel: LyricsOverlayViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureStatusItemButton()
        bindLyricsUpdates()
        updateStatusBar(primary: viewModel.primaryLine, secondary: viewModel.secondaryLine)
    }

    private func configureStatusItemButton() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp])
    }

    private func bindLyricsUpdates() {
        viewModel.$primaryLine
            .combineLatest(viewModel.$secondaryLine)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] primary, secondary in
                self?.updateStatusBar(primary: primary, secondary: secondary)
            }
            .store(in: &cancellables)
    }

    private func updateStatusBar(primary: String, secondary: String?) {
        guard let button = statusItem.button else {
            return
        }

        let primaryText = normalizedLine(primary)
        let secondaryText = normalizedLine(secondary)

        let merged: String
        if !secondaryText.isEmpty, primaryText != "无歌词" {
            merged = "\(primaryText) / \(secondaryText)"
        } else {
            merged = primaryText
        }

        let finalText = merged.isEmpty ? "无歌词" : merged
        button.title = truncated(finalText, maxCount: 34)
        button.toolTip = finalText
    }

    private func normalizedLine(_ value: String?) -> String {
        guard let value else {
            return ""
        }

        return value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func truncated(_ value: String, maxCount: Int) -> String {
        guard value.count > maxCount else {
            return value
        }

        let endIndex = value.index(value.startIndex, offsetBy: max(1, maxCount - 1))
        return String(value[..<endIndex]) + "…"
    }

    @objc
    private func handleStatusItemClick() {
        let app = NSApplication.shared
        app.unhide(nil)
        app.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        app.activate(ignoringOtherApps: true)

        for window in app.windows where window.isMiniaturized {
            window.deminiaturize(nil)
        }

        for window in app.windows {
            window.orderFrontRegardless()
        }
        app.windows.first?.makeKeyAndOrderFront(nil)
    }
}
