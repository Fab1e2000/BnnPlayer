import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct BananaPlayerApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            LibraryView(
                viewModel: container.libraryViewModel,
                playerViewModel: container.playerViewModel
            )
            .frame(minWidth: 760, minHeight: 620)
            .onAppear {
                bringAppToFront()
            }
        }
        .commands {
            CommandMenu("Library") {
                Button("添加音乐文件夹") {
                    container.libraryViewModel.addFolderFromDialog()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("重新扫描") {
                    container.libraryViewModel.scanLibrary()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandMenu("Playback") {
                Button(container.playerViewModel.state.isPlaying ? "暂停" : "播放") {
                    container.playerViewModel.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("上一首") {
                    container.playerViewModel.playPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                Button("下一首") {
                    container.playerViewModel.playNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
            }
        }
    }

    private func bringAppToFront() {
        #if os(macOS)
        // When launched via `swift run`, window creation can lag behind `onAppear`.
        // Delay slightly, then force-activate and raise all windows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)

            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            app.activate(ignoringOtherApps: true)

            for window in app.windows {
                window.orderFrontRegardless()
            }
            app.windows.first?.makeKeyAndOrderFront(nil)
        }
        #endif
    }
}
