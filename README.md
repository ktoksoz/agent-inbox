# agent-inbox

One inbox for every Claude Code session that is waiting on you.

When you run many agent sessions across many projects, it is easy to miss the one that stopped to ask for a permission, posed a question, or simply finished its turn. **agent-inbox** collects those moments from *all* your sessions into a single pane beside the chat, grouped by project, oldest first. Click a row to jump to that session.

- Works for every project at once: one user-level install, no per-project setup.
- Shows what each agent wants from you: permission request (with the tool and command), a question (AskUserQuestion / plan approval), or "turn finished, waiting for input", plus how long it has been waiting.
- One record per session: it appears when the agent waits, disappears when you answer or the session ends.
- Jump to the session: in Claude Desktop (Code tab) the row opens that session; for terminal sessions the pane shows and copies `claude --resume <id>`.
- Languages: English, Türkçe, Deutsch, Français, Español (auto-detected, or set in the plugin's options).

## How it works

1. **Hooks** (declared in `hooks/hooks.json`, run `scripts/inbox-hook.sh`) fire on `PermissionRequest`, `Notification`, `PreToolUse` (AskUserQuestion / ExitPlanMode) and `Stop`, and write one JSON line per waiting session to `~/.claude/inbox.jsonl`: session id, project folder, session title, kind, a short summary, a timestamp and, for Claude Desktop sessions, the app's deep link. `UserPromptSubmit`, `PostToolUse`, `PermissionDenied`, `SessionStart` and `SessionEnd` remove the record. Writes are serialised with a lock; the script always exits 0 and takes about 50 ms.
2. **The pane** (`hooks/register.tsx`, a Claude Code function-hooks module) polls the file every 1.5 s, redraws when it changes, groups entries by project and sorts by waiting time. `/inbox` opens it; in Claude Desktop it opens by itself (`autoOpen` option).

## Install

At the prompt of a terminal Claude Code session:

```
/plugin install agent-inbox --marketplace ktoksoz/agent-inbox
```

From a shell:

```
claude plugin install agent-inbox --marketplace ktoksoz/agent-inbox
```

In the Claude desktop app, where `/plugin` does not run: click **+** next to the prompt box, then **Plugins**, **Add marketplace** with `ktoksoz/agent-inbox`, then **Add plugin**.

Choose the **user** scope so the hooks run in every project. Requires `jq` (preinstalled on macOS 15+; `brew install jq` / `apt install jq` otherwise).

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `language` | `auto` | `auto`, `en`, `tr`, `de`, `fr`, `es`. `auto` reads `LANG`, then the macOS system language. |
| `autoOpen` | `true` | Open the pane when a Claude Desktop session starts. |
| `inboxPath` | `~/.claude/inbox.jsonl` | Where the hook writes. |

Set them with `/plugin configure agent-inbox` or `claude plugin install … --config language=tr`.

## Limitations

- Jumping to a session works for Claude Desktop (Code tab) sessions on macOS, through the app's `claude://` link. Terminal sessions cannot be focused from the pane; their `claude --resume <id>` command is shown and copied instead.
- Chats outside the Code tab (the regular Claude chat, claude.ai) have no hooks and never appear.
- A session that crashes without `SessionEnd` is pruned when its process is gone; a stale record can also be dismissed from the pane.

## Uninstall

```
claude plugin uninstall agent-inbox
```

Then delete `~/.claude/inbox.jsonl` if you like. Nothing else is written outside the plugin folder.

## Development

```
claude plugin validate .
claude plugin test .
```

The hook script can be exercised alone: pipe a hook payload into `scripts/inbox-hook.sh`, or run `scripts/inbox-hook.sh --remove <session_id>`. Touch `~/.claude/inbox.debug` to log every payload it receives to `~/.claude/inbox-debug.log`.

---

## Türkçe

Aynı anda birçok projede birçok agent oturumu çalıştırırken hangisinin sizden bir şey beklediğini (izin, soru, turunu bitirip girdi bekleme) sohbetin yanında duran tek bir panelde, proje bazında ve en eski bekleyen üstte görürsünüz. Satıra tıklayınca Claude Desktop'taki o oturuma geçilir; terminal oturumları için `claude --resume <id>` komutu gösterilir ve panoya kopyalanır.

Kurulum (terminaldeki bir Claude Code oturumunda): `/plugin install agent-inbox --marketplace ktoksoz/agent-inbox`, kapsam olarak **user** seçin. Dil `language` seçeneğiyle (`tr`) ayarlanır; `auto` sistem dilini kullanır. Kaldırma: `claude plugin uninstall agent-inbox`.
