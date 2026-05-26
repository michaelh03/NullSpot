//
//  MinimalPlaylistView.swift
//  NullSpot
//

import SwiftUI

struct MinimalPlaylistView: View {
    @Environment(MinimalPlaylist.self) private var playlist

    let onPlay: (MinimalPlaylist.Entry) -> Void
    @FocusState.Binding var focusedField: MinimalPlayerWindow.Field?

    @State private var selectedEntryId: UUID?

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
        .onAppear {
            if selectedEntryId == nil {
                selectedEntryId = playlist.currentEntryId ?? playlist.entries.first?.id
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
                            isSelected: entry.id == selectedEntryId,
                        ) {
                            selectedEntryId = entry.id
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
            .onChange(of: selectedEntryId) { _, new in
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
        let currentIdx = selectedEntryId.flatMap { id in entries.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIdx = (currentIdx + delta).clamped(to: 0 ... (entries.count - 1))
        selectedEntryId = entries[nextIdx].id
    }

    private func playSelected() {
        guard let id = selectedEntryId, let entry = playlist.entries.first(where: { $0.id == id }) else { return }
        onPlay(entry)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
