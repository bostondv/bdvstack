# Coordinator state

Everything in this folder except this README is runtime state and is gitignored.
It is created on first run; a clean clone has only this file.

| File | Written by | Holds |
| --- | --- | --- |
| `LEDGER.md` | everyone | append-only decision log, newest at top |
| `queue.json` | coordinator | the items waiting on you; the only thing that reaches you |
| `watch.json` | coordinator | live task chats, thread id to last completed turn |
| `decisions.json` | the app | answers you gave in the Agent Queue |
| `surfaced.json` | coordinator | what has already been shown, so nothing repeats |
| `WRITES.md` | everyone | one line per Linear write |
| `NOTICES.md` | coordinator | short-lived notices |
| `web-platform.md`, `extensibility.md` | area owners | current state per area, overwritten each run |

`PROTOCOL.md` in the parent folder is the spec for all of it. Do not commit any of
these files: they are one person's working record, and the repo is shared.
