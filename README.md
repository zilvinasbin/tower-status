# Tower menu bar

macOS menu bar app that shows Tower's status. It polls Tower's read-only
`GET /dash.json` (schema 2) over Tailscale every 10 s and never changes Tower state.

- Menu bar: tower icon + `1/3` (slots busy/allocated), amber `⚠5` when items need you,
  `–` dimmed when Tower doesn't answer or the snapshot is stale (> 60 s).
- Panel (click the icon): what needs you, slot cells and queue, running agents as
  state-coloured strips (click opens the ticket), memory/disk/CPU meters with the 90 %
  limit marked, Tower's warnings, Open dashboard, Refresh, Quit.
- Settings (gear in the panel): Tower address (**IP literal**, e.g. `100.x.y.z`, port
  8090 by default; host names get `421`), refresh interval 5–60 s, notifications when
  something new needs you (off by default), open at login.
- Opening Tower.app again while it runs opens the panel (handy if a menu bar manager
  hides the icon).

```sh
./build.sh            # builds build/Tower.app (sandboxed, ad-hoc signed)
./build.sh --install  # also copies it to ~/Applications
./test.sh             # unit tests
build/Tower.app/Contents/MacOS/TowerBar --print 100.x.y.z   # poll once, print the lines
.build/debug/TowerBar --snapshot out.png 100.x.y.z [settings]  # render the panel (DARK=1 for dark)
```

`TowerCore` holds the decoding, display rules and states (pure, unit-tested);
`TowerBar` is the AppKit status item. Open `Package.swift` in Xcode to work on it.
