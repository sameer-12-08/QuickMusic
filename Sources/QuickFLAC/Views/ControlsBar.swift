import SwiftUI
import AppKit

/// Now-playing title, seek bar, theme button, previous / play-pause / next, and volume.
struct ControlsBar: View {
    let playback: PlaybackController
    let themes: ThemeStore
    let onMiniPlayer: () -> Void
    let onFullScreen: () -> Void

    @Environment(\.palette) private var palette
    @LocalState private var showThemes = false

    var body: some View {
        let player = playback.player

        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ArtworkView(image: playback.artwork)
                VStack(spacing: 6) {
                    Text(player.title ?? "Nothing playing")
                        .font(.headline)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SeekBar(player: player)
                }
            }

            HStack {
                // Left: theme picker (opens as a popover so you can watch the app re-color).
                Button { showThemes.toggle() } label: {
                    Image(systemName: "paintpalette")
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.sub)
                .help("Themes")
                .popover(isPresented: $showThemes) { ThemePicker(store: themes) }

                // Shrinks the app into the small floating player.
                Button(action: onMiniPlayer) {
                    Image(systemName: "pip.enter")
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.sub)
                .help("Mini Player")

                // Opens the big full-screen Now Playing screen.
                Button(action: onFullScreen) {
                    Image(systemName: "rectangle.expand.vertical")
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.sub)
                .help("Full Screen Player")

                Spacer()

                // Center: transport buttons.
                HStack(spacing: 18) {
                    Button(action: playback.previous) {
                        Image(systemName: "backward.fill")
                    }
                    .disabled(player.title == nil)

                    Button(action: player.togglePlayPause) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 24)
                    }
                    .keyboardShortcut(.space, modifiers: [])   // typing a space in the search box still works
                    .disabled(player.title == nil)

                    Button(action: playback.next) {
                        Image(systemName: "forward.fill")
                    }
                    .disabled(playback.queue.itemAfterCurrent() == nil)   // greyed out at the end of the queue
                }
                .buttonStyle(.plain)
                .font(.title3)
                .foregroundStyle(palette.text)

                Spacer()

                // Right: volume.
                Image(systemName: "speaker.fill").foregroundStyle(palette.sub)
                // A Binding is a get/set pair, so the slider can read and write the volume.
                Slider(value: Binding(get: { Double(player.volume) },
                                      set: { player.setVolume(Float($0)) }),
                       in: 0...1)
                    .frame(width: 90)
            }
        }
        .padding(12)
        .background(palette.subAlt)      // the bar sits on a slightly different surface color
    }
}

/// Small square cover. It always takes the same space, so the bar doesn't jump
/// around when a song has no artwork.
struct ArtworkView: View {
    let image: NSImage?
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(palette.background)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note").foregroundStyle(palette.sub)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Seek bar + elapsed/total time labels.
struct SeekBar: View {
    let player: Player
    @Environment(\.palette) private var palette
    // Non-nil only while the user is dragging the slider.
    @LocalState private var dragValue: Double?

    var body: some View {
        // TimelineView re-runs its content 4x/second, but only while visible.
        // That is much cheaper than a Timer that updates the model constantly.
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let time = dragValue ?? player.currentTime()
            HStack(spacing: 8) {
                Text(format(time)).monospacedDigit().foregroundStyle(palette.sub)
                Slider(value: Binding(get: { time }, set: { dragValue = $0 }),
                       in: 0...max(player.duration, 1)) { editing in
                    // Called when the user presses (true) or releases (false) the slider.
                    if !editing, let target = dragValue {
                        player.seek(to: target)
                        dragValue = nil
                    }
                }
                .disabled(player.title == nil)
                Text(format(player.duration)).monospacedDigit().foregroundStyle(palette.sub)
            }
        }
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
