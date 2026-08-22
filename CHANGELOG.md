# Changelog

All notable changes to NullSpot will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Trailing `+` on an album (or playlist) row in Minimal search added nothing to the queue. `MinimalPlayerWindow.handleEnqueue` passed the container's own URI to `PlaybackViewModel.addToQueue`, but neither backing path accepts one: Spirc's `add_to_queue` and the Web API's `POST /me/player/queue` are track/episode-only, so the call was a no-op — and the branch never called `playlist.append`, so the visible queue was left untouched either way. Album, playlist and show picks now expand into their tracks first (via the existing `AlbumService`/`PlaylistService`/`ShowService` fetches) and go through a shared `enqueue(_ tracks:)` that appends each track to `MinimalPlaylist` and mirrors it into the live player queue, then refreshes the queue once — the same shape the artist branch already used. The per-entity track fetches shared with Play-All were pulled out into `tracks(forAlbum:)` / `tracks(forArtist:)` / `tracks(forPlaylist:)` / `tracks(forShow:limit:)` helpers.

## [0.2.1] - 2026-08-22

### Fixed
- Playback never started: the Spotify Connect device silently failed to register, so every play command was rejected. `Spirc::new()` was failing at `session.login5().auth_token()` with `INVALID_CREDENTIALS`, which left `SPIRC_READY`/`SESSION_CONNECTION_STATE.is_connected` false (they're only set *after* `Spirc::new()` returns), so `require_session_connected()` rejected every command with `ERROR_NOT_CONNECTED`. Because `PlaybackViewModel` only sets `isInitialized` once `isSpircReady` is true, each play attempt re-ran `initializeIfNeeded` → `nullspot_cleanup()` + re-init, producing an endless ~40s connect/teardown loop. Root cause: NullSpot handed librespot the *Web API* OAuth token. librespot's native path (clienttoken.spotify.com → access point → login5) only accepts a first-party native `client_id`; ncspot's Web API id is rejected there (clienttoken answers HTTP 400, and login5 answers `INVALID_CREDENTIALS` for stored credentials minted by a different id). Fixed by minting a **second** PKCE token with Spotify's keymaster id (`65b708073fc0480ea92a077233ca87bd`) purely for the librespot session, keeping the ncspot token for Web API calls — the same split spotify-player uses. New `LibrespotAuth` owns that token (keychain-cached under `librespot_*` keys, refreshed via its own `client_id`, re-authorizing interactively only when the refresh token is gone); `SpotifyAuth.authenticate`/`refreshAccessToken` are now parameterized by `clientId`/`scopes`. `SpotifyPlayer.setTokenProvider` and its `tokenProviderSession` global are removed — the Rust reconnect token callback now pulls from `LibrespotAuth.shared` too, so reconnects don't regress to the Web API token. Existing users get one extra browser consent on next launch.

## [0.2] - 2026-06-12

### Added
- Homebrew Cask distribution: NullSpot can now be installed via `brew install --cask michaelh03/nullspot/nullspot` (or `brew tap michaelh03/nullspot && brew install --cask nullspot`). The cask lives in the `michaelh03/homebrew-nullspot` tap (`Casks/nullspot.rb`) and points at the notarized `.dmg` attached to each GitHub Release of the public `michaelh03/NullSpot` repo, with a `livecheck` block (`strategy :github_latest`) so `brew` can detect new versions and a `zap` stanza that clears the app's Application Support, Preferences, and Caches (`com.michaelh.nullspot`) on uninstall.
- Remove tracks from the Minimal queue, Winamp-style: with the playlist focused, **Delete**/**Backspace** (or Fn-Delete) removes the selected row(s); **⌘A** selects all, so **⌘A** then **Delete** clears the whole list (there's no separate clear command, matching the classic Winamp Playlist Editor idiom). Selection moved from a single row to a `Set<UUID>` plus a `cursorId` anchor (arrow keys / Return / click still operate on the single cursor and collapse the selection to it). After a delete the cursor lands on the row that slides into the topmost removed slot (or the new last row). New `MinimalPlaylist.remove(entryIds:)` mutates the visible list in one pass (auto-persisted via the entries `didSet`); `MinimalPlaylistView` routes Delete/⌘A through `handleKeyPress` and an `onRemove(Set<UUID>)` callback to `MinimalPlayerWindow`. This is local/cosmetic only — librespot's live queue is intentionally left untouched (there is no FFI to remove a single item from it), so a deleted but already-queued upcoming track may still play until the next time you press play. Removing the currently-playing row skips to the next track (`PlaybackViewModel.next()`) so audio keeps going; clearing everything leaves whatever is playing alone.
- Podcast episode resume position ("Continue listening"). Episode rows in the show drill-in now show a thin listening-progress bar plus a remaining-time caption ("12 min left") for partially-played episodes, or "Played" for finished ones. Tapping a partially-played episode resumes playback from where you stopped instead of restarting from 0. Data comes from the Web API's `resume_point` (`resume_position_ms` / `fully_played`), which required adding the `user-read-playback-position` OAuth scope — `resume_point` is decoded in `SimplifiedEpisodeCodable`, carried on the synthetic episode `Track` (`resumePositionMs` / `fullyPlayed` / `resumeProgress`), and rendered via new optional `progress`/`progressLabel` params on `MinimalSearchResultRow`. Resume-on-play threads a one-shot `pendingResume` through `PlaybackViewModel.playTracks(resumeFrom:)`: when the matching episode loads, it seeks to the saved position (guarded so it won't fight librespot if the podcast already auto-resumed). Localized `minimal.search.episode.time_left` / `minimal.search.episode.played` added for en/de/fr. Note: existing users must log out and back in to grant the new scope before resume data appears.
- Minimal player gains a Winamp-style volume slider on the left of the transport row. Slim 60pt `.controlSize(.mini)` slider with a `speaker.fill` glyph; the transport buttons sit on the right of the row (flush right, with a `Spacer` between) for clear separation between volume and playback controls. Bound to `PlaybackViewModel.volume` so it routes through the existing local-Spirc / remote-Connect plumbing (debounced subject → either `SpotifyPlayer.setVolume` or `SpotifyAPI.setVolume`). When a remote Connect device is active, the slider displays and updates `remoteVolume` for immediate visual feedback while the API call is in flight. Localized `minimal.volume` added for en/de/fr.
- Persist the Minimal queue across app launches: tracks you've enqueued are restored when you reopen the app, with the previously-current row highlighted (no auto-play). Stored as a per-user JSON file under `~/Library/Application Support/<bundle-id>/queue-<userId>.json`. Reads and writes happen on a dedicated `MinimalPlaylistPersistence` actor, so even a multi-hundred-track queue never blocks the UI. The file is removed on logout (both in-view buttons and the Preferences → Logout notification path). Note: this is local-only — the official Spotify Web API has no concept of a saved user queue, so it may diverge from what other Spotify clients show.
- Minimal search Artists tab: new pill inserted between Songs and Albums (order: Songs / Artists / Albums / Playlists / Podcasts). Tapping (or Return on) an artist drills into the artist's top tracks; Play-All replaces the queue with those tracks; the trailing `+` enqueues all of them. Cmd-keyed pill shortcuts shift accordingly (`⌘2` Artists, `⌘3` Albums, `⌘4` Playlists, `⌘5` Podcasts).
- Minimal-winamp search: Songs / Albums / Playlists pill filter with `⌘1`/`⌘2`/`⌘3` shortcuts and Tab-to-cycle. Strict one-type-at-a-time results, instant pill switching from cache, per-type infinite scroll, recent-searches empty state (last 10, deduped, persisted in `UserDefaults`). Return plays albums and playlists immediately via their `context_uri`; trailing `+` queues all album/playlist tracks.
- `MinimalMarqueeText`: Winamp-style horizontal marquee for the now-playing title and artist lines. Text width is measured synchronously via `NSFont` so the scroll/static decision is right on the first frame; a hidden sizer `Text` plus `.clipped()` envelope keeps a long string from inflating the parent HStack. Two copies separated by a 40pt gap scroll at 25pt/s with a 1.5s start delay; the marquee resets when the track changes.

### Changed
- Reduced `MinimalVisualizer.maxBarHeightRatio` from 0.95 to 0.65 so bars take at most ~65% of the header height instead of slamming against the top/bottom edges at loud volume. Same FFT data — just leaves visual breathing room around the bars.
- Restructured the minimal player layout: the visualizer and the current track name/artist now share one cell at the top, with the progress slider and transport controls (prev/play-pause/next) sitting directly underneath. The playlist/search list fills the remaining space below. `MinimalNowPlayingStrip` was removed and `MinimalTheme.nowPlayingHeight` retired in favor of a taller `headerHeight` (56pt).
- Refactored the logged-in shell so `NavigationCoordinator` now owns section selection, library detail selection, drill-down path, and back/forward history, with toolbar, lifecycle, and column routing extracted out of `LoggedInView`

### Removed
- Legacy three-column UI and supporting views (`LoggedInView`, content/detail routers, sidebar, now-playing bar, list/detail views for albums/artists/playlists/favorites/queue, user profile, speakers/AirPlay pickers, legacy search, startpage, track row, all `Views/Components/` cards, `NavigationCoordinator`, `TrackLookupViewModel`, `KeyboardShortcuts`). The Winamp-style Minimal UI is now the only logged-in surface. `PreferencesView` lost its Startpage tab (settings were only consumed by the removed startpage); the three unused focused-value keys in `NullSpotApp` (`navigationSelection`, `searchFieldFocused`, `recentlyPlayedService`) are gone. `BlockingState` is promoted to a top-level enum so the lifecycle modifier still compiles.

### Fixed
- App refused to launch on macOS 15–25: `NullSpot/Info.plist` hardcoded `LSMinimumSystemVersion` to `26.2`, overriding the `15.0` deployment target so the shipped build demanded macOS 26 (Tahoe). Changed it to `$(MACOSX_DEPLOYMENT_TARGET)` so the advertised minimum tracks the build setting (15.0 / Sequoia).
- Backspace/Delete didn't remove a queue row after clicking it. Two causes: (1) clicking a `MinimalPlaylistRow` (a plain `Button`) selected/played the track without moving keyboard focus to the list, so the row looked selected yet keypresses went nowhere — the row click closure now sets `focusedField = .playlist`; (2) delete was wired through `.onKeyPress(.delete)`, which is unreliable for the Backspace key inside a `.focusable()` container full of buttons — switched to `.onDeleteCommand` (the AppKit command path, same family as the `.onMoveCommand` already handling arrow keys), with ⌘A left on `.onKeyPress`. Clicking a track now makes the list the active pane and Backspace/Delete removes the selected row(s) immediately, matching the Winamp Playlist Editor idiom.
- Now-playing strip stayed blank (just a dash and "Nothing playing") while a podcast episode was playing, even though songs showed their title + artist correctly. The header read the current item via `SpotifyAPI.parseTrackURI`, which only understands `spotify:track:` URIs and returns nil for `spotify:episode:...`, and `store.currentTrackEntity` is never populated for episodes (the queue path drops them for the same parse reason, and episode metadata isn't fetched via the `/tracks` endpoint). `MinimalHeaderBar.currentTrack` now first looks the playing URI up in the local `MinimalPlaylist`, which already holds the full synthetic episode `Track` (episode title as the name, show name as the "artist"), so the episode title + show name surface just like a song's title + artist. The existing store/`parseTrackURI` lookups are kept as fallbacks.
- Search-result drill-in (album / playlist / podcast): tapping a single song or episode no longer wipes your queue and dumps the entire list into it. A mouse tap was wired to a whole-list `playFromDetail` path that called `playlist.clear()` and loaded every track, while the keyboard Return, the top-level search results, and the view's own doc comment all did the single-track thing — the drill-in mouse tap was the outlier. Now tapping a row appends just that one track and plays it (`pickTrack` always plays now, and threads podcast resume position through `playEntry(resumeFrom:)`). The header's **Play All** also stopped replacing the queue: the four `replaceAndPlay(forAlbum/Artist/Playlist/Show:)` handlers are now `appendAndPlay(forX:)`, appending the whole list to the existing queue and playing from the first track via a shared `appendAndPlay(_:)` helper. Removed the dead `playFromDetail` and its duplicated resume logic.
- Cut steady-state CPU during playback from ~20–30% down to ~5% (Release, Apple Silicon). Root causes and fixes: (1) `MinimalPlayerControls.progressRow` wrapped the Slider in a `TimelineView(.periodic, by: 0.25)`, so the Slider's `Binding(get:set:)` was re-allocated 4× per second and the Slider re-initialized each tick — gated the `TimelineView` on `playbackViewModel.isPlaying` (paused state no longer ticks) and lengthened the period to 0.5s; (2) `MinimalVisualizer` had `.animation(.easeOut, value: tap.bands)` on a `Canvas`, which the SwiftUI animation system can't actually interpolate but still drove the subtree at display refresh rate (60–120 Hz) — removed; (3) the visualizer's `Canvas` allocated 12 `Path`s + issued 12 fills per frame — batched into one `Path` with 12 rects and a single fill; (4) `VisualizerTap`'s FFT worker ran the full pipeline every 33 ms regardless of audio state — now gated on `writeCount` changes (skips FFT when the ring hasn't been written to), skips the `MainActor.run` republish when bands and `hasAudio` are unchanged, and extends its sleep to 100 ms once silence hysteresis has elapsed.
- Visualizer FFT worker now pauses while the host window is occluded, minimized, or on a different Space, and while the visualizer view itself is unmounted (e.g., during search). New `WindowVisibility.onWindowVisibilityChange` modifier bridges `NSWindow.didChangeOcclusionStateNotification` into SwiftUI; `VisualizerTap.setWindowVisible` / `setMounted` combine into a `(visible && mounted)` gate that starts/cancels the worker `Task`. There's a ~100 ms cold-start lag on resume which the existing `hasAudio` 45-frame hysteresis hides.
- Window-visibility probe now debounces the visible→hidden edge by 200 ms before propagating to consumers. AppKit emits transient `occlusionState` flips (`.visible` bit clears for ~10–50 ms) during window/Space/focus transitions while the window is plainly in the foreground (`isKey`/`isMain`/`onActiveSpace` all true, `NSApp.isActive`), which was tearing down and restarting the FFT worker on every blip — observed in logs as a 13 ms hide-then-show round trip on app re-focus. Visible-true still propagates immediately so resume has no added latency. Pending hide task is cancelled on observer replacement and in `deinit`.
- Favorites now resolve via batched `/me/tracks/contains` checks for the tracks actually shown in album, playlist, queue, search, and now-playing views instead of depending on a full favorites preload
- Saving and removing favorite tracks now uses Spotify's saved-tracks endpoint correctly, so heart toggles persist again across Spotify clients
- Clicking Favorites in the sidebar now loads the favorites list automatically again, and the first real favorites fetch replaces any optimistic placeholder entries instead of appending to them
- Navigation history is now tracked consistently across sidebar section switches, library detail selections, and pushed search destinations, with shared back/forward controls in the content toolbar
- Back/forward history restores no longer depend on a next-runloop reset flag; history recording is now suppressed until the exact restored snapshot is reached
- Search-result drill-down navigation now stores track IDs instead of full track payloads, so back/forward history does not retain large copies of search result arrays
- The navigation coordinator API no longer exposes ignored section/selection context parameters, and card/caller plumbing for those dead arguments has been removed
- Navigation history cleanup: removed the trivial back wrapper and documented why section switches clear the visible stack before history snapshots are recorded

## [1.2.5] - 2026-03-11

### Added
- French localization (merci [@statisticalyquiet](https://github.com/statisticalyquiet)! 🇫🇷🥐)
- Shuffle mode

### Fixed
- Fix silent failure (no audio) when playing a new album/playlist immediately after the previous one ends, if a network reconnect races the track load (audio key timeout left player in a broken state with no context)

## [1.2.4] - 2026-03-06

### Fixed
- Fix connecting to Spotify Connect enabled speakers
- Bug fixes and performance improvements

## [1.2.3] - 2026-02-27

### Changed
- AirPlay audio routing rewritten to use `AVAudioEngine` with a custom `AudioRenderer` for more reliable AirPlay device support
- Spotify Connect session stability improvements: better soft reconnect handling, reduced playback jolts during network recovery
- Use 300px album art instead of 640px across the app — reduces download size and eliminates OS-side JPEG transcode overhead in Now Playing (largest display size is 200pt)

### Fixed
- Mini player mode no longer breaks when a fullscreen notification triggers a window state change
- Significantly reduced CPU usage during playback: split Now Playing metadata updates into full vs position-only paths, lowered seek bar update frequency, stopped unnecessary drift-check writes, and removed redundant per-second `currentPositionMs` updates (~94% reduction in active CPU samples vs 1.2.2)

## [1.2.2] - 2026-02-08

### Added
- Context-aware track playback: double-tap a track in an album, playlist, or favorites to play from that position within the context (thanks [@vitbashy](https://github.com/vitbashy)!)

### Changed
- Adapt to [Spotify Web API breaking changes (February 2026)](https://developer.spotify.com/documentation/web-api/references/changes/february-2026): migrate removed endpoints, update playlist response structure, and replace batch fetches with parallel individual requests

### Fixed
- Double-tapping a queue track when playing radio (no context URI) no longer silently does nothing — falls back to single track playback
- Clicking a track card in search results before any playback has occurred now properly initializes the player first

### Removed
- Artist top tracks section (endpoint removed by Spotify with no alternative)
- New Releases section (endpoint removed by Spotify with no alternative)
- Artist follower counts, user email/country/follower display (fields removed from API responses)

## [1.2.1] - 2026-02-06

### Added
- 🎉 Spotify Connect support — NullSpot now shows up as a real Spotify Connect device
- Seamless playback transfer between NullSpot and other Spotify devices (phone, desktop, etc.)
- Automatic session reconnection with exponential backoff

### Changed
- All playback controls (play, pause, seek, volume, next, previous) now go through Spotify Connect for proper state sync across devices

### Fixed
- Remote playback state (queue, position, track) now shows immediately on launch
- Playback state updates correctly in the UI when controlled locally

## [1.2.0] - 2026-01-12

### Added
- User-facing README with screenshots, download links, and setup guide
- DEVELOPMENT.md with architecture and build documentation
- Images directory with screenshots for GitHub page

### Changed
- Releases now published to main repo (michaelh/nullspot) instead of homebrew-nullspot
- Updated release process documentation in CLAUDE.md

## [1.1.7] - 2026-01-09

### Added
- Queue editing: Edit queue like playlists with drag-and-drop reordering and track removal
- Fixed queue header with song count, scroll-to-current button, clear queue button, and edit mode toggle
- Only unplayed tracks can be reordered or removed from the queue
- Real-time queue updates: when player advances during editing, track is automatically removed from edit list
- New Rust FFI functions for queue manipulation: `nullspot_remove_from_queue`, `nullspot_move_queue_item`, `nullspot_clear_upcoming_queue`

## [1.1.6] - 2026-01-07

### Changed
- Client ID is now mandatory: removed optional toggle, users must provide their own Spotify Client ID
- Added link to setup instructions on login screen
- Added note about using existing Spotify apps with the required redirect URI

## [1.1.5] - 2026-01-07

### Added
- Custom Client ID support: Users can now provide their own Spotify Client ID on the login screen via a checkbox and input field, useful for working around Spotify API restrictions

## [1.1.4] - 2026-01-05

### Added
- Streaming quality preferences (Normal, High, Very High) in Preferences window
- Sleep-proof token refresh: tokens are now validated lazily on-demand instead of background timers

### Fixed
- Fixed favorite indicator not updating correctly after toggling
- Fixed token expiration handling when Mac wakes from sleep

## [1.1.3] - 2026-01-05

### Changed
- Use market from OAuth token instead of hardcoded US for proper regional content
- Optimized album loading: reduced page size and prevented duplicate fetches
- Moved service state to centralized AppStore for consistent architecture
- Reduced artist pagination limit to 20 for better performance

### Fixed
- Fixed artist pagination issues
- Auto-select first item in library list views for better UX

## [1.1.2] - 2026-01-04

### Fixed
- Mini player bugfixes and performance improvements

## [1.1.1] - 2026-01-04

### Added
- Playlist management (edit, rename, delete, reorder tracks)

### Fixed
- Bug fixes and performance improvements

## [1.1.0] - 2026-01-03

### Added
- 3-dot context menu on tracks with actions:
  - Play Next
  - Add to Queue
  - Start Song Radio
  - Go to Artist
  - Go to Album
  - Share (copies link to clipboard)
- Like/Unlike current track with Cmd+L keyboard shortcut
- Menu bar entries for all keyboard shortcuts (Playback and Navigate menus)
- Heart indicator on tracks showing favorite status

### Fixed
- Bug fixes and performance improvements

## [1.0.1] - 2026-01-02

### Fixed
- Fixed crash on login in release builds by embedding Spotify client credentials in the app bundle

### Changed
- Updated build process to automatically inject credentials from environment variables

## [1.0.0] - 2026-01-01

### Added
- Lightweight Spotify player for macOS using librespot
- Recently played tracks, albums, artists, and playlists
- Queue management with drag-to-reorder
- Playback controls with progress bar
- Search functionality across tracks, albums, artists, playlists
- Favorites management
- Mini player mode
- AirPlay support
- Native macOS app with Spotify Web API integration
