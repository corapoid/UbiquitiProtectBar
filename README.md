# ProtectBar

A lightweight macOS menu bar application for monitoring UniFi Protect cameras.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Menu Bar Integration** - Quick access to all your cameras from the menu bar
- **Live RTSP Streaming** - Real-time video using MPV with hardware acceleration
- **Flexible Grid Layout** - Choose 2 columns, 4 columns, or single row view
- **Pin to Desktop** - Pin individual cameras as floating windows
- **Hide Cameras** - Right-click to hide cameras you don't need
- **Multiple Auth Methods** - Supports API Key (recommended) or username/password
- **Low Latency** - Optimized for minimal delay with RTSP over TCP
- **Secure** - Credentials stored in encrypted local file (ChaCha20-Poly1305)

## Screenshots

<!-- TODO: Add screenshots -->

## Requirements

- macOS 13.0 (Ventura) or later
- UniFi Protect NVR with RTSP enabled
- Local network access to the NVR

## Installation

### Download

Download the latest release from [Releases](https://github.com/corapoid/UbiquitiProtectBar/releases).

### Homebrew (coming soon)

```bash
brew install --cask protectbar
```

### Build from Source

```bash
git clone https://github.com/corapoid/UbiquitiProtectBar.git
cd macos_ubiquiti_protect_bar/ProtectBar
swift build -c release
```

## Setup

### 1. Enable RTSP on UniFi Protect

1. Open UniFi Protect web interface
2. Go to **Settings** > **Advanced**
3. Enable **RTSP**
4. Note the RTSP port (default: 7447)

### 2. Create API Key (Recommended)

1. Go to **UniFi OS Settings** > **API Access**
2. Click **Create Token**
3. Copy the generated API key

### 3. Configure ProtectBar

1. Click the ProtectBar icon in the menu bar
2. Click the gear icon to open Settings
3. Enter your NVR address (IP or hostname)
4. Choose authentication method:
   - **API Key** (recommended): Paste your API key
   - **Username/Password**: Enter your UniFi account credentials
5. Click **Save & Connect**

## Usage

| Action | How |
|--------|-----|
| View cameras | Click menu bar icon |
| Change grid layout | Use grid buttons in header |
| Pin camera to desktop | Click pin icon on camera |
| Hide camera | Right-click > Hide Camera |
| Show hidden cameras | Click eye icon in header |
| Refresh cameras | Click refresh button |
| Quit | Click power icon |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd + ,` | Open Settings |
| `Cmd + Q` | Quit |

## Troubleshooting

### "Connection failed" error

- Verify NVR address is correct
- Check if RTSP is enabled on the NVR
- Ensure you're on the same network as the NVR

### "Invalid credentials" error

- For API Key: Generate a new token in UniFi OS Settings
- For Username/Password: Verify credentials work in the web interface

### "Access denied (403)" error

- Your account may be temporarily locked due to failed attempts
- Wait a few minutes and try again
- Check if your IP is blocked in NVR settings

### Cameras not loading

- Verify RTSP is enabled for each camera
- Check camera is online in UniFi Protect
- Try a different stream quality setting

### High CPU usage

- Lower the stream quality in Settings
- Reduce number of visible cameras
- Pin only cameras you need to monitor

## Privacy Policy

ProtectBar is designed with privacy as a core principle. Here's exactly what the app does with your data:

### Data Collection

**We do NOT collect:**
- Personal information
- Usage analytics or telemetry
- Camera footage or snapshots
- IP addresses or network information
- Crash reports (unless you manually submit them)

### Data Storage

**Stored locally on your Mac:**

| Data | Location | Encryption |
|------|----------|------------|
| NVR credentials | `~/Library/Application Support/ProtectBar/.credentials` | ChaCha20-Poly1305 (AES-256 equivalent) |
| App settings | `~/Library/Preferences/com.protectbar.plist` | None (non-sensitive) |
| Hidden cameras list | UserDefaults | None (camera IDs only) |

### Network Connections

ProtectBar only connects to:
1. **Your UniFi Protect NVR** - Direct local network connection for API and RTSP streams
2. **GitHub** (optional) - Only for update checks via Sparkle framework

**No data is ever sent to:**
- Our servers (we don't have any)
- Third-party analytics services
- Cloud storage providers

### Encryption Details

Credentials are encrypted using:
- **Algorithm**: ChaCha20-Poly1305 (RFC 7539)
- **Key derivation**: Hardware UUID + app-specific salt
- **Storage**: Local file, not macOS Keychain (for portability)

### Your Rights

You can:
- **Delete all data**: Remove `~/Library/Application Support/ProtectBar/` folder
- **Export settings**: Copy the preferences plist
- **Audit the code**: This project is open source

### Third-Party Dependencies

| Dependency | Purpose | Privacy Impact |
|------------|---------|----------------|
| MPVKit | Video playback | None - local only |
| Sparkle | Auto-updates | Checks GitHub for new versions |

### Contact

For privacy concerns, open an issue on [GitHub](https://github.com/corapoid/UbiquitiProtectBar/issues).

---

## Security

- **Local only** - All connections are direct to your NVR, no cloud services
- **Encrypted credentials** - Stored locally using ChaCha20-Poly1305 encryption
- **No telemetry** - No data is collected or sent anywhere
- **Self-signed certs** - Accepts self-signed certificates from local NVR

## Building

### Requirements

- Xcode 15+ or Swift 5.9+
- macOS 13.0+ SDK

### Build

```bash
cd ProtectBar
swift build
```

### Run

```bash
swift run
```

### Lint

```bash
swiftlint lint
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `swiftlint lint` to check code style
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [MPVKit](https://github.com/mpvkit/MPVKit) - Video playback
- [UniFi Protect](https://ui.com/camera-security) - NVR system

## Disclaimer

This project is not affiliated with or endorsed by Ubiquiti Inc. UniFi and UniFi Protect are trademarks of Ubiquiti Inc.
