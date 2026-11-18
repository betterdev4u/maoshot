# Contributing

Thanks for helping. Small, focused pull requests are easiest to review.

## Set up

Needs macOS 14+ and Swift 5.9+ (Xcode or the Command Line Tools).

```bash
git clone https://github.com/betterdev4u/maoshot.git
cd maoshot
swift test            # run the unit tests
./build.sh install    # build, install to /Applications and launch
```

`swift run MaoShot --render-demo /tmp/demo` renders the overlay to PNGs without Screen Recording permission, handy for checking UI changes.

## Before opening a PR

- `swift test` passes. Put drawing, geometry and history logic in `MaoShotCore` and add a test for it.
- Keep the app dependency-free and offline: no network calls, no analytics.
- Match the existing style: small files, short comments that explain *why*.
- If you change user-visible behaviour, update the README and `CHANGELOG.md`.

## Reporting bugs

Open an issue with your macOS version, what you did, and the diagnostics report (menu bar → Troubleshoot → Copy Diagnostics Report).

## Permission gotcha

Ad-hoc signed builds lose Screen Recording permission on every rebuild. Sign with an Apple Development certificate (free Apple ID in Xcode) so it persists while you develop. See the README.
