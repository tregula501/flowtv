# FlowTV v0.3.8 — Chromecast Stability & AC-3 Audio Transcoding

This release focuses on making Chromecast casting genuinely usable: smooth continuous playback, accurate timeline reporting, and full AC-3 audio support via real-time FFmpeg transcoding.

## Highlights

### Chromecast — Production-Ready
- **Local HLS proxy with TS repackaging** — converts arbitrary IPTV streams into Chromecast-compatible HLS on-the-fly
- **PTS/DTS/PCR remapping** — eliminates timeline jumps and stalls caused by clock drift between source PTS and Cast's master clock
- **Accurate EXTINF durations** — reduced segment window eliminates timeline drift on the Cast device
- **Continuous smooth playback** — no more jumping to non-IDR live edges, no more discontinuity-induced glitches

### AC-3 → AAC Audio Transcoding
- **Persistent FFmpeg subprocess** with stdin/stdout pipes for real-time transcoding
- **No startup overhead** — eliminates the ~500ms per-segment cost of spawning ffmpeg, enabling smooth live audio
- AC-3 audio (common in IPTV streams) now plays correctly when casting to devices that don't decode AC-3 natively

## Changes Since v0.3.7

- `3c4e91e` Persistent FFmpeg process, PCR remapping, larger segment window
- `20333ed` Accurate EXTINF + reduced segment window eliminates Cast timeline drift
- `027e34b` Working AC-3 → AAC transcoding via FFmpeg subprocess
- `240bf5e` AC-3 → AAC transcoding via MediaCodec background thread (groundwork)
- `3728e7e` Disable audio transcoding to eliminate event loop interference
- `28ffa1e` Remove EXT-X-DISCONTINUITY tags that broke Chromecast playback
- `09bbcdb` MediaCodec AC-3 → AAC transcoding infrastructure
- `7b1c125` Chromecast casting now plays continuous smooth video
- `4c5a806` Chromecast casting stability — PTS remapping, audio sync, deploy script
- `2df7beb` Chromecast casting via local HLS proxy with TS repackaging

## Downloads

| Platform | File | Size |
|---|---|---|
| Windows x64 | `FlowTV-0.3.8-windows.zip` | 33 MB |
| Android | `FlowTV-0.3.8-android.apk` | 58 MB |

## Install Notes
- **Windows:** unzip and run `flowtv.exe`. No installer.
- **Android:** sideload the APK. Enable "Install unknown apps" for your file manager / browser if prompted.

**Full Changelog:** https://github.com/tregula501/flowtv/compare/v0.3.7...v0.3.8
