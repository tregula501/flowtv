# FlowTV

A modern, cross-platform IPTV streaming application with EPG (Electronic Program Guide), DVR capabilities, and multi-view support.

![License](https://img.shields.io/badge/license-GPL%20v3-blue.svg)
![Flutter](https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-lightgrey)

## Features

### Core Features
- **M3U Playlist Support** - Import playlists via URL or file
- **Xtream Codes API** - Full support for Live TV, VOD, and Series
- **EPG Integration** - XMLTV guide with program schedules
- **Multi-Playlist Profiles** - Switch between different IPTV providers

### Playback
- **Adaptive Streaming** - HLS/RTMP with auto-quality adjustment
- **DVR Recording** - Record live TV to local storage
- **Timeshift** - Pause and rewind live TV
- **Multi-View** - Watch up to 4 channels simultaneously
- **Catch-up TV** - Watch previously aired content

### User Experience
- **TiviMate-Inspired UI** - Clean, intuitive interface
- **Dark & Light Themes** - Comfortable viewing any time
- **Full Keyboard Navigation** - Desktop-optimized controls
- **D-Pad Navigation** - Ready for TV remotes
- **Channel Search** - Search channels and EPG programs
- **Favorites** - Quick access to your preferred channels

### Privacy & Security
- **No Account Required** - Works entirely offline
- **No Analytics** - Your viewing habits stay private
- **Parental Controls** - PIN-protected profiles and channel locks

## Installation

### Pre-built Releases (Recommended)

Download the latest release for your platform from the [Releases](../../releases) page:

| Platform | Download |
|----------|----------|
| Windows | `FlowTV-x.x.x-windows.zip` |
| macOS | `FlowTV-x.x.x-macos.dmg` |
| Linux | `FlowTV-x.x.x-linux.AppImage` |
| Android | `FlowTV-x.x.x-android.apk` |

### Build from Source

#### Prerequisites

1. **Flutter SDK** (3.27 or later)
   ```bash
   # Download from https://docs.flutter.dev/get-started/install
   # Add to PATH
   flutter --version
   ```

2. **Platform-specific requirements:**
   - **Windows:** Visual Studio 2022 with "Desktop development with C++" workload
   - **macOS:** Xcode 15+
   - **Linux:** `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`

#### Build Steps

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/flowtv.git
cd flowtv

# Install dependencies
flutter pub get

# Generate code (Isar, Riverpod, Freezed)
dart run build_runner build --delete-conflicting-outputs

# Run in development mode
flutter run -d windows  # or macos, linux

# Build release
flutter build windows --release
```

## Usage

### Adding a Playlist

1. Open FlowTV
2. Go to **Settings** > **Playlists**
3. Click **Add Playlist**
4. Choose method:
   - **URL**: Paste your M3U playlist URL
   - **File**: Select a local `.m3u` or `.m3u8` file
   - **Xtream**: Enter server URL, username, and password

### Keyboard Shortcuts (Desktop)

| Key | Action |
|-----|--------|
| `Space` | Play/Pause |
| `F` | Toggle Fullscreen |
| `M` | Mute/Unmute |
| `Up/Down` | Volume |
| `Left/Right` | Seek (VOD) |
| `Esc` | Exit Fullscreen / Back |
| `Ctrl+F` | Search |
| `1-9` | Quick channel switch |

## Project Structure

```
lib/
├── core/           # Constants, themes, utilities
├── data/           # Models, repositories, data sources
├── domain/         # Business logic, use cases
├── presentation/   # UI screens, widgets, providers
├── l10n/           # Localization files
└── platform/       # Platform-specific code
```

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Roadmap

- [x] Phase 1: Core M3U playback
- [ ] Phase 2: EPG & Xtream Codes
- [ ] Phase 3: DVR & Multi-view
- [ ] Phase 4: Profiles & Parental controls
- [ ] Phase 5: Desktop polish
- [ ] Phase 6: Mobile & TV platforms

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Disclaimer

FlowTV is a media player application. It does not provide any TV content. Users are responsible for ensuring they have the legal right to access any content they stream through this application.

## Support

- [Report a Bug](../../issues/new?template=bug_report.md)
- [Request a Feature](../../issues/new?template=feature_request.md)
- [Discussions](../../discussions)

---

Made with Flutter
