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

    // Closing the window quits the app (so `swift run` returns to the prompt),
    // except while the mini player is open and the main window is only hidden.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !KeepAlive.miniPlayerOpen
    }
}

// Entry point: like `if __name__ == "__main__":` in Python.
@main
struct QuickFLACApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // @LocalState (our macro-free @State, see LocalState.swift) keeps these alive for the app's lifetime.
    @LocalState private var library: Library
    @LocalState private var playback: PlaybackController      // owns the Player and the PlayQueue
    @LocalState private var themes: ThemeStore                // current theme, remembered between launches
    @LocalState private var keyboard: KeyboardController      // media keys, F7/F8/F9 and "/"
    @LocalState private var miniPlayer: MiniPlayerController  // the small floating player
    @LocalState private var fullScreen: FullScreenPlayer      // the big Now Playing screen

    init() {
        Diagnostics.markStart()      // start the stopwatch before anything is created
        let library = Library()
        let playback = PlaybackController()
        // When a song has been played long enough, the controller tells the library to count it.
        playback.onPlayCounted = { [library] id in library.incrementPlayCount(id) }
        _library = LocalState(wrappedValue: library)
        _playback = LocalState(wrappedValue: playback)
        let themes = ThemeStore()
        // When the playing song's cover changes, the theme picks its accent color from it.
        playback.onArtworkChanged = { [themes] image in themes.artworkChanged(image) }
        _themes = LocalState(wrappedValue: themes)
        _keyboard = LocalState(wrappedValue: KeyboardController(playback: playback, library: library))
        _miniPlayer = LocalState(wrappedValue: MiniPlayerController(playback: playback, themes: themes))
        _fullScreen = LocalState(wrappedValue: FullScreenPlayer())
    }

    var body: some Scene {
        // `Window` = exactly one window (a `WindowGroup` can spawn a new window every
        // time Finder hands us a file, which we don't want for a one-window player).
        Window("QuickFLAC", id: "main") {
            ContentView(playback: playback, library: library, themes: themes,
                        fullScreen: fullScreen, onMiniPlayer: miniPlayer.toggle)
                .frame(minWidth: 820, minHeight: 400)
                .onAppear {
                    connectFinderOpen()
                    keyboard.install()
                }
        }
        .defaultSize(width: 1100, height: 600)
        .commands {
            playbackMenu
            libraryMenu
        }
    }

    /// A "Playback" menu in the menu bar. Menu items are the easy way to get app-wide
    /// shortcuts that work whichever part of the window has focus.
    /// (Space = play/pause lives on the on-screen button, so typing a space in search still works.)
    @CommandsBuilder
    private var playbackMenu: some Commands {
        CommandMenu("Playback") {
            Button("Play/Pause  (Space)") { playback.player.togglePlayPause() }
            Button("Next") { playback.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous") { playback.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button("Volume Up") { changeVolume(by: 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Volume Down") { changeVolume(by: -0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            Button("Search") { library.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Mini Player") { miniPlayer.toggle() }
                .keyboardShortcut("m", modifiers: [.command, .option])
            Button("Full Screen Player") { toggleFullScreenPlayer() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }

    @CommandsBuilder
    private var libraryMenu: some Commands {
        CommandMenu("Library") {
            Button("Set Music Folder…") { library.chooseMusicFolder() }
            Button("Rescan Music Folder") { Task { await library.rescanMusicFolder() } }
                .keyboardShortcut("r", modifiers: .command)
            Divider()
            Toggle("Match Theme to Album Art",
                   isOn: Binding(get: { themes.matchArtwork },
                                 set: { themes.setMatchArtwork($0) }))
        }
    }

    private func toggleFullScreenPlayer() {
        if miniPlayer.isShowing { miniPlayer.expand() }     // the full screen player needs the main window
        fullScreen.toggle()
    }

    private func changeVolume(by amount: Float) {
        let player = playback.player
        player.setVolume(min(1, max(0, player.volume + amount)))
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

/// The window: sidebar, library page and queue on top, controls at the bottom.
struct ContentView: View {
    let playback: PlaybackController
    let library: Library
    let themes: ThemeStore
    let fullScreen: FullScreenPlayer
    let onMiniPlayer: () -> Void

    @LocalState private var section: LibrarySection = .songs   // which sidebar page is open

    var body: some View {
        let palette = themes.palette    // reading this makes the window re-color when the theme changes

        VStack(spacing: 0) {
            // HSplitView gives draggable dividers between the panels.
            HSplitView {
                SidebarView(section: $section)
                    .frame(minWidth: 120, idealWidth: 150, maxWidth: 200)

                LibraryView(library: library, playback: playback, section: section)
                    .frame(minWidth: 320)

                QueueView(queue: playback.queue, onPlay: playback.play)
                    .frame(minWidth: 220, idealWidth: 280)
            }
            Divider()
            ControlsBar(playback: playback, themes: themes,
                        onMiniPlayer: onMiniPlayer, onFullScreen: fullScreen.toggle)
        }
        // Theme: give every child view the palette, and color the standard controls.
        .environment(\.palette, palette)
        // The Now Playing screen covers the whole window. The library underneath stays alive,
        // so closing it brings back your search, sidebar page and scroll position.
        .overlay {
            if fullScreen.isActive {
                NowPlayingView(playback: playback, onClose: fullScreen.leave)
            }
        }
        .background(palette.background.ignoresSafeArea())
        .background(WindowAccessor())       // records this window for the mini / full screen players
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
