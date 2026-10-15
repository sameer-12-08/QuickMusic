import SwiftUI
import AppKit

// When you start an app with `swift run` there is no .app bundle, so macOS may not
// treat it as a normal foreground app (window behind the terminal, keyboard not
// reaching the search box). This small AppKit delegate fixes that.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The app sets this once its window exists. It receives files opened from Finder.
    var openHandler: (([URL]) -> Void)? {
        didSet { deliverPending() }
    }
    // Files can arrive before the window is ready (cold start), so we hold on to them.
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// macOS calls this for "Open With > QuickFLAC", double-clicking an associated
    /// file, or dropping files on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURLs += urls
        deliverPending()
    }

    private func deliverPending() {
        guard let handler = openHandler, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs = []
        handler(urls)
    }

    // Closing the window quits the app (so `swift run` returns to the prompt).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// Entry point: like `if __name__ == "__main__":` in Python.
@main
struct QuickFLACApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // @LocalState (our macro-free @State, see LocalState.swift) keeps these alive for the app's lifetime.
    @LocalState private var library: Library
    @LocalState private var playback: PlaybackController      // owns the Player and the PlayQueue
    @LocalState private var themes: ThemeStore                // current theme, remembered between launches

    init() {
        Diagnostics.markStart()      // start the stopwatch before anything is created
        _library = LocalState(wrappedValue: Library())
        _playback = LocalState(wrappedValue: PlaybackController())
        _themes = LocalState(wrappedValue: ThemeStore())
    }

    var body: some Scene {
        // `Window` = exactly one window (a `WindowGroup` can spawn a new window every
        // time Finder hands us a file, which we don't want for a one-window player).
        Window("QuickFLAC", id: "main") {
            ContentView(playback: playback, library: library, themes: themes)
                .frame(minWidth: 640, minHeight: 360)
                .onAppear(perform: connectFinderOpen)
        }
        .defaultSize(width: 900, height: 560)
    }

    /// Files opened from Finder: add them to the library, play the first one now,
    /// and line the rest up right behind it.
    private func connectFinderOpen() {
        appDelegate.openHandler = { [library, playback] urls in
            Task { @MainActor in
                let added = await library.addAndWait(urls)
                guard let first = added.first else { return }
                playback.playNow(first)
                playback.playNext(Array(added.dropFirst()))
            }
        }
    }
}

/// The window: library (left) and queue (right) on top, controls at the bottom.
struct ContentView: View {
    let playback: PlaybackController
    let library: Library
    let themes: ThemeStore

    var body: some View {
        let palette = themes.palette    // reading this makes the window re-color when the theme changes

        VStack(spacing: 0) {
            // HSplitView gives a draggable divider between the two panels.
            HSplitView {
                LibraryView(library: library,
                            nowPlaying: playback.player.currentURL,
                            onPlay: playback.playNow,
                            onPlayNext: playback.playNext,
                            onEnqueue: playback.enqueue)
                    .frame(minWidth: 320)

                QueueView(queue: playback.queue, onPlay: playback.play)
                    .frame(minWidth: 220, idealWidth: 280)
            }
            Divider()
            ControlsBar(playback: playback, themes: themes)
        }
        // Theme: give every child view the palette, and color the standard controls.
        .environment(\.palette, palette)
        .background(palette.background.ignoresSafeArea())
        .foregroundStyle(palette.text)
        .tint(palette.main)                                         // sliders, selection, default buttons
        .preferredColorScheme(palette.isDark ? .dark : .light)      // title bar and system controls
        .onAppear { Diagnostics.logWindowReady() }
        // Drag files or folders from Finder onto the window.
        .dropDestination(for: URL.self) { urls, _ in
            library.add(urls)
            return true
        }
        .alert("Couldn't play file",
               isPresented: Binding(get: { playback.errorMessage != nil },
                                    set: { if !$0 { playback.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playback.errorMessage ?? "")
        }
    }
}
