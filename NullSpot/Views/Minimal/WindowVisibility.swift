//
//  WindowVisibility.swift
//  NullSpot
//
//  SwiftUI bridge for NSWindow.didChangeOcclusionStateNotification. Reports the
//  host window's visibility (occlusionState.contains(.visible)) on attach and on
//  every state change. Use to gate per-frame work that's invisible when the
//  window is occluded, minimized, or on a different Space.
//

import AppKit
import SwiftUI

extension View {
    func onWindowVisibilityChange(_ perform: @escaping @MainActor (Bool) -> Void) -> some View {
        background(WindowVisibilityProbe(onChange: perform))
    }
}

private struct WindowVisibilityProbe: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context _: Context) -> ProbeView {
        ProbeView(onChange: onChange)
    }

    func updateNSView(_ nsView: ProbeView, context _: Context) {
        nsView.onChange = onChange
    }
}

private final class ProbeView: NSView {
    var onChange: @MainActor (Bool) -> Void
    // nonisolated(unsafe) so the deinit can drop the observer token without
    // hopping actors. NSView itself is @MainActor; mutation of this property
    // only happens from viewDidMoveToWindow (main) and deinit (whichever
    // thread releases the last strong ref — see removeObserver below).
    private nonisolated(unsafe) var observer: NSObjectProtocol?
    private weak var observedWindow: NSWindow?

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    deinit {
        // NotificationCenter.removeObserver is thread-safe.
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if observedWindow === window { return }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        observedWindow = window
        guard let window else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let win = self.observedWindow else { return }
                self.onChange(win.occlusionState.contains(.visible))
            }
        }
        // Fire once with the initial state so callers don't have to wait for
        // the first occlusion change.
        onChange(window.occlusionState.contains(.visible))
    }
}
