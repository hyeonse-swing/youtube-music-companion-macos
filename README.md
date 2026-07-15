# YT Music Companion

A focused macOS menu-bar app for the installed YouTube Music web app. It:

- Shows synchronized lyrics in a transparent, click-through overlay.
- Shows the exact YouTube Music cover supplied to macOS in the Now Playing panel.
- Publishes the current track, visually verified artwork, and progress to Discord Rich Presence.
- Restores Japanese titles, artists, and albums when YouTube Music exposes a
  localized or romanized label.
- Shows the current track, playback progress, and the exact value reported by
  YouTube Music in a native **Now Playing** panel.

Other players and ordinary browser tabs are intentionally ignored.

Use **About YT Music Companion…** in the menu-bar menu to check the installed
version, build number, Discord configuration status, bundle identifier, and project link.

## Menu and overlay controls

- **Show Now Playing…** opens the current-track panel.
- Drag the current lyric line to move the overlay. Its position is restored at the
  next launch and falls back automatically if a display is disconnected.
- **Reset Lyrics Position** returns the overlay to the bottom of the primary display.
- Scroll over the current lyric line to adjust lyric synchronization.

## Requirements

- macOS 14 or later
- Discord desktop app for Rich Presence
- YouTube Music installed as a Chromium web app
- Swift 5.9 or later to build from source

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
.build/debug/YTMusicCompanion --now-original
.build/debug/YTMusicCompanion --now-artwork
.build/debug/YTMusicCompanion --metadata "Kenshi Yonezu" "Shunrai" 289
.build/debug/YTMusicCompanion --probe "Artist" "Title" 200
.build/debug/YTMusicCompanion --art "Artist" "Title"
DISCORD_CLIENT_ID=your_application_id .build/debug/YTMusicCompanion --discord
```

## Architecture

- `NowPlaying.swift`: reads macOS MediaRemote state through an `osascript` JXA bridge.
- `NowPlayingArtwork.swift`: requests the actual cover once per track, keeps it in
  memory, and verifies any public Discord artwork URL against those pixels.
- `YouTubeMusicSource.swift`: accepts only the installed YouTube Music web app.
- `OriginalScriptMetadataResolver.swift`: verifies Japanese storefront metadata and
  prefers an artist's canonical release over matching compilation albums.
- `PlayerModel.swift`: coordinates playback polling, original metadata, lyrics, timing,
  and menu state.
- `DiscordPresenceController.swift`: publishes only pixel-verified public artwork URLs
  and manages successful-send deduplication and retry.
- `DiscordRPC.swift`: dependency-free Discord local IPC client.
- `Lyrics.swift` / `LyricsCache.swift`: LRCLIB lookup, LRC parsing, and disk cache.
- `LyricsView.swift` / `OverlayStyle.swift`: overlay rendering and shared geometry.
- `NowPlayingPanel.swift`: native current-track and playback-progress panel.
- `OverlayPositionStore.swift`: persistent, display-safe overlay positioning.

The MediaRemote bridge uses a private Apple framework. That makes direct, notarized distribution appropriate, but not Mac App Store distribution. macOS updates may also require compatibility fixes.

Discord cannot receive local image bytes. The app searches for a public catalog
cover and uses it only when its pixels match the actual YouTube Music cover; if no
verified match exists, Discord keeps the configured YouTube Music fallback icon.

Original-script resolution is deliberately conservative. A similar duration or search
rank is never sufficient by itself. If the same catalog ID cannot be verified against
MediaRemote's title and artist, the app keeps YouTube Music's label instead of guessing.
The storefront is used only as a metadata lookup; Apple Music playback is never monitored.

## Build a release app

```sh
DISCORD_CLIENT_ID=your_application_id ./scripts/build-app.sh
open YTMusicCompanion.app
```

The generated app is ad-hoc signed for local use. Distribution to other Macs requires a Developer ID signature and notarization.

## License

MIT. The original copyright and license notice are retained, with additional copyright for this derivative project.
