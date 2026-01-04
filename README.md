# FlowTV

A modern, cross-platform IPTV streaming application with EPG (Electronic Program Guide), DVR capabilities, and multi-view support.

![License](https://img.shields.io/badge/license-GPL%20v3-blue.svg)
![Flutter](https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-lightgrey)

## Features

### Core Features
- **M3U Playlist Support** - Import playlists via URL, edit metadata, and manage multiple profiles
- **Xtream Codes API** - Full support for Live TV, VOD, and Series
- **EPG Integration** - XMLTV guide with program schedules and progress tracking
- **Multi-Playlist Profiles** - Switch between different IPTV providers
- **Batch Import Optimization** - Fast playlist and EPG loading with real-time progress

### Playback
- **Adaptive Streaming** - HLS/RTMP with auto-quality adjustment
- **Buffer Management** - Configurable prebuffering and auto-retry on connection loss
- **DVR Recording** - Record live TV to local storage
- **Timeshift** - Pause and rewind live TV
- **Multi-View** - Watch up to 4 channels simultaneously

### User Experience
- **TiviMate-Inspired UI** - Clean, intuitive interface with dark and light themes
- **Progress Indicators** - Real-time progress bars for EPG and playlist loading
- **Playlist Management** - Edit, refresh, and manage playlists with visual feedback
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

# Generate code (Drift, Riverpod, Freezed)
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
   - **URL**: Paste your M3U playlist URL (with optional EPG URL)
   - **File**: Select a local `.m3u` or `.m3u8` file
   - **Xtream**: Enter server URL, username, and password
5. Watch the progress bar as channels are imported
6. Once complete, the playlist will be ready to use

### Managing Playlists

- **Set Active**: Switch between loaded playlists
- **Edit**: Modify playlist name, URL, or EPG URL
- **Refresh**: Re-download channels from the source URL
- **Delete**: Remove a playlist and all its channels

### Loading EPG

1. Ensure your playlist has an EPG URL configured (auto-detected or manually set)
2. Go to **Settings** > **EPG**
3. Click the refresh button to load the TV guide
4. Watch the real-time progress bar showing programs being imported
5. Set auto-refresh interval for automatic updates

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
├── core/           # Constants, themes, utilities, extensions
├── data/           # Models, repositories, data sources, parsers
│   ├── datasources/
│   │   ├── local/  # Drift database, local storage
│   │   └── remote/ # M3U parser, XMLTV parser, HTTP clients
│   └── repositories/  # EPG and Playlist repositories
├── presentation/   # UI screens, widgets, providers
│   ├── providers/  # Riverpod state management
│   ├── screens/    # App screens
│   └── widgets/    # Reusable UI components
├── l10n/           # Localization files
└── platform/       # Platform-specific code
```

## Technical Stack

### Database & State Management
- **Drift** - Type-safe SQL database with reactive queries
- **Riverpod 3.x** - Provider-based state management with scoped access
- **Freezed** - Code generation for immutable models

### Data & Parsing
- **M3U Parser** - Full attribute extraction (tvg-id, logo, group-title, etc.)
- **XMLTV Parser** - EPG guide parsing with timezone support
- **Batch Imports** - Optimized bulk database inserts for performance

### UI & UX
- **Flutter 3.27+** - Cross-platform framework
- **Material 3** - Modern design system
- **Responsive Layout** - Works on desktop, tablet, and mobile

### Performance Optimizations
- **Batch Insert Operations** - Reduces 435,000+ individual DB calls to ~435 batch operations
- **Progress Tracking** - Real-time UI updates during long operations
- **Auto-retry with Exponential Backoff** - Handles connection failures gracefully
- **Configurable Buffering** - Prebuffer and auto-retry strategies

## Recent Updates (Phase 2)

### Database Migration
- Migrated from Isar to **Drift** for better type safety and reactive queries
- Batch insert operations for EPG (chunk size: 1000) and playlists (chunk size: 500)
- Dramatic performance improvement: Loading 435,000 EPG programs now completes in seconds

### Progress Tracking UI
- Real-time progress bars in Settings for both EPG and playlist operations
- Shows current/total items and operation phase (Downloading, Parsing, Storing)
- Visual feedback with circular and linear progress indicators

### Playlist Management
- **Edit Playlists** - Change name, M3U URL, and EPG URL without re-importing
- **Refresh Playlists** - Re-download channels with progress tracking
- **Set Active Playlist** - Switch between multiple loaded playlists
- **Delete Playlists** - Remove with all associated channels

### State Management
- Upgraded to **Riverpod 3.x** with Notifier pattern
- Scoped state providers for playlist and EPG progress
- Reactive UI that automatically updates with database changes

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Roadmap

### Completed
- [x] Phase 1: Core M3U playback
  - M3U/M3U8 parser with full attribute support
  - Favorites system
  - Channel search and filtering
  - Category organization

### In Progress
- [🔄] Phase 2: EPG & Xtream Codes
  - [x] XMLTV EPG parsing and storage (Drift database)
  - [x] Batch import optimization with progress tracking
  - [x] Edit playlist functionality
  - [x] Auto-retry on stream failures
  - [x] Buffer size configuration
  - [x] EPG grid view UI (time-based layout with synchronized scrolling, live highlighting)
  - [x] Xtream Codes API integration (live TV channels with categories)

### Planned
- [ ] Phase 3: DVR & Multi-view
  - Recording to local storage
  - Multi-view (up to 4 channels)
  - Recording management
- [ ] Phase 4: Profiles & Parental controls
  - PIN-protected profiles
  - Channel locks and restrictions
  - Viewing history
- [ ] Phase 5: Mobile & TV platforms
  - Android app optimization
  - iOS support
  - TV remote navigation
- [ ] Phase 6: Advanced features
  - Subtitle/audio track selection
  - Streaming quality selection
  - Custom HTTP headers

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
