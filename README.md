# YT Music Companion

A focused macOS menu-bar app for the installed YouTube Music web app. It does two things:

- Shows synchronized lyrics in a transparent, click-through overlay.
- Publishes the current track, artwork, and progress to Discord Rich Presence.

Other players and ordinary browser tabs are intentionally ignored.

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
swift build
swift test
DISCORD_CLIENT_ID=your_application_id swift run
```

Useful probes:

```sh
.build/debug/YTMusicCompanion --now
.build/debug/YTMusicCompanion --probe "Artist" "Title" 200
.build/debug/YTMusicCompanion --art "Artist" "Title"
DISCORD_CLIENT_ID=your_application_id .build/debug/YTMusicCompanion --discord
```

## Architecture

- `NowPlaying.swift`: reads macOS MediaRemote state through an `osascript` JXA bridge.
- `YouTubeMusicSource.swift`: accepts only the installed YouTube Music web app.
- `PlayerModel.swift`: coordinates playback polling, lyrics, timing, and menu state.
- `DiscordPresenceController.swift`: resolves artwork and manages successful-send deduplication and retry.
- `DiscordRPC.swift`: dependency-free Discord local IPC client.
- `Lyrics.swift` / `LyricsCache.swift`: LRCLIB lookup, LRC parsing, and disk cache.
- `LyricsView.swift` / `OverlayStyle.swift`: overlay rendering and shared geometry.

The MediaRemote bridge uses a private Apple framework. That makes direct, notarized distribution appropriate, but not Mac App Store distribution. macOS updates may also require compatibility fixes.

## Build a release app

```sh
DISCORD_CLIENT_ID=your_application_id ./scripts/build-app.sh
open YTMusicCompanion.app
```

The generated app is ad-hoc signed for local use. Distribution to other Macs requires a Developer ID signature and notarization.

## License

MIT. The original copyright and license notice are retained, with additional copyright for this derivative project.
