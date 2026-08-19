# YT Music Companion

A focused macOS menu-bar app for the installed YouTube Music web app. It:

- Shows synchronized lyrics in a transparent, click-through overlay.
- Shows the exact YouTube Music cover supplied to macOS in the Now Playing panel.
- Publishes the current track, visually verified artwork, progress, and an exact
  YouTube Music song link to Discord Rich Presence.
- Uses the exact title, artist, and album rendered in YouTube Music's player bar,
  including bilingual labels such as `鋼の羽根 - Iron Feather`.
- Shows the current track and playback progress in a native **Now Playing** panel.
- Keeps the source lyrics as the primary line and can add optional romanization
  and on-device translation layers for the song's detected language. This is
  language-aware behavior, not a Japanese-only mode.
- Lets you choose lyric versions, lyric size, layered-lyric options, timing resets,
  and separate metadata sources for the app and Discord from a native **Settings** panel.
- Follows the supported macOS interface language by default and lets you switch
  the app independently between Korean and English without relaunching.
- Includes Balanced, Focused, Compact, and Stage overlay presets plus an optional
  lightweight karaoke line-progress highlight.
- Lets you pin a local UTF-8 `.lrc` file to the current song, export the active
  synced lyrics, and safely return to the saved online version.
- Includes a Discord Studio with live presets, pause behavior, clickable fields,
  two custom buttons, per-song privacy, and an auto-expiring manual presence mode.
- Cancels stale lyric, metadata, and artwork work when tracks change, and slows
  background polling automatically while paused or idle.
- Includes a **Diagnostics** settings tab for polling, child-process, cache, and
  live Discord connection status.

Other players and ordinary browser tabs are intentionally ignored.

Use **About YT Music Companion…** in the menu-bar menu to check the installed
version, build number, Discord configuration status, bundle identifier, and project link.

## Menu and overlay controls

- **Show Now Playing…** opens the current-track panel.
- **Enable Exact YouTube Music Metadata…** opens Accessibility settings when the
  required permission has not been granted yet.
- Drag the current lyric line to move the overlay. Its position is restored at the
  next launch and falls back automatically if a display is disconnected.
- **Reset Overlay Position** returns the overlay to the bottom of the primary display.
- Scroll over the current lyric line to adjust lyric synchronization.
- A new song always starts at `0.00s`; a manual timing adjustment is restored only
  when that same recording plays again.
- **Settings…** (`⌘,`) changes lyric size, resets the current or all timing
  adjustments, selects an LRCLIB result per song, configures original/romanized/
  translated lyric layers, and independently chooses YouTube Music screen metadata
  or macOS playback metadata for the app and Discord.
- The **General** tab selects **System Default**, **한국어**, or **English**.
  Interface changes apply immediately and are independent from the lyric
  translation target.
- The **Appearance** section applies an overlay preset and its recommended type
  size in one action. Karaoke progress estimates left-to-right character timing
  from each LRC line timestamp because standard LRC files do not provide word timing.
- **Show romanization** works across writing systems and hides duplicate Latin
  output. A timing-compatible community lyric version is preferred when available;
  macOS language-aware pronunciation supplies readings for Japanese Kanji and
  automatic transliteration covers other supported scripts.
- **Show translation** uses Apple's on-device Translation framework on macOS 15 or
  later. The source language is detected automatically, the target is selectable,
  and the full lyric is translated with song context while preserving its original
  timing. **Natural lyrics** makes Korean sentence endings consistently conversational;
  **System translation** preserves Apple's output unchanged. Completed translations
  are cached per song, lyric version, target, and tone, and stale work is cancelled
  on track changes.
- The **Local Lyrics** section imports or replaces a timestamped UTF-8 `.lrc`,
  exports the currently active lyrics, and removes the imported copy only after
  confirmation. Imported files are user-owned Application Support data and are
  not removed by **Clear Saved Lyrics**.
- The **Discord** settings tab has separate **Live** and **Manual** editors. Live
  mode supports presets, `{title}` / `{artist}` / `{album}` templates, pause
  retention, clickable card fields, and up to two buttons. Songs can be hidden
  using a locally saved one-way fingerprint instead of their title or URL.
- Manual mode can publish an explicitly entered song, cover URL, link, duration,
  and optional second button for 15 minutes to 2 hours. It is marked as manual in
  the app, returns to live playback automatically, and is never restored after quit.
- The **Diagnostics** tab shows the current polling cadence, active work, child
  process counts, bounded session caches, saved-lyrics disk usage, and Discord
  publication status. Saved lyrics can be cleared there at any time.

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac (Universal app)
- Discord desktop app for Rich Presence
- YouTube Music installed as a Chromium web app
- Swift 5.9 or later to build from source

On first playback, allow **Accessibility** access when macOS asks. It is used only
to read the title, artist, album, and exact current-song URL in YouTube Music's
player bar. Until permission is granted, the app safely falls back to the
English-only labels that Chrome sends to macOS and omits the song link.

If macOS does not show the prompt, choose **Enable Exact YouTube Music Metadata…**
from the menu-bar menu, then enable YT Music Companion in Accessibility settings.

### Install YouTube Music as an app

1. Open <https://music.youtube.com> in Chrome, Brave, or Edge.
2. Use the install icon in the address bar, or choose **Install YouTube Music** from the browser menu.
3. Play music from the installed app, not a regular browser tab.

