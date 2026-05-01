# bdvstack

Boston's personal Claude Code plugins.

## Install

Add the marketplace, then install whichever plugins you want.

```text
/plugin marketplace add bostondv/bdvstack
```

Then install individual plugins:

```text
/plugin install autopilot@bdvstack
/plugin install cmux@bdvstack
/plugin install go@bdvstack
/plugin install pr-patrol@bdvstack
/plugin install stacked-prs@bdvstack
/plugin install sync-claude@bdvstack
/plugin install todos@bdvstack
```

## Plugins

| Plugin | What it does |
|--------|--------------|
| `autopilot` | Autonomous SWE agent loop — turns a feature description into a reviewed PR. |
| `cmux` | Terminal multiplexer control — manipulate panes, splits, tabs, and surfaces. |
| `go` | `/go` ship-it loop — build, review, verify, simplify, then open a draft PR. |
| `pr-patrol` | Babysit open PRs and sweep merged PRs for missed review feedback. |
| `stacked-prs` | Manage stacked PR workflows — create, rebase, push, track. |
| `sync-claude` | Sync Claude Code settings between machines via a dotfiles git repo. |
| `todos` | Persistent file-based todos with groups, priorities, and worktree-based execution. |

## Update

```text
/plugin marketplace update bdvstack
```

## Recommended companions

`autopilot`'s optional VALIDATE phase drives the browser via [`agent-browser`](https://www.npmjs.com/package/agent-browser) and reads `.browser-check/config.yaml` + `.browser-flows/flows.yml` (the **browser-check** skill format from the Gohan plugin). For UI features:

- Install `agent-browser`: `gohan install agent-browser` or `npm install -g agent-browser && agent-browser install`
- The first `/autopilot` run that opts into the verification loop on a UI feature will offer to scaffold `.browser-check/` for you with your local dev URL.

If `agent-browser` is missing, browser scenarios in VALIDATE are SKIPPED non-blockingly — the loop still ships the PR, just without runtime UI verification.
