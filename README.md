# DDRDesk iOS

Native **iPhone and iPad** client for [ddrdesk-host](https://github.com/ddr-ai/ddrdesk-host). Sideload the unsigned `.ipa` produced by GitHub Actions.

## Why native Swift

| Piece | Choice | Why |
|---|---|---|
| UI | **SwiftUI** | iPhone + iPad from one target (`TARGETED_DEVICE_FAMILY = 1,2`). |
| Keyboard | **System `UITextField`** | Requirement: the device’s **native** keyboard, including on the Fedora login greeter. No custom keyboard view. Hidden first-responder forwards inserts/deletes. |
| Pointer | **UIKit trackpad overlay** | One-finger drag = relative move, tap = left click, quick double-tap = right click. |
| Video | **VideoToolbox / `AVSampleBufferDisplayLayer`** | Hardware H.264 decode, aspect-fit so the whole desktop is visible without pinch-zoom. |
| Network | **Network.framework TLS 1.3** | Talks directly to the host. `TCP_NODELAY`, ALPN `ddrdesk/1`, TOFU cert pin. No relay. |
| Discovery | **Bonjour `_ddrdesk._tcp`** | Match the 9-digit ID on LAN. After pairing, WAN uses cached host endpoints (UPnP/STUN mapped). |
| Reconnect | Exponential backoff 0.5s → 10s | Banner on disconnect; host keeps listening. |

## Download, sign, install

GitHub Actions builds an **unsigned arm64 device IPA** on every push to `main` (and via **Actions → Build unsigned IPA → Run workflow**).

**Download (easiest):** [DDRDesk.ipa](https://github.com/ddr-ai/ddrdesk-ios/releases/download/unsigned-ipa/DDRDesk.ipa)  
Release page: https://github.com/ddr-ai/ddrdesk-ios/releases/tag/unsigned-ipa

The IPA has **no** signature and **no** provisioning profile. Sign it with your Apple ID, then install:

1. **Sideloadly** (Windows/macOS): open `DDRDesk.ipa`, sign in with your Apple ID, install to the iPhone.
2. **AltStore / AltServer**: sideload the IPA; it re-signs with your Apple ID.
3. **Mac + Xcode**: `codesign` / Xcode “Signing & Capabilities” with your team, then install.

Bundle ID is `ai.ddr.DDRDesk`. On first launch, allow **Local Network** (mDNS).

To build locally on a Mac:

```bash
xcodebuild -project DDRDesk.xcodeproj -scheme DDRDesk -sdk iphoneos \
  -configuration Release CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

## Use

1. Install and start the host (`ddrdeskd --print-id`).
2. Open DDRDesk, type the 9-digit ID, **Connect**.
3. The system keyboard is used for typing (login included).
4. Drag one finger to move the pointer; tap to left-click; quick double-tap to right-click.
5. Rotate the device — the host rescales immediately.
6. If the network drops, the app shows **Disconnected — retrying…** and reconnects with backoff. The host stays up.

First connection is easiest on the same Wi-Fi (mDNS). After that the app remembers the host’s public address and can reconnect from another network without a central server.

## Protocol

See [PROTOCOL.md](PROTOCOL.md).
