# Save My Space

**English** · [Italiano](README.it.md)

Analyzes your macOS home folder and suggests what to clean up. Use it from the command line
(`smspace`) or through an optional SwiftUI app. Available in English and Italian.

**Safe by default:** `scan` changes nothing; `clean` moves items to the **Trash** (never a
permanent delete), only after explicit confirmation, and every cleanup is recorded in a history
so it can be undone with `restore`.

## What it looks for

| Category | Examples | Risk |
|---|---|---|
| Caches | `~/Library/Caches/*`, Homebrew, pip | safe |
| Logs | `~/Library/Logs` | safe |
| Development | DerivedData, DeviceSupport, npm/Gradle caches, `node_modules`/`.venv`/`target`/`build` of idle projects | safe / review |
| Old downloads | `.dmg`/`.pkg` installers, files unused for more than 90 days | review |
| Large files | files over 500 MB in your folders | review |
| Duplicates | files with identical content (SHA-256) | review |
| App data | large folders in Application Support, Games, `~/.something` | caution |
| iOS backups, Mail, Messages, Docker, Trash | | report-only or caution |

iCloud Drive, CloudStorage and the Photos library are never scanned.

## Usage

```sh
smspace                          # = scan
smspace scan --limit 50
smspace scan --category caches,developer --risk safe
smspace scan --json > report.json
smspace scan -o report.md        # save the report (.md, .csv, .json)
smspace scan --large-size 1G --older-than 180d --no-duplicates

smspace clean --dry-run          # what would be moved (only "safe" risk)
smspace clean                    # asks for confirmation, then moves to the Trash
smspace clean --risk review -i   # confirm item by item
smspace clean --yes              # no confirmation: only allowed for "safe" risk

smspace history                  # cleanup history (numbered: #1 = most recent)
smspace history -d               # with each item and where it is in the Trash
smspace restore                  # restore the last cleanup
smspace restore --entry 2 --path ~/Library/Caches/pip   # one item of an earlier cleanup

smspace gui                      # open the graphical interface
```

## Language

The language is chosen in this order: the `--lang en|it` option, the `SMSPACE_LANG`
environment variable, the system language; English is used if none is supported.

```sh
smspace --lang it scan
SMSPACE_LANG=en smspace history
```

In the app, change it from *Settings* (Automatic / English / Italiano).

## Reports, history and restore

- `scan -o report.md` (or `.csv`, `.json`) saves the suggestions shown, with the same filters.
- `clean --dry-run --report proposal.md` saves what *would* be moved.
- Every `clean`, from the CLI or the app, is recorded in
  `~/Library/Application Support/save-my-space/history.jsonl`: original path, size, category
  and **location in the Trash**. `clean --report cleanup.md` also saves the summary of that
  cleanup; `history -o history.csv` exports the history.
- `restore` puts items back in their original location while they are still in the Trash.
  It never overwrites anything: if the location is taken, the item stays in the Trash.
- In the app: *Report* menu › *Export report…* / *Show cleanup history* / *Restore last cleanup…*.

For a complete analysis, grant *Full Disk Access* to your terminal
(System Settings › Privacy & Security).

## Building

Requires macOS 14+ and Swift 6.

```sh
swift build                  # debug CLI + app
swift run smspace
swift run SaveMySpaceApp
make app                     # builds dist/Save My Space.app
make install                 # `smspace` CLI in ~/.local/bin, app in ~/Applications
make test                    # tests (require Xcode)
```

## Layout

- `Sources/SaveMySpaceCore` — scanning, rules, reports, Trash, restore, localization
- `Sources/smspace` — CLI (swift-argument-parser)
- `Sources/SaveMySpaceApp` — SwiftUI interface
- `Tests/SaveMySpaceCoreTests` — tests on fake home folders in temporary directories

## License

Copyright © 2026 homecla.

Save My Space is free software: you can redistribute it and/or modify it under the terms of the
[GNU Affero General Public License v3.0](LICENSE). Third-party components and their licenses
are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
