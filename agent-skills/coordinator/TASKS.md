# Task chats

One chat per task. The chat owns its branch, worktree, PR, and state. No lead layer.

| Chat | Owns | Status |
|---|---|---|
| Lead — Web Platform → retired | area routing | replaced by task chats |
| Lead — Extensibility → retired | area routing | replaced by task chats |

## A task chat gets

- One feature, one ticket, or one PR. If it needs a second PR, that's a second chat.
- Its own worktree. Never shared.
- A `START` line in the ledger before the first commit.
- Responsibility for keeping its Linear ticket current as it moves.

## A task chat does not

- Route other work. No spawning reports, no managing siblings.
- Hold cross-cutting state. If it needs something from another task, it reads that task's state file.

## Registry

`watch.json` is the live list: thread id → task name → last completed turn. The hourly sweep polls it and reports completions here.
