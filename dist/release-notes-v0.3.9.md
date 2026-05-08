# FlowTV v0.3.9 — Casting Reachability, Android Edge-to-Edge, Auto-Refresh

## Highlights

### Chromecast — Now works on Samsung devices
Fixed a long-standing bug where Chromecast playback would briefly start, then drop to the cast icon and never recover, on Samsung phones (and any device whose network interface list enumerates `rmnet*` cellular interfaces before `wlan0`). The HLS proxy was advertising the first non-loopback IPv4, which on Samsung often pointed at an unreachable cellular IP. Replaced with a scored picker that prefers `wlan*`/`wlp*`/`en*` and RFC1918 addresses, with per-interface scoring logged at cast start for diagnostics.

### Android edge-to-edge — Buttons no longer hidden behind the system bar
On Android 15+ devices that render edge-to-edge by default (including foldables like the ZFold6), the Mobile home channel grid and player control overlays could render behind the system navigation bar, hiding the bottom buttons. Mobile home is now wrapped in `SafeArea`, and player overlays lift by `MediaQuery.padding` so they always clear the system insets.

### Auto-refresh playlists on launch
When you cold-start the app, any playlist whose data is older than the configured TTL (default 24 h, reusing the existing `playlistRefreshHours` setting) automatically refreshes in the background. Skipped silently when offline. New "Refresh playlists on launch" toggle in Settings (default on) lets you opt out — same pattern Televizo uses. EPG already auto-refreshes; this brings playlists in line.

## Bug fixes & details
- `fix(cast)`: pick the actual Wi-Fi interface for HLS proxy address (closes #3)
- `fix`: respect system insets on mobile home and player overlays (closes #2)
- `feat`: refresh stale playlists on app launch (closes #1)
- Defensive: in `_remapPcr`, leave PCR un-remapped when `pcrBase < ptsOffset` rather than wrap into a 33-bit nonsense value.
- Drift schema bumped 5 → 6 with `m.addColumn` migration for the new `refreshPlaylistsOnLaunch` setting.

## Changes since v0.3.8
- `8c2a6eb` feat: refresh stale playlists on app launch (#1)
- `e14fa34` fix(cast): pick the actual Wi-Fi interface for HLS proxy address (#3)
- `4a2c377` fix: respect system insets on mobile home and player overlays (#2)
- `31f1bad` chore: Bump version to 0.3.9+10

## Downloads

| Platform | File | Size |
|---|---|---|
| Windows x64 | `FlowTV-0.3.9-windows.zip` | 33 MB |
| Android | `FlowTV-0.3.9-android.apk` | 58 MB |

## Install Notes
- **Windows:** unzip and run `flowtv.exe`. No installer.
- **Android:** sideload the APK. **Uninstall any previous version first** — the Drift schema bumped from 5 → 6 for the new auto-refresh setting.

## Credits
Thanks to **@msoroczak** for filing the three issues that drove this release and for the precise reproduction info that pinned down the cast root cause (testing both AC-3 and AAC channels was decisive).

**Full Changelog:** https://github.com/tregula501/flowtv/compare/v0.3.8...v0.3.9
