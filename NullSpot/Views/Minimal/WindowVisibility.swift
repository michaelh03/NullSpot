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
    // AppKit emits transient occlusionState flips during window/Space/focus
    // transitions where the .visible bit briefly clears for ~10–50ms while
    // the window is plainly in the foreground (isKey/isMain/onActiveSpace
    // all true, NSApp.isActive). Debounce the false→consumer edge so we
    // don't tear down the FFT worker on every blip. True propagates
    // immediately (cheap, and we never want to delay resume).
    private var pendingHideTask: Task<Void, Never>?
    private static let hideDebounce: Duration = .milliseconds(200)

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    deinit {
        // NotificationCenter.removeObserver is thread-safe.
        if let observer { NotificationCenter.default.removeObserver(observer) }
        pendingHideTask?.cancel()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if observedWindow === window { return }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        pendingHideTask?.cancel()
        pendingHideTask = nil
        observedWindow = window
        guard let window else { return }
        debugLog(
            "WindowVisibility",
            "observing window title=\"\(window.title)\" id=\(ObjectIdentifier(window)) " +
                "isKey=\(window.isKeyWindow) isMain=\(window.isMainWindow) " +
                "miniaturized=\(window.isMiniaturized) onActiveSpace=\(window.isOnActiveSpace) " +
                "occlusion=\(occlusionDescription(window.occlusionState))",
        )
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let win = self.observedWindow else { return }
                let visible = win.occlusionState.contains(.visible)
                debugLog(
                    "WindowVisibility",
                    "occlusion change visible=\(visible) " +
                        "occlusion=\(occlusionDescription(win.occlusionState)) " +
                        "isKey=\(win.isKeyWindow) isMain=\(win.isMainWindow) " +
                        "miniaturized=\(win.isMiniaturized) onActiveSpace=\(win.isOnActiveSpace) " +
                        "appActive=\(NSApp.isActive)",
                )
                self.report(visible: visible)
            }
        }
        // Fire once with the initial state so callers don't have to wait for
        // the first occlusion change.
        report(visible: window.occlusionState.contains(.visible))
    }

    private func report(visible: Bool) {
        pendingHideTask?.cancel()
        pendingHideTask = nil
        if visible {
            onChange(true)
        } else {
            pendingHideTask = Task { [weak self] in
                try? await Task.sleep(for: Self.hideDebounce)
                guard !Task.isCancelled, let self else { return }
                debugLog("WindowVisibility", "hide debounce elapsed — reporting visible=false")
                onChange(false)
            }
        }
    }
}

private func occlusionDescription(_ state: NSWindow.OcclusionState) -> String {
    // The raw value is a bitmask; .visible is currently the only documented bit
    // (bit 1, value 2), but other bits can be set by AppKit internally.
    "raw=\(state.rawValue) visible=\(state.contains(.visible))"
}