This distinction is required because macOS reports only the generic browser bundle for normal tabs.

## Discord setup

1. Create an application in the [Discord Developer Portal](https://discord.com/developers/applications).
2. Copy its **Application ID**. This public identifier is the Discord client ID.
3. Optionally upload a Rich Presence Art Asset with the key `youtube-music` for the source badge and fallback cover.
4. Build or install with the ID:

```sh
DISCORD_CLIENT_ID=your_application_id ./scripts/install.sh
open -a YTMusicCompanion
```

Discord must have activity sharing enabled. If no client ID is supplied, the lyrics overlay still works and the Discord menu item is disabled.

## Development

```sh
./scripts/build-artwork-bridge.sh
swift build
swift test
DISCORD_CLIENT_ID=your_application_id swift run
```

Useful probes:

```sh
.build/debug/YTMusicCompanion --now
.build/debug/YTMusicCompanion --now-page
.build/debug/YTMusicCompanion --now-artwork
.build/debug/YTMusicCompanion --metadata "Kenshi Yonezu" "Shunrai" 289
.build/debug/YTMusicCompanion --probe "Artist" "Title" 200
.build/debug/YTMusicCompanion --art "Artist" "Title"
DISCORD_CLIENT_ID=your_application_id .build/debug/YTMusicCompanion --discord
.build/debug/YTMusicCompanion --check-resources
```

## Architecture

- `NowPlaying.swift`: reads macOS MediaRemote state through an `osascript` JXA bridge.
- `NowPlayingArtwork.swift`: requests the actual cover once per track, keeps it in
  memory, and verifies any public Discord artwork URL against those pixels.
- `YouTubeMusicSource.swift`: accepts only the installed YouTube Music web app.
- `YouTubeMusicPageMetadataResolver.swift`: reads the exact visible player-bar labels
  and watch URL through macOS Accessibility and rejects a stale previous-track page.
- `OriginalScriptMetadataResolver.swift`: retains the optional storefront probe used
  by the `--metadata` development command; it is not used for displayed metadata.
- `PlayerModel.swift`: coordinates adaptive playback polling, cancellable page
  metadata/artwork/lyrics work, timing, and menu state without publishing
  clock-only changes to every view.
- `CancellationToken.swift` / `SubprocessRunner.swift`: cancel stale Swift work and
  terminate its `curl`, `osascript`, or artwork-bridge child process.
- `RuntimeDiagnostics.swift`: polling cadence, binary lyric lookup, Discord state,
  and the runtime counters rendered by Settings.
- `DiscordPresenceController.swift`: publishes only pixel-verified public artwork URLs
  and manages successful-send deduplication and retry.
- `DiscordPresenceConfiguration.swift`: renders and validates the saved Discord text
  templates before they reach the Rich Presence transport.
- `DiscordStudio.swift`: live presets, link validation, pause policies, and the
  non-persistent manual-presence model.
- `DiscordRPC.swift`: dependency-free Discord local IPC client.
- `Lyrics.swift` / `LyricsCache.swift`: LRCLIB lookup, LRC parsing, and
  re-downloadable disk cache.
- `LyricLayers.swift` / `LyricTranslationCache.swift`: language-aware
  romanization, aligned optional lyric layers, and version-safe translation cache.
- `LyricTranslationCoordinator.swift`: cancellable macOS on-device translation
  tasks that run only after a song or lyric-layer setting changes.
- `LyricsFileDocument.swift` / `CustomLyricsStore.swift`: validated UTF-8 LRC
  import/export and per-song user-owned lyrics stored in Application Support.
- `LyricsView.swift` / `OverlayStyle.swift`: overlay rendering and shared geometry.
- `OverlayPresentation.swift`: persisted overlay presets and bounded line-progress
  timing for the optional karaoke highlight.
- `CompanionPreferences.swift` / `SettingsWindow.swift`: persisted user choices and
  a lazily-created native settings interface whose inactive sections are not rendered.
- `AppLanguage.swift` / localized resources: supported-language resolution,
  persisted overrides, and live Korean/English interface strings.
- `NowPlayingPanel.swift`: native current-track and playback-progress panel.
- `OverlayPositionStore.swift`: persistent, display-safe overlay positioning.

The MediaRemote bridge uses a private Apple framework. That makes direct, notarized distribution appropriate, but not Mac App Store distribution. macOS updates may also require compatibility fixes.

Discord cannot receive local image bytes. The app searches for a public catalog
cover and uses it only when its pixels match the actual YouTube Music cover; if no
verified match exists, Discord keeps the configured YouTube Music fallback icon.

Displayed metadata is not looked up in Apple Music or another music catalog. The app
reads YouTube Music's visible player bar and only checks that its title still belongs
to the MediaRemote track, preventing a brief previous-track UI state from being shown.

## Build a release app

```sh
DISCORD_CLIENT_ID=your_application_id ./scripts/build-app.sh
open YTMusicCompanion.app
```

The generated Universal app contains native Apple Silicon and Intel code and is
ad-hoc signed for local use. Distribution to other Macs requires a Developer ID
signature and notarization.
The release build also runs a standalone resource check so the installed app does
not depend on the source checkout or SwiftPM build directory remaining on disk.

## License

MIT. The original copyright and license notice are retained, with additional copyright for this derivative project.
