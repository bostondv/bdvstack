# bdvstack

Boston's personal Claude Code plugins and agent skills.

## Layout

| Path | What it is |
| --- | --- |
| `claude-plugins/` | Claude Code plugins, published through the marketplace below. |
| `agent-skills/` | Portable agent skills — instructions and scripts, no personal data. |
| `.claude-plugin/` | The marketplace manifest. Stays at the root so `/plugin marketplace add` finds it. |

## Plugins

Add the marketplace, then install whichever plugins you want.

```text
/plugin marketplace add bostondv/bdvstack
```

```text
/plugin install autopilot@bdvstack
/plugin install cmux@bdvstack
/plugin install go@bdvstack
/plugin install pr-patrol@bdvstack
/plugin install stacked-prs@bdvstack
/plugin install sync-claude@bdvstack
/plugin install todos@bdvstack
/plugin install using-gh-stack@bdvstack
```

| Plugin | What it does |
|--------|--------------|
| `autopilot` | Autonomous SWE agent loop — turns a feature description into a reviewed PR. |
| `cmux` | Terminal multiplexer control — manipulate panes, splits, tabs, and surfaces. |
| `go` | `/go` ship-it loop — build, review, verify, simplify, then open a draft PR. |
| `pr-patrol` | Babysit open PRs and sweep merged PRs for missed review feedback. |
| `stacked-prs` | Manage stacked PR workflows — create, rebase, push, track. |
| `sync-claude` | Sync Claude Code settings between machines via a dotfiles git repo. |
| `todos` | Persistent file-based todos with groups, priorities, and worktree-based execution. |
| `using-gh-stack` | Drive `instacart/gh-stack` — rebases and chains of dependent pull requests. |

Update later with `/plugin marketplace update bdvstack`.

## Skills

`agent-skills/` holds four skills that work outside the plugin system. They are
plain folders of instructions plus a few scripts, so symlink or copy whichever
you want into your agent's skills directory:

```bash
SKILLS_ROOT="${SKILLS_ROOT:-$HOME/.codex/skills}"   # or ~/.claude/skills on Claude Code
ln -s "$PWD/agent-skills/pr-watch" "$SKILLS_ROOT/pr-watch"
```

| Skill | What it does |
| --- | --- |
| `pr-watch` | Watches a PR you just opened: CI failures, review comments, conflicts. |
| `coordinator` | Chief-of-staff loop — queue of decisions, ledger, one chat per task. |
| `writing` | Rules for anything a human reads, with a voice style card and an eval. |
| `agent-memory` | Standing preferences, operating rules, and past mistakes. |

### Paths

The skills were written for a `~/.codex/skills` layout. Every install-root
reference is now the `SKILLS_ROOT` variable, with `$HOME/.codex/skills` as the
fallback, so an unmodified setup works with no configuration:

```bash
export SKILLS_ROOT="$HOME/.claude/skills"
```

### What is not here

Personal data stays out of this repo, and `.gitignore` enforces it:

- No corpus of my writing — `agent-skills/writing/voice/corpus/` and `raw/` are ignored.
- No generated profile or stats files.
- No state: no `queue.json`, no `prs.json`, no `LESSONS.md`, no ledgers.
- No launchd plists.

Each skill creates its own state on first run. See the `README.md` inside
`coordinator/state/` and the notes in `writing/voice/`.

## Recommended companions

`autopilot`'s optional VALIDATE phase drives the browser via [`agent-browser`](https://www.npmjs.com/package/agent-browser) and reads `.browser-check/config.yaml` + `.browser-flows/flows.yml` (the **browser-check** skill format from the Gohan plugin). For UI features:

- Install `agent-browser`: `gohan install agent-browser` or `npm install -g agent-browser && agent-browser install`
- The first `/autopilot` run that opts into the verification loop on a UI feature will offer to scaffold `.browser-check/` for you with your local dev URL.

If `agent-browser` is missing, browser scenarios in VALIDATE are SKIPPED non-blockingly — the loop still ships the PR, just without runtime UI verification.
