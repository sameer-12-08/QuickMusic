import SwiftUI

/// The play queue: drag rows to reorder, double-click to jump to a song,
/// Delete key or right-click to remove.
struct QueueView: View {
    let queue: PlayQueue
    let onPlay: (QueueItem) -> Void

    @Environment(\.palette) private var palette
    @LocalState private var selection = Set<QueueItem.ID>()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue · \(queue.items.count)")
                    .font(.headline)
                    .foregroundStyle(palette.caption)
                Spacer()
                Button("Clear") {
                    queue.clear()
                    selection.removeAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.error)      // destructive action
                .disabled(queue.items.isEmpty)
            }
            .padding(10)

            List(selection: $selection) {
                // `.onMove` only exists on ForEach; it gives us drag-to-reorder for free.
                ForEach(queue.items) { item in
                    TrackRow(track: item.track, isPlaying: item.id == queue.currentID)
                }
                .onMove { source, destination in
                    queue.move(from: source, to: destination)
                }
            }
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: QueueItem.ID.self) { ids in
                if !ids.isEmpty {
                    Button("Remove from Queue") { queue.remove(ids) }
                }
            } primaryAction: { ids in
                if let id = ids.first, let item = queue.items.first(where: { $0.id == id }) {
                    onPlay(item)
                }
            }
            .onDeleteCommand {
                queue.remove(selection)
                selection.removeAll()
            }
            .overlay {
                if queue.items.isEmpty {
                    Text("Queue is empty.\nRight-click a song and choose\nPlay Next or Add to Queue.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.sub)
                }
            }
        }
    }
}
