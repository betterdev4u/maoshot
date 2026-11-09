# MaoShot

A small, fast screenshot tool for macOS (猫 *māo* = cat). Press a shortcut, drag an area, mark it up, copy or save.
Native Swift, universal (Apple Silicon + Intel), no Rosetta, no dependencies. macOS 14 or later.

## Use

| Action | Key |
|---|---|
| Capture | **⇧⌘2**. Change it in the menu bar → Shortcut, or pick **Custom Shortcut…** and press any combo |
| Select, move or resize the area | drag; drag the edge handles |
| Select · Pen · Line · Arrow · Rectangle · Highlighter · Text | V · P · L · A · R · H · T |
| Snap a line or arrow to 45° | hold ⇧ |
| Edit a mark | Select tool → click the mark. Drag to move, drag handles to resize (⇧ keeps proportions), arrow keys to nudge, Delete to remove, click a colour to recolour |
| Undo · Redo | ⌘Z · ⇧⌘Z |
| Copy and close | Return, ⌘C, or double-click the area |
| Save to a file | ⌘S |
| Cancel | Esc |

**Recent:** the last 10 captures are kept, even ones you closed without saving. Menu bar → Recent → Copy, Save, Open, or Show in Finder.

**PrintScreen-style:** choose F13 in Shortcut, or turn off macOS's own ⇧⌘4 (System Settings → Keyboard → Keyboard Shortcuts → Screenshots) and choose ⇧⌘4.

## Install

Build from source:

```bash
./build.sh install
```

Installing a shared copy: unzip, move **MaoShot.app** to Applications, then right-click it → **Open** the first time (it isn't notarized, so macOS asks once).

**Screen Recording access:** on first launch macOS asks for permission. Turn MaoShot on under System Settings → Privacy & Security → Screen & System Audio Recording, and MaoShot restarts by itself. If it's not in the list, use **Show in Finder** in MaoShot's setup window and drag the app into the list.

## Troubleshooting

Menu bar → Troubleshoot:

- **Screen Recording Setup…** opens the setup window.
- **Reset Screen Recording Permission…** for when MaoShot is switched on but still can't capture. This is common after installing a new version, because builds without an Apple developer certificate look like a new app to macOS.
- **Copy Diagnostics Report** and **Show Log** (`~/Library/Logs/MaoShot.log`) for bug reports.

## Develop

```bash
swift test                                  # unit tests
./build.sh                                  # build/MaoShot.app
./build.sh dist                             # build/MaoShot-<version>.zip
swift run MaoShot --render-demo /tmp/demo   # render the overlay UI to PNGs, no permission needed
```

`build.sh` signs with an Apple Development or Developer ID certificate if your keychain has one (`SIGN_ID` overrides it). With a certificate, the Screen Recording permission survives updates. Without one the build is signed ad-hoc. To share publicly without the right-click step, sign with Developer ID and notarize.
