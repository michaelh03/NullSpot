//
//  MinimalPlaylistView.swift
//  NullSpot
//

import SwiftUI

struct MinimalPlaylistView: View {
    @Environment(MinimalPlaylist.self) private var playlist

    let onPlay: (MinimalPlaylist.Entry) -> Void
    let onRemove: (Set<UUID>) -> Void
    @FocusState.Binding var focusedField: MinimalPlayerWindow.Field?

    /// Highlighted rows. Usually a single item (arrow-nav / click), but ⌘A
    /// selects everything so ⌘A-then-Delete clears the list, Winamp-style.
    @State private var selectedIds: Set<UUID> = []
    /// Navigation/play anchor — the row arrow keys move and Return plays.
    @State private var cursorId: UUID?

    var body: some View {
        Group {
            if playlist.entries.isEmpty {
                ContentUnavailableView(
                    "minimal.playlist.empty_title",
                    systemImage: "music.note.list",
                    description: Text("minimal.playlist.empty_description"),
                )
            } else {
                playlistScroll
            }
        }
        .background(MinimalTheme.bg)
        .focusable()
        .focusEffectDisabled()
        .focused($focusedField, equals: .playlist)
        .onMoveCommand { direction in
            switch direction {
            case .up: moveSelection(-1)
            case .down: moveSelection(1)
            default: break
            }
        }
        .onKeyPress(.return) {
            playSelected()
            return .handled
        }
        .onDeleteCommand(perform: deleteSelected)
        .onKeyPress(phases: .down, action: handleKeyPress)
        .onAppear {
            if cursorId == nil {
                let initial = playlist.currentEntryId ?? playlist.entries.first?.id
                selectSingle(initial)
            }
        }
    }

    private var playlistScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(playlist.entries) { entry in
                        MinimalPlaylistRow(
                            track: entry.track,
                            isCurrent: entry.id == playlist.currentEntryId,
                            isSelected: selectedIds.contains(entry.id),
                        ) {
                            focusedField = .playlist
                            selectSingle(entry.id)
                            onPlay(entry)
                        }
                        .id(entry.id)
                        MinimalDivider()
                    }
                }
            }
            .onChange(of: playlist.currentEntryId) { _, new in
                guard let new else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
            .onChange(of: cursorId) { _, new in
                guard let new else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private func moveSelection(_ delta: Int) {
        let entries = playlist.entries
        guard !entries.isEmpty else { return }
        let currentIdx = cursorId.flatMap { id in entries.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIdx = (currentIdx + delta).clamped(to: 0 ... (entries.count - 1))
        selectSingle(entries[nextIdx].id)
    }

    private func playSelected() {
        guard let id = cursorId, let entry = playlist.entries.first(where: { $0.id == id }) else { return }
        onPlay(entry)
    }

    /// Collapse the selection to a single row and move the cursor to it.
    private func selectSingle(_ id: UUID?) {
        cursorId = id
        selectedIds = id.map { [$0] } ?? []
    }

    private func selectAll() {
        selectedIds = Set(playlist.entries.map(\.id))
    }

    /// Remove every selected row (or just the cursor row if nothing is multi-
    /// selected), then move the cursor to the row that slides into the topmost
    /// removed slot — or the new last row if the tail was removed.
    private func deleteSelected() {
        let entries = playlist.entries
        let targets = selectedIds.isEmpty ? Set(cursorId.map { [$0] } ?? []) : selectedIds
        guard !targets.isEmpty else { return }
        let successor = successor(after: targets, in: entries)
        onRemove(targets)
        selectSingle(successor)
    }

    /// The id that should hold the cursor after `removed` are deleted: the first
    /// survivor below the topmost removed row, else the last survivor, else nil.
    private func successor(after removed: Set<UUID>, in entries: [MinimalPlaylist.Entry]) -> UUID? {
        let survivors = entries.filter { !removed.contains($0.id) }
        guard !survivors.isEmpty else { return nil }
        guard let topIdx = entries.firstIndex(where: { removed.contains($0.id) }) else {
            return survivors.first?.id
        }
        return entries[(topIdx + 1)...].first { !removed.contains($0.id) }?.id ?? survivors.last?.id
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // Delete/Backspace is handled by `.onDeleteCommand` (the AppKit command
        // path), which is reliable inside this focusable, button-filled list.
        if press.key == KeyEquivalent("a"), press.modifiers.contains(.command) {
            selectAll()
            return .handled
        }
        return .ignored
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
