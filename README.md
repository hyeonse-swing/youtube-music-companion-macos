# YT Music Companion

A focused macOS menu-bar app for the installed YouTube Music web app. It:

- Shows synchronized lyrics in a transparent, click-through overlay.
- Displays enhanced LRC word-timed files without showing their timing tags in the lyric text.
- Shows the exact YouTube Music cover supplied to macOS in the Now Playing panel.
- Optionally publishes the current track, visually verified artwork, progress,
  and an exact YouTube Music song link to Discord Rich Presence.
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

## YouTube Music priority

While Companion and the installed YouTube Music player are running, Companion
assigns the system media-control target to YouTube Music, including while paused.
Headset transport controls therefore use the music player even when a browser
video starts. Quitting Companion or closing the music app releases this preference.
Track metadata is queried directly from the YouTube Music client, independently
of the system's selected player. No playback command is sent when assigning priority.

When several media clients are registered, Companion checks all installed YouTube
Music candidates and prefers a complete, actively playing response. An empty first
candidate does not hide another valid player. Artwork uses the same YouTube Music selection
instead of the system's currently selected video or other audio source.

This uses dynamically resolved private MediaRemote APIs. If an API is unavailable,
the app still launches and falls back to the existing metadata query; priority is
not guaranteed on an untested macOS version. Hardware headset behavior must be
checked on the actual device. macOS 13 remains the minimum supported build target.


Use **About YT Music Companion…** in the menu-bar menu to check the installed
version, build number, Discord configuration status, bundle identifier, and project link.

## Menu and overlay controls

- **Show Now Playing…** opens the current-track panel. Choose **Pin to Side** or use
  **Show Mini Player…** from the menu bar for a floating card with artwork, title,
  artist, and playback progress. Drag it to your preferred position. **Expand Player**
  restores the full panel, and closing the card leaves playback running.
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

On first launch, Companion opens its setup guide if it cannot find the installed
player. Reopen it at any time from **Set Up YouTube Music…** in the menu bar or
from **Settings → General**.

1. Choose an installed Chrome, Edge, or Brave browser in the guide and open YouTube
   Music. If none is installed, the guide links to the official Chrome download.
2. Confirm the web app installation in the browser. In Chrome, use the install
   icon in the address bar or **Cast, save, and share → Install page as app**.
3. The guide detects the installed player automatically. Choose **Open app** and play a song in that window. A regular browser tab does not provide
   the separate player identity that macOS needs.

