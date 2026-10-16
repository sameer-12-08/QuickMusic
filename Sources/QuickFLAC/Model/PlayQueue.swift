import SwiftUI        // only needed for Array.move(fromOffsets:toOffset:) used by drag-reordering
import Observation

/// One entry in the queue. The same song can be queued twice, so each entry gets
/// its own id (a Track's id would not be unique inside the queue).
///
/// `groupID` is shared by every song that was queued together as an album (or an
/// artist / folder). Songs with the same groupID always sit side by side in the queue.
struct QueueItem: Identifiable {
    let id = UUID()
    let track: Track
    var groupID: UUID? = nil
}

/// The play order, plus a "cursor" pointing at the entry that is playing now.
///
/// Played entries stay in the list above the cursor, so "previous" is just
/// "the entry above". Think of it as a Python list plus a `current_id` variable.
@MainActor
@Observable
final class PlayQueue {

    private(set) var items: [QueueItem] = []
    private(set) var currentID: QueueItem.ID?

    func setCurrent(_ id: QueueItem.ID?) {
        currentID = id
    }

    /// The entry that is playing now.
    var currentItem: QueueItem? {
        guard let i = index(of: currentID) else { return nil }
        return items[i]
    }

    // MARK: - Adding

    /// Puts songs at the end of the queue.
    /// `@discardableResult` = callers may ignore the return value without a warning.
    @discardableResult
    func append(_ tracks: [Track], groupID: UUID? = nil) -> [QueueItem] {
        let new = tracks.map { QueueItem(track: $0, groupID: groupID) }
        items.append(contentsOf: new)
        return new
    }

    /// Puts songs right after the playing entry (or at the very top if nothing is playing).
    /// If the playing entry is part of an album, the new songs go after the END of that
    /// album instead, so an album is never split in the middle.
    @discardableResult
    func insertNext(_ tracks: [Track], groupID: UUID? = nil) -> [QueueItem] {
        let new = tracks.map { QueueItem(track: $0, groupID: groupID) }
        var position = 0
        if let i = index(of: currentID) {
            position = i + 1
            if let group = items[i].groupID {
                while position < items.count && items[position].groupID == group { position += 1 }
            }
        }
        items.insert(contentsOf: new, at: position)
        return new
    }

    // MARK: - Editing

    /// Removes entries. The entry that is playing right now is skipped, so the cursor
    /// never points at something that no longer exists (use Clear to remove everything).
    func remove(_ ids: Set<QueueItem.ID>) {
        items.removeAll { ids.contains($0.id) && $0.id != currentID }
    }

    /// Called by the list when you drag rows to a new position.
    /// A move that would drop a song into the middle of an album, or pull a song out
    /// of its album, is ignored. You can still reorder inside an album, and move a
    /// whole album as a block.
    func move(from source: IndexSet, to destination: Int) {
        var moved = items
        moved.move(fromOffsets: source, toOffset: destination)
        guard groupsStayTogether(moved) else { return }
        items = moved
    }

    /// True if every groupID forms one unbroken run in the list.
    private func groupsStayTogether(_ list: [QueueItem]) -> Bool {
        var finished = Set<UUID>()
        var open: UUID?
        for item in list where item.groupID != open {
            if let open { finished.insert(open) }
            if let group = item.groupID, finished.contains(group) { return false }
            open = item.groupID
        }
        return true
    }

    func clear() {
        items.removeAll()
        currentID = nil
    }

    // MARK: - Moving the cursor

    /// The entry after `id`. With no id, the first entry.
    func item(after id: QueueItem.ID?) -> QueueItem? {
        guard let id else { return items.first }
        guard let i = index(of: id), i + 1 < items.count else { return nil }
        return items[i + 1]
    }

    func itemAfterCurrent() -> QueueItem? {
        item(after: currentID)
    }

    func itemBeforeCurrent() -> QueueItem? {
        guard let i = index(of: currentID), i > 0 else { return nil }
        return items[i - 1]
    }

    private func index(of id: QueueItem.ID?) -> Int? {
        guard let id else { return nil }
        return items.firstIndex { $0.id == id }
    }
}
