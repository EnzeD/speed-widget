# Speed Widget

Speed Widget is a minimalist macOS menu bar app that estimates Internet connection quality without running a permanent speed test.

The score out of 100 combines:

- application latency to a nearby edge;
- jitter between successive measurements;
- probe failures treated as packet loss;
- latency inflation observed during natural network activity;
- an optional capacity tier from a manual micro-test.

The panel also displays a score chart over a rolling five-minute window. The history resets when the network interface changes so two connections are not mixed.

## Run in development

Requirements: macOS 14 or later and Xcode 16 or later.

```sh
swift run SpeedWidget
```

The Wi-Fi icon and score appear in the menu bar. Stop the process from the terminal or use the power button in the panel.

## Build the app

```sh
./scripts/package-app.sh
open "dist/SpeedWidget.app"
```

The script creates a locally signed app at `dist/SpeedWidget.app`.

## Tests

```sh
swift test
```

## Network usage

- a zero-byte request runs every five seconds;
- the score appears after three probes, with no exponential smoothing;
- latency reflects roughly 15 seconds and stability roughly 30 seconds;
- the interval increases to 15 seconds on a network macOS marks as constrained;
- `URLSession` metrics approximately track headers and connection overhead;
- daily usage is displayed with no cap or automatic stop;
- the micro-test is manual only and capped at 2 MB.

The MVP uses `https://speed.cloudflare.com/__down`, the public endpoint of the Cloudflare Speedtest engine. An Apple `HEAD` request is only triggered to confirm a failure or latency above 500 ms. Speed Widget sends no analytics results.

## MVP limitations

- HTTPS requests measure application latency, not a raw ICMP ping.
- A lost HTTP probe may reflect a server issue; the secondary probe reduces this false positive but cannot eliminate it completely.
- The 2 MB micro-test provides a capacity tier, not an exact maximum throughput measurement.
- “Under load” detection relies on counters from the active network interface and does not guarantee that the link is saturated.
- A VPN can change the measured path and interface selection.

The next natural evolution is a small dedicated QUIC endpoint: an encrypted echo of a few dozen bytes would further reduce usage and make loss measurement more direct.
