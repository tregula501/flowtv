# FlowTV v0.3.11 — Cast Revert + Fullscreen Edge-to-Edge

## Important: Partial revert

v0.3.10 made the Chromecast bug measurably worse on at least one user's stream set: Peacock channels died in 5 seconds (vs ~10-15s on v0.3.9), there was a new 30-second black-screen startup window, and the app eventually crashed under sustained pressure. This release **reverts** the v0.3.10 cast changes (PR #9) back to v0.3.9 behavior while we re-investigate.

If you were on v0.3.9 and casting worked acceptably for you, v0.3.11 should match that. If you were on v0.3.10 and casting was painful, this should restore the prior baseline. A more targeted cast fix is planned for v0.3.12.

## Highlights

### Fullscreen + popup player — Edge-to-edge
v0.3.10 wrapped the desktop `HomeScreen`, `Settings`, and `EpgGuide` screens in `SafeArea`, but fullscreen player and popup player still rendered edge-to-edge — control buttons clipped behind the system nav bar on the unfolded ZFold6 inner display. v0.3.11 applies the same `MediaQuery.padding` lift pattern to those overlays.

### Cast — reverted to v0.3.9 behavior
PR #9's per-segment buffer clear and segment-window bump have been backed out. The Wi-Fi interface picker fix from v0.3.9 is unchanged.

## Bug fixes & details
- `revert`: PR #9 ffmpeg stdout isolation — regressed cast (refs #3)
- `fix`: wrap fullscreen + popup player screens in SafeArea (refs #2)

## Changes since v0.3.10
- `8f5e785` revert: PR #9 ffmpeg stdout isolation (#12)
- `c9f3307` fix: fullscreen + popup player SafeArea (#13)
- `9aa3963` chore: Bump version to 0.3.11+12

## Downloads

| Platform | File | Size |
|---|---|---|
| Windows x64 | `FlowTV-0.3.11-windows.zip` | 33 MB |
| Android | `FlowTV-0.3.11-android.apk` | 58 MB |

## Install Notes
- **Windows:** unzip and run `flowtv.exe`. No installer.
- **Android:** sideload the APK. No schema migration in this release — you can install over v0.3.10 without uninstalling.

## Credits
Thanks to **@msoroczak** for the precise testing reports on v0.3.10 — the "Peacock died in 5s vs CBS works for 10-15s" comparison was the diagnostic clue that motivated the revert (the symptoms differ enough across streams that something more nuanced than the buffer-clear is needed).

**Full Changelog:** https://github.com/tregula501/flowtv/compare/v0.3.10...v0.3.11
