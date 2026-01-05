# SeekQool

**The PostgreSQL client that doesn't suck.**

A native macOS app for developers who want to browse, query, and edit their Postgres data without the bloat.

![SeekQool Screenshot](assets/hero.png)

### See it in action

[![How SeekQool works](assets/video-thumbnail.png)](https://vimeo.com/1150826039)

---

## Why SeekQool?

You've tried them all. Electron apps that eat 2GB of RAM. Java tools from 2008. Web UIs that feel like swimming through molasses.

SeekQool is different:

- **Native macOS** — Built with SwiftUI. Launches instantly. Uses ~50MB of memory.
- **Edit inline** — Double-click any cell. Change it. Preview the SQL. Push.
- **Smart queries** — Write `SELECT email FROM users` and still edit the results. We handle the primary keys.
- **Stay connected** — Laptop sleep? Network blip? SeekQool reconnects automatically.
- **Remember everything** — Your tabs, queries, and sort orders persist across sessions.

---

## Features

### Browse Tables

Click a table. See the data. Sort by any column. Paginate through millions of rows.

![Table Browser](assets/table-browser.png)

### Edit Anything

Double-click a cell to edit. Right-click to set NULL. See exactly what SQL will run before you commit.

![Inline Editing](assets/inline-edit.png)

### Query Editor

Write raw SQL. Get results. Edit them too (for simple SELECTs).

![Query Editor](assets/query-editor.png)

### SQL Preview

Never push blind. Review every UPDATE statement before it hits your database.

![SQL Preview](assets/sql-preview.png)

---

## Installation

### Download

Grab the latest release from [GitHub Releases](https://github.com/foxwise-ai/seekqool/releases):

1. Download `SeekQool-x.x.x.dmg`
2. Open the DMG
3. Drag **SeekQool** to **Applications**
4. Launch from Applications (or Spotlight)

> Works on both Apple Silicon and Intel Macs.

### Build from Source

```bash
git clone https://github.com/foxwise-ai/seekqool.git
cd seekqool/macOS
./scripts/build.sh
./scripts/install.sh
```

App installs to `~/Applications/SeekQool.app`.

### Manual Build

```bash
cd seekqool/macOS
swift build -c release
```

Binary lands in `.build/release/SeekQool`.

---

## Quick Start

1. Launch SeekQool
2. Click **+** to add a connection
3. Enter your Postgres credentials
4. Double-click a table to browse
5. Double-click a cell to edit

That's it. No setup wizards. No configuration files. No bullshit.

---

## Requirements

- macOS 14.0+
- PostgreSQL 12+ (any standard Postgres-compatible database)

---

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Run Query | `⌘ + Return` |
| New Query Tab | `⌘ + T` |
| Close Tab | `⌘ + W` |
| Refresh | `⌘ + R` |

---

## Roadmap

- [ ] Multiple result sets
- [ ] Export to CSV/JSON
- [ ] Table structure editor
- [ ] Dark mode refinements
- [ ] SSH tunneling

---

## Built With

- **SwiftUI** — Native macOS UI
- **PostgresNIO** — Async PostgreSQL driver
- **Swift Concurrency** — Modern async/await

---

## License

MIT

---

## Contributing

Found a bug? Want a feature? Open an issue or submit a PR.

### Creating a Release

To publish a new version:

```bash
# Tag the release
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions will automatically:
- Build a universal binary (Apple Silicon + Intel)
- Create a DMG and ZIP
- Publish to [GitHub Releases](https://github.com/foxwise-ai/seekqool/releases)

---

## Other Projects

Check out [TheQuickFox.ai](https://www.thequickfox.ai/) —  Ask AI from any app about any app without breaking your flow. Special feature: reply to any message/email using a few words.

---

<p align="center">
  <strong>Stop fighting your database tools. Start shipping.</strong>
</p>