See Google's [YouTube Music desktop guide](https://support.google.com/youtubemusic/answer/9231765)
and [Chrome web app instructions](https://support.google.com/chrome/answer/9658361).

## Discord setup

When the installed app already has an Application ID, enable Discord sharing in
Companion and turn on activity sharing in Discord. In **Settings → Discord → Live**,
the default **Member list status** is **Song title - artist**. The expanded card
shows the title on the first line and the artist on the second. You can also select
the card’s details line, its status line, or the app name, then choose **Apply**.
The preview follows your template and preset.
Discord controls where the activity appears and who can see it. A friend can open
the same track in YouTube Music by clicking the title, the artist or weekly count,
the cover, or **Listen on YouTube Music** when a verified song link is available.
If the player is on the YouTube Music home page, choose **Open player page** in
the playback bar. Companion reads the current song’s watch link there with macOS
Accessibility access and shares only its video ID, leaving out playlist and tracking parameters.
When Companion starts with the player already in the background, bring the player
window forward once. Subsequent track changes can then be read in the background.

Turn on **Show this artist's weekly song count on Discord** and choose **Apply**
to show a second line such as **Companion QA · 2 songs this week**. The count is
for the artist you are listening to, starting on Monday in your Mac's time zone.
The weekly line uses the artist and title supplied by the player to macOS to
keep the same recordings together when screen labels or translations change.
Only distinct songs played while the option is on count. Replaying a song counts
once. Set **Member list status** to **Artist / status line** to use this line in
your status as well. Discord decides which activities appear in a server's
recent activity cards.

The floating mini player is available on macOS independently of Discord. Discord
documents the in-game overlay for Windows and synchronized Listen Along for its
Spotify account connection. See [Discord activity privacy](https://support.discord.com/hc/en-us/articles/7931156448919-Activity-Sharing-on-Discord-FAQ),
[Game Overlay](https://support.discord.com/hc/en-us/articles/217659737-Game-Overlay-101), and
[Discord’s Spotify connection](https://support.discord.com/hc/en-us/articles/360000167212-Discord-Spotify-Connection).

To configure your own source build:

1. Create an application in the [Discord Developer Portal](https://discord.com/developers/applications).
2. Copy its **Application ID**. This public identifier is the Discord client ID.
3. Optionally upload a Rich Presence Art Asset with the key `youtube-music` for the source badge and fallback cover.
4. Build or install with the ID:

```sh
DISCORD_CLIENT_ID=your_application_id ./scripts/install.sh
open -a YTMusicCompanion
```

Discord sharing is **off by default** on a new installation. Enable it in the app
only when you want to publish your listening activity; existing saved choices are
preserved during updates. Discord must also have activity sharing enabled. If no
client ID is supplied, the lyrics overlay still works and the Discord menu item is
disabled. An Application ID is public; never put a bot token or client secret in it.

## Privacy and security

- Playback metadata and artwork are read locally from the installed YouTube Music
  app. Optional Accessibility access reads its visible player-bar labels and song
  URL. The app does not require your Google password or browser cookies.
- Online lyric lookup sends song metadata, such as title, artist, album, and
  duration, to LRCLIB. Discord artwork matching searches Apple's iTunes catalog
  and downloads candidate covers. Those services receive ordinary network requests,
  including your IP address; disabling Discord does not disable online lyrics.
- When enabled, Discord sharing sends the configured song fields, progress, links,
  and public artwork URL to the local Discord desktop client. Discord controls who
  can see the resulting activity. Manual presence publishes the content you enter.
- Weekly counts are off by default. Opting in stores this week's artist and track
  identifiers as salted hashes on this Mac. Hidden songs and manual activities
  are excluded. With Discord sharing off, counts stay local. Turning off the
  weekly option and applying the change clears its data.
- Preferences, song choices, imported lyrics, and lyric/translation caches stay on
  this Mac. Diagnostics can clear downloaded lyrics; imported files are retained.
  Translation uses Apple's on-device framework, which may download language packs.
- There is no project-operated backend, analytics, or crash-reporting service.
  Please remove song details, local paths, and other personal information before
  sharing diagnostic output in a public issue.

The MediaRemote bridge uses private Apple APIs and the app requests powerful
Accessibility permission for exact metadata. Review the source before granting
access. Public release archives are currently **ad-hoc signed and not notarized**;
macOS may block them on another Mac. Do not disable Gatekeeper system-wide.
The MIT license covers the app's code, not music, lyrics, artwork, or third-party
service content. This is an independent project, unaffiliated with YouTube, Google,
Apple, or Discord.

## Development

```sh
./scripts/build-artwork-bridge.sh
./scripts/test-artwork-bridge.sh
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
.build/debug/YTMusicCompanion --check-player-setup
.build/debug/YTMusicCompanion --show-player-setup
.build/debug/YTMusicCompanion --show-mini-player
DISCORD_CLIENT_ID=your_application_id .build/debug/YTMusicCompanion --check-discord-connection
# Publishes “Companion Test” on the signed-in Discord profile for 12 seconds, then clears it.
DISCORD_CLIENT_ID=your_application_id .build/debug/YTMusicCompanion --discord
# To include a weekly count of two synthetic tracks, add --weekly-summary.
.build/debug/YTMusicCompanion --check-resources
```

## Architecture

- `NowPlaying.swift`: reads the installed YouTube Music client's MediaRemote state
  through the native bridge hosted by Apple's Perl, with a source-filtered JXA fallback.
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
