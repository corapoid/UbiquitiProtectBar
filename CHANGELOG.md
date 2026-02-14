# Changelog

All notable changes to ProtectBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Drag and drop camera reordering in grid view
- Camera order persistence across app restarts

### Fixed
- Fix crash when loading camera preview (dangling pointers in MPV software render params)
- Fix use-after-free in MPV callbacks when popover closes during stream playback
- Fix crash from calling draw() directly on MTKView instead of setNeedsDisplay()
- Fix double-shutdown crash when dismantleNSView and deinit both call shutdown()
- Fix deadlock from NSLock in renderFrame/draw/shutdown — replaced with NSRecursiveLock
- Fix race condition: draw() now protected by renderLock to prevent concurrent Metal resource access
- Fix renderFrame() re-checking shutdown state under lock to prevent use-after-free after shutdown
- Fix sendMPVCommand using unsafe withMemoryRebound — now uses properly typed C pointer array
- Fix Unmanaged.passRetained release: releases are now conditional on actual context creation
- Fix renderFrame() capturing local copy of mpvRenderContext to prevent nil dereference after shutdown

## [1.0.0] - 2026-02-13

### Added
- Initial public release
- Menu bar integration with camera grid view
- Live RTSP streaming with MPV player
- Hardware-accelerated video decoding (VideoToolbox)
- API Key authentication (recommended for UniFi OS 3.0+)
- Username/Password authentication (legacy)
- Flexible grid layouts (2 columns, 4 columns, single row)
- Pin cameras to desktop as floating windows
- Hide/show individual cameras
- Stream quality selection (Low/Medium/High)
- Encrypted credential storage (ChaCha20-Poly1305)
- Self-signed certificate support for local NVR
- Rate limiting to prevent API throttling
- Polish and English localization

### Security
- Credentials stored in encrypted file instead of Keychain (avoids repeated password prompts for unsigned apps)
- Hardware UUID-based encryption key derivation
- No cloud services or telemetry

## [0.1.0] - 2026-02-13

### Added
- Initial development version
- Basic camera viewing functionality
- Settings UI for NVR configuration
