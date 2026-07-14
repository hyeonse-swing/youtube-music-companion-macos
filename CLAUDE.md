# Development guide

## Scope

YT Music Companion supports exactly one media source: the installed YouTube Music Chromium web app. Its product features are synchronized on-screen lyrics and Discord Rich Presence. Do not add generic browser, Spotify, Apple Music, or Telegram behavior without an explicit product decision.

## Commands

```sh
swift build
swift test
DISCORD_CLIENT_ID=your_application_id swift run
DISCORD_CLIENT_ID=your_application_id ./scripts/install.sh

.build/debug/YTMusicCompanion --now
.build/debug/YTMusicCompanion --probe "Artist" "Title" 200
.build/debug/YTMusicCompanion --art "Artist" "Title"
DISCORD_CLIENT_ID=your_application_id .build/debug/YTMusicCompanion --discord
```

## Required verification

1. Run `swift build` and `swift test`.
2. For runtime changes, rebuild `/Applications/YTMusicCompanion.app` with `scripts/install.sh`.
3. Confirm the running binary path with `pgrep -fl YTMusicCompanion`.
4. Use the debug probes for live MediaRemote, lyrics, artwork, and Discord checks.

## Load-bearing decisions

- MediaRemote is read through `/usr/bin/osascript`; third-party native calls are denied on recent macOS versions.
- Lyrics and artwork networking use `/usr/bin/curl`; do not switch to URLSession without live verification.
- A normal browser tab is not accepted because MediaRemote exposes only its generic browser bundle.
- `trackKey` excludes duration because web players report it late or inconsistently.
- Discord publication is deduplicated only after a successful send so starting Discord later retries the current track.
- Overlay geometry belongs in `OverlayStyle`; avoid duplicating matching AppKit and SwiftUI constants.
- Keep original MIT attribution in `LICENSE`.

Commit and push only when requested.
