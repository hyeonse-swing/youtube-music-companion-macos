# YT Music Companion

A focused macOS menu-bar app for the installed YouTube Music web app. It:

- Shows synchronized lyrics in a transparent, click-through overlay.
- Shows the exact YouTube Music cover supplied to macOS in the Now Playing panel.
- Publishes the current track, visually verified artwork, progress, and an exact
  YouTube Music song link to Discord Rich Presence.
- Uses the exact title, artist, and album rendered in YouTube Music's player bar,
  including bilingual labels such as `鋼の羽根 - Iron Feather`.
- Shows the current track and playback progress in a native **Now Playing** panel.
- Lets you choose lyric versions, lyric size, timing resets, and separate metadata
  sources for the app and Discord from a native **Settings** panel.
- Lets you customize Discord's top line, second line, cover description,
  playback-time visibility, and song-link visibility with track metadata templates.

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
  adjustments, selects an LRCLIB result per song, and independently chooses
  YouTube Music screen metadata or macOS playback metadata for the app and Discord.
- The **Discord** settings tab supports `{title}`, `{artist}`, and `{album}` tokens,
  shows a live preview, lets you show or hide the exact current-song link, and
  provides **Revert Changes** and **Reset to Defaults**.

## Requirements

- macOS 14 or later
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
- `PlayerModel.swift`: coordinates playback polling, page metadata, lyrics, timing,
  and menu state without publishing clock-only changes to every view.
- `DiscordPresenceController.swift`: publishes only pixel-verified public artwork URLs
  and manages successful-send deduplication and retry.
- `DiscordPresenceConfiguration.swift`: renders and validates the saved Discord text
  templates before they reach the Rich Presence transport.
- `DiscordRPC.swift`: dependency-free Discord local IPC client.
- `Lyrics.swift` / `LyricsCache.swift`: LRCLIB lookup, LRC parsing, and disk cache.
- `LyricsView.swift` / `OverlayStyle.swift`: overlay rendering and shared geometry.
- `CompanionPreferences.swift` / `SettingsWindow.swift`: persisted user choices and
  a lazily-created native settings interface whose inactive sections are not rendered.
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

The generated app is ad-hoc signed for local use. Distribution to other Macs requires a Developer ID signature and notarization.

## License

MIT. The original copyright and license notice are retained, with additional copyright for this derivative project.
