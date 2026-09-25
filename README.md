# Bandwidth Tracker

A small macOS menu bar app that tracks network usage in real time. It lives in the
menu bar and shows live download/upload speed, how much data you've used today, a
per-interface breakdown, and a weekly/monthly recap plus a built-in speed test.

Written in SwiftUI + AppKit, no third-party dependencies.

## Features

- Live download/upload speed with a 60-second sparkline
- Daily total that resets automatically at 00:00 WIB (Asia/Jakarta)
- Per-interface counters (Wi-Fi, Ethernet, VPN tunnels, AirDrop, …)
- Recap tab: this-week bar chart, this-month total, and a calendar heatmap of daily usage
- Built-in speed test — ping, download and upload against Cloudflare
- Preferences: theme (auto / light / dark) and background (translucent / solid color / your own image)

## How it works

Byte counters are read from the kernel with `sysctl(NET_RT_IFLIST2)`, which exposes the
64-bit `if_data64` counters. (The more common `getifaddrs` only gives 32-bit counters
that wrap every ~4 GB.) Usage is accumulated as per-interface deltas once per second, so
the daily total stays correct even when interfaces come and go — a VPN dropping or an
AirDrop transfer no longer looks like a counter reset.

Daily history is persisted to `UserDefaults` as JSON, keyed by date in the Asia/Jakarta
timezone, and flushed on a throttle so it doesn't hammer the disk.

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ / Xcode 15 command line tools (`xcode-select --install`)

## Build

Build a signed `.app` bundle and install it to `/Applications`:

```bash
./build_app.sh
```

Or run it straight from the package without bundling:

```bash
swift run -c release
```

## Install

Move `Bandwidth Tracker.app` into `/Applications`. To start it automatically at login,
add it under System Settings → General → Login Items.

The bundle is signed ad-hoc, so the first launch may need a right-click → Open to get
past Gatekeeper.

## Notes and limitations

- macOS doesn't let third-party apps read per-app data usage the way the Settings app
  can. Usage here is measured at the interface level — total system traffic, not per
  application.
- "Today" counts traffic only while the app is running. Anything transferred while it's
  closed isn't measured.
- The daily reset is fixed to WIB (Asia/Jakarta).

## License

MIT — see [LICENSE](LICENSE).
