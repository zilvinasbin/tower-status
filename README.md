# Tower menu bar

macOS menu bar app that shows Tower's status. It polls Tower's read-only
`GET /dash.json` (schema 2) over Tailscale every 10 s and never changes Tower state.

- Title: `T 1/3` (slots occupied/allocated), `T 1/3 · ⚠5` when items need you,
  `T –` dimmed when Tower doesn't answer or the snapshot is stale (> 60 s).
- Menu: slots, needs-you (submenu), queue, host MEM/DISK/CPU (amber over the limits),
  running agents (click opens the ticket), Tower warnings, Open dashboard, Refresh now,
  Settings…, Quit.
- Settings: Tower address (**IP literal**, e.g. `100.x.y.z`, port 8090 by default;
  host names get `421`), poll interval 5–60 s, needs-you notifications (off by default),
  launch at login.

```sh
./build.sh            # builds build/Tower.app (sandboxed, ad-hoc signed)
./build.sh --install  # also copies it to ~/Applications
./test.sh             # unit tests
build/Tower.app/Contents/MacOS/TowerBar --print 100.x.y.z   # poll once, print the menu
```

`TowerCore` holds the decoding, display rules and states (pure, unit-tested);
`TowerBar` is the AppKit status item. Open `Package.swift` in Xcode to work on it.
