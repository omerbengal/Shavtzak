# Claude Code — health report & cleanup plan

**Generated:** 2026-07-27 · **Nothing has been changed.** This file is a handoff so the cleanup can be applied in a later session.

**Scan window:** 50 most-recently-modified session transcripts across 3 projects, 2026-07-22 → 2026-07-27 (6 days, 42 MB). Lifetime usage counters span 121 startups since install. Six days judges daily-use tools well; it does **not** judge something you'd reach for monthly — noted per item where it matters.

> Token figures are estimates (chars ÷ 4) from disk. Run `/context` for the live measurement.

---

## TL;DR

The setup is healthy. Install is clean, version is current, auto mode is already the default, nothing is being denied repeatedly.

Two real findings:

1. **`CLAUDE.md` contains a factually wrong line** — it says there are no tests; there are 486 passing. This misleads every session.
2. About a third of `CLAUDE.md` is content a session can derive by reading the repo (~2,356 est. tokens).

Plus four unused extensions worth turning off. All changes below are reversible.

---

## Current state

| Component | Type | Scope | Uses (total since install) | Used in window? | Est. resident tokens | Verdict |
|---|---|---|---|---|---|---|
| `superpowers` | plugin | user | 190 | ✅ 13 skill runs | ~1.6k (listing) | keep |
| `firebase` | plugin | user | 96 | ✅ 3 tool calls | deferred | keep |
| `playwright` | plugin | user | 5 | ✅ 5 tool calls | deferred | keep |
| `clangd-lsp` | plugin | user | 3 (last 2026-07-11) | ❌ | ~0 | remove |
| `ui-ux-pro-max` | plugin | user | 0 plugin / 1 skill (2026-05-10) | ❌ | ~175 | remove |
| `knesset-seedance-scenes` | skill | user | 2 (last 2026-05-27) | ❌ | ~238 | remove (weak — see note) |
| `find-skills` | skill | user | 0 | ❌ | ~79 | remove |
| `knesset-seedance-scenes-workspace/` | stray dir | user | — | — | 0 (not loadable) | delete (optional) |
| `knesset-seedance-scenes.skill` | stray file | user | — | — | 0 (not loadable) | delete (optional) |
| `CLAUDE.md` (project) | memory | checked-in | — | always loaded | ~7,992 | trim ~2,356 |
| Gamma / Gmail / Calendar / Drive | claude.ai connectors | account | n/a (no counter) | ❌ | deferred | see note |

**Connectors note:** zero calls in the window, but they're managed in your claude.ai account, not any local file — no local edit can disable them. Their schemas are deferred (fetched on demand), so they cost nothing in context. Only worth disabling in claude.ai settings if you want fewer connections to maintain.

---

## Actions

### A. Disable 2 unused plugins

File: `~/.claude/settings.json` → existing `enabledPlugins` object. Flip both to `false`:

```json
"clangd-lsp@claude-plugins-official": false,
"ui-ux-pro-max@ui-ux-pro-max-skill": false
```

