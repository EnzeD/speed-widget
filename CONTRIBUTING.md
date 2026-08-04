# Contributing to Speed Widget

Thanks for helping make Speed Widget clearer, safer, and more useful.

## Development setup

You need macOS 14 or later and Xcode 16 or later.

```sh
git clone https://github.com/EnzeD/speed-widget.git
cd speed-widget
swift test
swift run SpeedWidget
```

To create a local app bundle, run:

```sh
./scripts/package-app.sh
```

The generated app is intentionally ignored by Git and lives at `dist/SpeedWidget.app`.

## Before opening a pull request

- Keep each change focused and explain its user impact.
- Run `swift test`.
- If you modify packaging or entitlements, also run `./scripts/package-app.sh` and verify the resulting app launches.
- Keep the interface and documentation in English.
- Do not commit generated bundles, `.build`, local configuration, certificates, provisioning profiles, API keys, tokens, or other credentials.
- Use a Conventional Commit-style message when possible, such as `fix(probe): reject unexpected redirects`.

## Security issues

Do not disclose security bugs in a public issue or pull request. Follow [SECURITY.md](SECURITY.md) instead.

## Pull requests

Fork the repository, create a focused branch, and open a pull request against `main`. Describe the problem, the solution, and how you tested it. Changes that affect probes or measurement logic should include or update tests where practical.
