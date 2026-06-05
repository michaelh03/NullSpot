# NullSpot

Spotify client for macOS (and maybe later iPad and iOS).

## Active UI: Minimal (Winamp-style)

**Always search `NullSpot/Views/Minimal/` first.** The minimal Winamp-style UI is the active development surface — it's the only UI rendered when logged in (`ContentView` → `MinimalLoggedInView`). When asked about "the player", "the search bar", "the playlist", "the now-playing strip", etc., look in `Views/Minimal/` before anything else.

- Active root: `NullSpot/Views/Minimal/MinimalLoggedInView.swift` → `MinimalPlayerWindow.swift`
- All active UI components live under `NullSpot/Views/Minimal/` (prefix `Minimal*`)
- Active queue model: `NullSpot/Views/Minimal/MinimalPlaylist.swift` (NOT the legacy queue views)

**Non-Minimal views in `NullSpot/Views/` (still wired, in scope for edits):** `ContentView.swift`, `LoggedInLifecycleModifier.swift`, `PreferencesView.swift`, `PremiumRequiredView.swift`, `SessionExpiredView.swift`, `UserNotWhitelistedView.swift`. The previously-listed legacy UI files (`LoggedInView.swift`, `SidebarView.swift`, `NowPlayingBarView.swift`, the list/detail router views, etc.) have been removed from the repo.

**Shared infrastructure (used by the minimal UI, in scope for edits):** everything under `Store/`, `Store/Services/`, `SpotifyAPI/`, `Models/`, `SpotifyPlayer.swift`, `ViewModels/PlaybackViewModel.swift`, `VisualizerTap.swift`, `AudioRenderer.swift`.

## Tech Stack

- **Language**: Swift 6.2 with strict concurrency enabled
- **Target Platforms**: macOS 15.0+ (iOS/iPadOS later)
- **UI Framework**: SwiftUI

## Development Guidelines

- Use Swift 6.2 strict concurrency features (`Sendable`, `@MainActor`, async/await)
- Minimum deployment target is macOS 15.0 — guard any newer APIs with `if #available(macOS 26, *)` etc.
- Format all Swift code with: `swiftformat --swiftversion 6.2 .`

Also read `AGENTS-twostraws.md` for general development guidelines and best practices inspired by Paul Hudson's "Two Straws" approach.

## Network Request Logging

All Spotify API network requests must include debug logging. Add a log statement after constructing the URL string:

```swift
let urlString = "\(baseURL)/endpoint"
debugLog("SpotifyAPI", "[METHOD] \(urlString)")
```

- Use the appropriate HTTP method: `[GET]`, `[POST]`, `[PUT]`, `[DELETE]`
- `debugLog(_ module:_ message:)` is defined in `NullSpot/DebugLog.swift`; pass `"SpotifyAPI"` as the module for API requests
- It is a no-op in release builds (compiled to an empty `@inlinable` stub via `#if DEBUG`), so a bare call needs no `#if DEBUG` guard. Only wrap in `#if DEBUG` when the log line does extra work (e.g. decoding the response body for a richer message)
- API endpoints live in `SpotifyAPI/` (`SpotifyAPI.swift` plus `SpotifyAPI+*.swift` extensions)

## State Management Architecture

The app uses a normalized state store pattern (similar to Pinia/Redux) for data management.

### Core Components

**AppStore** (`Store/AppStore.swift`)
- Single source of truth for all entity data
- Normalized entity tables: `tracks`, `albums`, `artists`, `playlists`, `shows`, `devices`
- ID arrays for ordered collections: `savedTrackIds`, `userPlaylistIds`, `userAlbumIds`, `userArtistIds`
- Injected via `@Environment(AppStore.self)`

**Entities** (`Store/Entities.swift`)
- Unified data models: `Track`, `Album`, `Artist`, `Playlist`, `Show`, `Device`
- Decoupled from API response types (conversions in `EntityConversions.swift`)

**Services** (`Store/Services/`)
- Handle API calls and update AppStore on success
- Each service takes `AppStore` in its initializer
- Injected via `@Environment(XxxService.self)`
- Available services: `TrackService`, `AlbumService`, `ArtistService`, `PlaylistService`, `DeviceService`, `QueueService`, `RecentlyPlayedService`, `SearchService`, `ShowService`, `TopItemsService`, `ConnectionService`

### Network Request Deduplication

Views using `.task` to load data need protection against duplicate requests. The approach depends on whether the view's layout can change:

- **Stable views** (no layout changes): Simple `guard !store.xxxPagination.isLoading` in the service is sufficient
- **Layout-switching views** (Albums/Artists/Playlists trigger 2→3 column switch): The service must store the `Task` reference and be persisted via `@State` in a parent view, because view recreation can re-trigger `.task` before `isLoading` is set

The stored task pattern in `AlbumService`/`ArtistService`/`PlaylistService`:
```swift
if let existingTask = userAlbumsTask {
    _ = try? await existingTask.value  // Await existing, don't start new
    return
}
```

These services are stored as `@State` in `MinimalLoggedInView` so the task reference survives view recreation. If adding a new section that changes the column layout, use this pattern.

## Debug Logging

### Spirc/Connect Trace Logging

To see raw Spirc state transitions during development, set the `RUST_LOG` environment variable:

```bash
RUST_LOG=librespot_connect::spirc=trace ./path/to/NullSpot.app/Contents/MacOS/NullSpot
```

Or in Xcode scheme (Edit Scheme → Run → Arguments → Environment Variables):
- Name: `RUST_LOG`
- Value: `librespot_connect::spirc=trace`

This shows Mercury frames, Connect state changes, and device updates.

## Changelog & Releases

### Changelog Management

- Keep `CHANGELOG.md` in this repo up to date with all changes (detailed, technical notes welcome)
- Use [Keep a Changelog](https://keepachangelog.com/) format with sections: Added, Changed, Fixed, Removed
- Add entries under `## [Unreleased]` as you work

### Release Process

When ready to release, run: `/release [version]` (e.g., `/release 1.1.5`)

This will:
1. Move `[Unreleased]` entries to a new version section with today's date
2. Bump `MARKETING_VERSION` in the Xcode project
3. Update `../homebrew-nullspot/CHANGELOG.md` with user-facing summary (temporary)
4. Commit both repos

After `/release`, you must:
1. Push both repos
2. Create a GitHub Release in this repo with the built .zip artifact
3. Update the Homebrew formula in homebrew-nullspot (URL + SHA256)

### About homebrew-nullspot

The `../homebrew-nullspot` repo is temporary scaffolding for the Homebrew tap. Once the app is accepted into official Homebrew, it will be deleted. Until then:
- Releases are published to **this repo** (michaelh/nullspot)
- The homebrew-nullspot repo only contains the tap formula and a user-facing changelog
- Both changelogs are updated during `/release`