- `clangd-lsp` is a C/C++ language server; this is a Dart/Flutter repo. Caveat: LSP usage is only visible via its counter (transcripts can't attribute LSP activity) and that tracking shipped recently, so its lifetime `3` may undercount.
- **Scope warning:** these are *user-scope* — disabling applies to **every** project, not just Shavtzak. Matters for `clangd-lsp` if you have C/C++ work elsewhere.
- Undo: set back to `true`, or use `/plugin`.

### B. Disable 2 unused skills

File: `~/.claude/settings.json` → add (no `skillOverrides` key exists yet):

```json
"skillOverrides": {
  "knesset-seedance-scenes": "off",
  "find-skills": "off"
}
```

- **`knesset-seedance-scenes` is the weakest recommendation here.** 2 uses since install, last 2026-05-27, ~238 est. tokens. You clearly built it deliberately (there's a companion workspace dir), and a 6-day window can't see a monthly-use tool. Reasonable to skip.
- `find-skills` has zero uses ever.
- Undo: remove the entry or set to `"on"`.

### C. Trim `CLAUDE.md` (the main finding)

**C1 — fix the wrong line.** Line 526 currently reads:

```
- **Testing**: Test infrastructure exists (`bloc_test`, `mockito`, `fake_cloud_firestore`) but no tests implemented yet
```

There are **486 passing tests** (`cd shavtzak && flutter test`). Replace with the real state. This is the highest-value single edit in this document — it's not bloat, it's misinformation.

**C2 — cut derivable content.** 232 lines / ~2,356 est. tokens. `CLAUDE.md` goes 31,971 → 22,545 chars (both under the 40,000-char warning threshold, so this is about signal, not silencing a warning).

> ⚠️ **Line numbers are from the 2026-07-27 version and shift as you cut.** Work **bottom-up** (largest line number first), or match on the section heading.

| Section heading | Lines | Est. tokens | Why it's derivable |
|---|---|---|---|
| `## Best Practices Summary` | 736–748 | ~256 | restates rules already stated above |
| `## File Organization` | 628–708 | ~776 | `ls`/`find` shows this |
| `## Features Implemented` | 541–588 | ~464 | a changelog; git and the code say it |
| `## Key Architectural Principles` | 530–540 | ~180 | restates the Architecture section |
| `## Screen Reference` | 304–340 | ~418 | repo tour of `lib/presentation/screens/` |
| Role enumeration inside `### Role-Based System` | 234–246 | ~141 | it's `role_types.dart` |
| Flutter command boilerplate inside `### Flutter Web Commands` | 23–51 | ~119 | `flutter pub get`/`run`/`build`/`analyze` are standard |

**Keep from the partial sections:**
- From `### Flutter Web Commands`: the `cd shavtzak` note (real monorepo gotcha) and "run `flutter analyze`, don't run the app yourself".
- From `### Role-Based System`: the one-line pointer that each `TeamMember` has `Map<RoleType, bool> roleCapabilities`.

**Do NOT touch — none of this is derivable from code:**
- `## Workflow Conventions (Claude Code — READ FIRST)` — worktree-per-task agent directives
- `### CRITICAL: Implementing Real-Time Updates` (404–504) — the Equatable-props gotcha
- `## Troubleshooting` (709–735)
- `### Constraints and Availability System` — domain rules
- `### Environment Switching System` — the test/prod contract
- `## Features To Be Implemented` — intent, not state

**How to apply:** ordinary working-tree edits. Review with `git diff`, then commit yourself — a future session should not commit this for you.

### D. Delete 2 stray items (optional, zero context cost)

```
~/.claude/skills/knesset-seedance-scenes-workspace/   (directory, no SKILL.md)
~/.claude/skills/knesset-seedance-scenes.skill        (6.9 KB file, not a directory)
```

Neither loads as a skill, so this is disk tidiness only. **Skip if the workspace dir holds source material you care about.**

---

## Checks that came back clean (no action)

| Check | Result |
|---|---|
| **0 — install health** | Native install `2.1.220` at `~/.local/bin/claude`, matches `installMethod: native`. No npm-global copy, no `~/.claude/local` leftover. `~/.local/bin` on `PATH`. All 3 config files parse. No agent definitions, so none broken or colliding. |
| **2 — local memory dedup** | No `~/.claude/CLAUDE.md`, no `CLAUDE.local.md`. Nothing to dedup. |
| **4 — lazy-loading migration** | **No proposal.** What survives the trim is gotchas, domain rules and agent directives — exactly what must stay resident. Moving a "never do X" rule into a lazily-loaded skill risks it not being loaded when it matters, and ~5.6k est. tokens on a 1M-context model doesn't justify the maintenance. |
| **5 — slow hooks** | Three `SessionStart` hooks, 48–105 ms typical, zero timeouts. Nothing blocking. |
| **7 — version** | `2.1.220` = latest on your channel. `autoUpdates: false` means background updates are off (your choice) — run `claude update` manually when a release lands. |
| **8 — auto mode** | `permissions.defaultMode` is already `"auto"` at user scope, nothing shadowing it. |
| **9 — denied commands** | Only 5 denials in the window: 3 × `AskUserQuestion` (you declining prompts, not a permission issue) and 2 on a `cd`-prefixed compound command. Nothing read-only worth pre-approving. |

---

## Where context actually goes

Estimates, disk-based. `/context` gives the live number.

| Source | Est. resident tokens |
|---|---|
| `CLAUDE.md` | ~7,992 → ~5,636 after trim |
| Skill/command listing | ~2,200 |
| `superpowers` SessionStart hook injection | ~1,000 |
| `MEMORY.md` | ~1,690 |
| MCP tool schemas | ~0 (all deferred) |

The skill listing is budgeted at roughly 1% of the context window — ~10k tokens on a 1M model — so at ~2.2k it is comfortable, not bloated. `CLAUDE.md` is the only item here worth acting on.

**Honest framing:** on a 1M-context model, ~2.4k tokens is noise. The reason to do section C is that `CLAUDE.md` currently tells every session you have no tests. Sections A, B and D are decluttering, not performance.

---

## To resume in a new session

> Read `claude-doctor-findings.md` at the repo root and apply sections A–D (skip any I name). Nothing has been applied yet.
