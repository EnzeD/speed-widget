# Speed Widget

<img width="332" height="591" alt="image" src="https://github.com/user-attachments/assets/d121c63c-7214-4227-91d0-d85e7aef9fe7" />

Speed Widget is a lightweight macOS menu bar app that shows the current quality of your Internet connection without running a permanent, bandwidth-heavy speed test.

It provides a reactive score out of 100, a rolling five-minute graph, latency, jitter, estimated loss, and an optional on-demand capacity tier. It is designed for “how good is my connection right now?” rather than a precise maximum download-speed benchmark.

## What it measures

The score combines:

- application latency to a nearby edge;
- jitter between recent measurements;
- failed probes, treated as potential packet loss;
- latency inflation observed during normal network activity;
- an optional capacity tier from a manual micro-test.

The score appears after three probes. It deliberately gives priority to the last 15–30 seconds instead of applying heavy smoothing. The chart keeps the last five minutes and resets when the active network interface changes, so separate connections are never mixed.

When meaningful traffic is detected, a separate score is calculated exclusively from probes observed during that traffic. After three loaded probes, the menu bar adds it in parentheses only when it is at least five points below the idle baseline. For example, `88 (58)` means an idle baseline of 88 and a measured loaded experience of 58. If no meaningful degradation is detected, the menu bar keeps the idle score alone. The parenthetical score also disappears when the load stops.

## Privacy and network behaviour

- A zero-byte HTTPS request runs every five seconds, or every 15 seconds when macOS marks the connection as constrained.
- A manual micro-test may download up to 2 MB; it never runs automatically.
- Probes use `https://speed.cloudflare.com/__down`. An Apple HTTPS `HEAD` request is only used as a fallback after a failure or latency above 500 ms.
- Requests use an ephemeral session with no cache, cookies, or stored credentials. Redirects are rejected and response sizes are bounded.
- The app does not collect telemetry, analytics, account details, or measurement results. Results remain on the Mac; the daily transfer counter is stored locally in UserDefaults.

Speed Widget is sandboxed with outbound network access only. Its local build is ad-hoc signed with the hardened runtime, but it is **not notarized** or signed with a Developer ID certificate.

## Install

### Build from source

Requirements: macOS 14 or later and Xcode 16 or later.

```sh
git clone https://github.com/EnzeD/speed-widget.git
cd speed-widget
./scripts/package-app.sh
open "dist/SpeedWidget.app"
```

The script creates `dist/SpeedWidget.app` for the architecture of the Mac that builds it. Because the bundle is ad-hoc signed rather than notarized, macOS may show a first-launch warning. In Finder, Control-click the app, choose **Open**, then confirm **Open**. Do not disable Gatekeeper globally.

### Run during development

```sh
swift run SpeedWidget
```

The score appears in the menu bar. Quit it from the power button in the panel or stop the development process in Terminal.

## Verify the project

```sh
swift test
./scripts/package-app.sh
```

The packaging script verifies the resulting code signature before reporting success.

## Limitations

- HTTPS probes measure application-level latency, not raw ICMP ping.
- A failed HTTP probe can be caused by a third-party endpoint issue; the fallback reduces, but cannot eliminate, false positives.
- The manual micro-test is a capacity tier, not an exact maximum throughput measurement.
- “Under load” relies on counters from the active interface and does not prove the link is saturated.
- A VPN, proxy, captive portal, or unusual routing can change the path being measured.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md), keep changes focused, run `swift test`, and open a pull request against `main`. Never commit credentials, certificates, generated app bundles, or local configuration.

For a suspected security vulnerability, use the private reporting process in [SECURITY.md](SECURITY.md), not a public issue.
