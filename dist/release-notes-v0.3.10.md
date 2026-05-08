# FlowTV v0.3.10 — Cast Stability & Foldable Edge-to-Edge

This release is a follow-up to v0.3.9 that addresses two issues msoroczak reported after testing v0.3.9 on a Samsung Galaxy ZFold6: the SafeArea fix only covered the mobile home screen (his unfolded inner display routes to the desktop layout), and Chromecast playback now started but stalled after 10-15s on AC-3 streams.

## Highlights

### Chromecast — Stable AC-3 playback
Fixed a buffer-management bug in the persistent FFmpeg subprocess that caused A/V sync drift after the initial cast buffer drained. The transcode call accumulated stdout across segment boundaries, so by segment 3 the audio bytes being muxed didn't match the segment's video timing — the cast device hit its A/V sync tolerance and stalled. `transcode()` now clears its output buffer before each write and uses a stability poll (bail after no growth, 1s timeout cap) instead of a fixed 200 ms sleep. Plus increased segment-window headroom (`_maxSegments` 6→8, `_initialSegments` 2→3) so transcoder jitter no longer starves the receiver.

### Edge-to-edge — Desktop home, Settings, EPG guide
v0.3.9's `SafeArea` fix landed on `MobileHomeScreen`, but devices with `MediaQuery.shortestSide >= 600dp` (tablets, foldables unfolded — the ZFold6 inner display measures ~870dp) render `HomeScreen` (sidebar+grid layout) instead. That widget had no SafeArea anywhere, so Android 15+ edge-to-edge rendering hid the bottom of the sidebar/grid behind the system nav bar. Same risk applied to `SettingsScreen` and `EpgGuideScreen`, which are pushed from `HomeScreen`. All three now wrap their `Scaffold` body in `SafeArea`.

## Bug fixes & details
- `fix(cast)`: isolate per-segment FFmpeg output to fix 10-15s playback stall (refs #3)
- `fix`: wrap desktop home/settings/epg-guide screens in SafeArea (refs #2)
- Diagnostic: log when FFmpeg `transcode()` returns 0 bytes after stability poll, so silent-AAC fallback is visible in logcat.

## Changes since v0.3.9
- `98a1e87` fix(cast): isolate per-segment FFmpeg output to fix 10-15s playback stall (#9)
- `fc9ed0c` fix: wrap desktop home/settings/epg-guide screens in SafeArea (#10)
- `e21bff8` chore: Bump version to 0.3.10+11

## Downloads

| Platform | File | Size |
|---|---|---|
| Windows x64 | `FlowTV-0.3.10-windows.zip` | 33 MB |
| Android | `FlowTV-0.3.10-android.apk` | 58 MB |

## Install Notes
- **Windows:** unzip and run `flowtv.exe`. No installer.
- **Android:** sideload the APK. No schema migration in this release — you can install over v0.3.9 without uninstalling.

## Credits
Thanks again to **@msoroczak** for testing v0.3.9 on the ZFold6 and reporting both regressions with enough detail to pin them down quickly. The "plays 10-15s then buffers" cadence + AC-3 streams (Peacock, CBS Pittsburgh) was the diagnostic for #3; the "either orientation" wording for #2 made the wrong-screen mistake immediately obvious.

**Full Changelog:** https://github.com/tregula501/flowtv/compare/v0.3.9...v0.3.10
