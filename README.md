# Shrike

Forensic, high-precision bug hunting for AI coding agents.

**New here? Read [SETUP.md](SETUP.md).**

Shrike is agent-neutral. The hunt itself is plain markdown that any capable agent can
follow — Claude Code, Codex, Cursor, Gemini CLI, Aider, Cline, Continue, or a raw API
call. Anything that can read files and run shell commands can run it. Currently one
skill: `deep-bug-hunter`.

## deep-bug-hunter

Forensic bug hunting on a diff, PR, or branch. Returns only correctness bugs backed
by a concrete failure scenario — never style, naming, refactoring, or "consider"
suggestions. Zero findings is a valid and common output.

Built to replace BugBot / CodeRabbit / Macroscope. Tuned for Flutter/Dart and
Next.js + TypeScript + Drizzle + Neon.

## What's in the repo

| Path | What it is |
|---|---|
| `skills/deep-bug-hunter/` | The source of truth: the methodology in the Agent Skills format (`SKILL.md` + on-demand references) |
| `dist/bug-hunt.flat.md` | The whole skill flattened into one self-contained file, for agents with no progressive disclosure |
| `adapters/` | Drop-in wiring for `AGENTS.md`-convention agents |
| `templates/` | A starter `review-rules.md` and a GitHub Actions workflow |
| `scripts/build_portable.sh` | Regenerates `dist/` from `skills/` |

---

## Install

### Any agent — the portable prompt

The universal path. No skill loader required:

| Agent | How to wire it |
|---|---|
| Codex | Copy `adapters/bug-hunt.prompt.md` to `.agents/` in the target repo, append `adapters/AGENTS.md` to its `AGENTS.md` |
| Cursor | `adapters/bug-hunt.prompt.md` → `.cursor/rules/bug-hunt.mdc`, set to manual/agent-requested |
| Gemini CLI | Append the `AGENTS.md` pointer to `GEMINI.md`, same prompt file |
| Aider / Cline / Continue | Point the conventions/rules file at `bug-hunt.prompt.md` |
| Raw API | Send `dist/bug-hunt.flat.md` as the system prompt; needs file-read + shell tools |

`scripts/build_portable.sh` regenerates `dist/bug-hunt.flat.md` — run it after editing
the skill so the two don't drift.

### Agents with Agent Skills support (Claude Code, and others adopting the format)

**Option A — one repo, symlinked (simplest, always works).** Clone once, symlink into
every project that needs it:

```bash
git clone git@github.com:ananmouaz/shrike.git ~/dev/shrike

# per project (path shown for Claude Code; adjust for your agent's skills dir)
mkdir -p .claude/skills
ln -s ~/dev/shrike/skills/deep-bug-hunter .claude/skills/deep-bug-hunter
```

Or install it globally for every project on the machine:

```bash
mkdir -p ~/.claude/skills
ln -s ~/dev/shrike/skills/deep-bug-hunter ~/.claude/skills/deep-bug-hunter
```

`git pull` in the clone updates it everywhere. Add `.claude/skills/` to
`.gitignore` in consuming repos if you don't want the symlink committed.

**Option B — git submodule (pins a version per project).**

```bash
git submodule add git@github.com:ananmouaz/shrike.git .claude/vendor/skills
ln -s ../vendor/skills/skills/deep-bug-hunter .claude/skills/deep-bug-hunter
```

Good when you want a project to stay on a known-good version of the skill and
update deliberately.

**Option C — plugin marketplace (Claude Code only).** This repo carries a
`.claude-plugin/marketplace.json`, so it can be added as a marketplace and installed
by name:

```
/plugin marketplace add ananmouaz/shrike
/plugin install deep-bug-hunter@mouaz-skills
```

Nicest ergonomics, but the manifest schema has changed over time — check
https://docs.claude.com/en/docs/claude-code/overview and fix the manifest if the
install errors. Options A and B have no schema to get wrong.

---

## Run it locally

In whatever agent you wired up:

```
> hunt for bugs in this branch
```

The skill description is written to trigger on "review this PR", "did I break
anything", "is this safe to merge", and similar. To force it:

```
> use the deep-bug-hunter skill on the diff against main
```

For agents using the portable prompt, replace `{{TARGET}}` in
`adapters/bug-hunt.prompt.md` (or just tell the agent what to review).

---

## Run it on GitHub PRs

Copy `templates/workflows/bug-hunt.yml` into the repo you want reviewed, then:

1. Add `ANTHROPIC_API_KEY` to that repo's Actions secrets.
2. Edit the "Fetch skill" step to point at your actual skills repo URL.
3. Trim the dependency setup steps to your real stack — the Flutter steps are dead
   weight on a Next.js repo and vice versa.

The shipped workflow runs the hunt with Claude Code as the CI runtime. To run it on a
different agent, swap the run step for that agent's CLI and feed it
`dist/bug-hunt.flat.md` — the hunt itself doesn't change.

Behaviour:
- Runs on PR open / push / ready-for-review. **Skips drafts and bot PRs.**
- Re-run on demand by commenting `/bughunt`.
- Cancels in-flight runs when you push again, so a branch under active development
  doesn't burn tokens reviewing every intermediate commit.
- Posts **one** comment, not inline review spam.

### Cost control

A hunt is not cheap — it reads the diff, traces callers, and runs a second
adversarial pass. Ways to keep it sane:

- Add a `paths:` filter so docs-only and config-only PRs don't trigger it.
- Drop the `pull_request` trigger entirely and run comment-only (`/bughunt`), so it
  fires when you actually want it rather than on every push.
- Lower `--max-turns` if runs are longer than useful.

### Making it a required check

Once you trust the precision, have the workflow exit non-zero when a **Critical**
finding survives, and mark it required in branch protection. Do not do this on day
one — a false positive that blocks a merge is how a tool gets uninstalled.

---

## review-rules.md

The skill reads a `review-rules.md` from the root of the repo being reviewed. This
is the learning loop that replaces CodeRabbit's per-org memory. Two kinds of entries
are worth writing:

**Suppressions** — patterns you've dismissed and don't want to see again:

```markdown
- Don't flag missing `await` on `analytics.track()` — fire-and-forget is intentional.
- Don't flag missing authz in `app/api/public/**` — that tree is deliberately open.
```

**Invariants** — the higher-value half, because these both kill false positives and
generate real findings when violated:

```markdown
- All money and coin balances are integer minor units. Any `double`/`number` holding
  currency is a bug.
- Every route under `app/(admin)` is authz-gated by middleware — don't flag those.
- Reward claims must carry an idempotency key. A mutation without one is Critical.
```

Commit it. It compounds.

---

## Measuring it

Before trusting it, run it on ~10 PRs where you already know the answer and track
**dismissed-comment rate**. If precision is low: raise the severity threshold, shrink
the cap, and strengthen the falsification pass. If real bugs slip through: widen
context retrieval (more caller traversal) before loosening the evidence bar.
