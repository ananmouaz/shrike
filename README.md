# Shrike

Forensic, high-precision bug hunting for AI coding agents.

**New here? Read [SETUP.md](SETUP.md).**

Shrike is agent-neutral. The hunt itself is plain markdown that any capable agent can
follow — Claude Code, Codex, Cursor, Gemini CLI, Aider, Cline, Continue, or a raw API
call. Anything that can read files and run shell commands can run it. Currently one
skill: `shrike`.

## shrike

Forensic bug hunting on a diff, PR, or branch. Returns only correctness bugs backed
by a concrete failure scenario — never style, naming, refactoring, or "consider"
suggestions. Zero findings is a valid and common output.

Built to replace BugBot / CodeRabbit / Macroscope. Tuned for Flutter/Dart and
Next.js + TypeScript + Drizzle + Neon.

## The output

Every run opens with a header of *measured* numbers — the duration is stamped in
Phase 0 and computed in Phase 6, never estimated:

```
## 🔪 Shrike — 1 finding — dark chrome fill eats photo shadows

| **Target**     | `fix/forced-dark-card-captures` · `3ecbfe0...bb7622b` |
| **Reviewed**   | 4 files, 31 hunks, 12 callers outside the diff        |
| **Duration**   | 6m 12s                                               |
| **Seeds worked**| 19 constructs · classes A,C,D,H live (B,E,F,G n/a)  |
| **Candidates** | 9 raised → 8 killed in falsification → **1 reported**|
| **Findings**   | 🔴 0 critical · 🟠 0 high · 🟡 1 medium               |
```

The candidates row is the part that earns trust: a run that raised nine and killed
eight is showing its work. Each finding then carries its severity, confidence, the
invariant class it belongs to, a trigger, a traced path, and either a failing test or
the one rebuttal that couldn't be closed.

The same markdown goes to the terminal and — on a PR — to a single comment that
updates in place on each push, so the thread never fills with stale reports.

## How the hunt stays bounded

Two layers, and both are deliberately finite:

- **Constructs** — grep-able syntax where defects concentrate (indexing, `await`
  boundaries, non-null assertions, write paths). Language-level, so the list doesn't
  grow.
- **Eight invariant classes** — the kinds of wrongness a change can introduce:
  meaning drift, an uncovered guard path, stale state, a partial population treated as
  whole, duplicated truth, failure that doesn't degrade, assumed ordering, unfollowed
  blast radius.

Capping the semantic layer at eight is the point. When a new bug class turns up, it
gets folded into one of the eight as evidence rather than appended as a new rule —
`references/seeds-and-slicing.md` states that budget and enforces it. Eight questions
get worked; forty get skimmed. Specific cases live in `study/` as corpus, not in the
method.

## What's in the repo

| Path | What it is |
|---|---|
| `skills/shrike/` | The source of truth: the methodology in the Agent Skills format (`SKILL.md` + on-demand references) |
| `commands/` | Slash commands the plugin adds to Claude Code (`/shrike-review`) |
| `dist/shrike.flat.md` | The whole skill flattened into one self-contained file, for agents with no progressive disclosure |
| `adapters/` | Drop-in wiring for `AGENTS.md`-convention agents |
| `templates/` | A starter `review-rules.md` and a GitHub Actions workflow |
| `scripts/build_portable.sh` | Regenerates `dist/` from `skills/` |
| `study/` | Classified corpora of findings from other reviewers — evidence behind the method, and a reusable eval set |
| `MISSES.md` | The ledger: every real miss, why it happened, and which class absorbed it |

---

## Install

The hunt ships in two equivalent formats — pick whichever your agent consumes:

- `skills/shrike/` — the Agent Skills format (`SKILL.md` + on-demand
  references). Cheapest on context for agents with a skill loader.
- `dist/shrike.flat.md` — the same hunt flattened into one self-contained file,
  for everything else. `scripts/build_portable.sh` regenerates it after editing the
  skill so the two don't drift.

| Agent | How to wire it |
|---|---|
| Claude Code | `/plugin marketplace add ananmouaz/shrike`, then `/plugin install shrike@shrike`. Also adds a `/shrike-review` command. |
| Codex | Copy `adapters/shrike.prompt.md` to `.agents/` in the target repo, append `adapters/AGENTS.md` to its `AGENTS.md`. Copy the prompt to `~/.codex/prompts/shrike-review.md` to get a `/shrike-review` command. |
| Cursor | `adapters/shrike.prompt.md` → `.cursor/rules/shrike.mdc`, set to manual/agent-requested |
| Gemini CLI | Append the `AGENTS.md` pointer to `GEMINI.md`, same prompt file |
| Aider / Cline / Continue | Point the conventions/rules file at `shrike.prompt.md` |
| Raw API | Send `dist/shrike.flat.md` as the system prompt; needs file-read + shell tools |

### Skill-loader agents — clone-based install

For any agent adopting the `SKILL.md` format, or when you want tighter control over
versions than a plugin manager gives you:

**Option A — one repo, symlinked (always works).** Clone once, symlink into your
agent's skills directory (shown here as `.claude/skills`; Claude Code's — substitute
your agent's):

```bash
git clone git@github.com:ananmouaz/shrike.git ~/dev/shrike

# per project
mkdir -p .claude/skills
ln -s ~/dev/shrike/skills/shrike .claude/skills/shrike

# or globally, for every project on the machine
mkdir -p ~/.claude/skills
ln -s ~/dev/shrike/skills/shrike ~/.claude/skills/shrike
```

`git pull` in the clone updates it everywhere. Add the skills dir to `.gitignore`
in consuming repos if you don't want the symlink committed.

**Option B — git submodule (pins a version per project).**

```bash
git submodule add git@github.com:ananmouaz/shrike.git .claude/vendor/skills
ln -s ../vendor/skills/skills/shrike .claude/skills/shrike
```

Good when you want a project to stay on a known-good version of the skill and
update deliberately.

---

## Run it locally

In whatever agent you wired up:

```
> hunt for bugs in this branch
```

The skill description is written to trigger on "review this PR", "did I break
anything", "is this safe to merge", and similar. To force it:

```
> use the shrike skill on the diff against main
```

Agents with a command system get an explicit entry point too — `/shrike-review` in
Claude Code (installed with the plugin) or Codex (via the prompts dir):

```
/shrike-review              # hunt the current working diff
/shrike-review 123          # hunt PR #123
/shrike-review my-branch    # hunt a branch against main
/shrike-review src/auth.ts  # hunt one file
```

For agents using the portable prompt, replace `{{TARGET}}` in
`adapters/shrike.prompt.md` (or just tell the agent what to review).

---

## Run it on GitHub PRs

Copy `templates/workflows/shrike.yml` into the repo you want reviewed, then:

1. Add `ANTHROPIC_API_KEY` to that repo's Actions secrets.
2. Edit the "Fetch skill" step to point at your actual skills repo URL.
3. Trim the dependency setup steps to your real stack — the Flutter steps are dead
   weight on a Next.js repo and vice versa.

The shipped workflow runs the hunt with Claude Code as the CI runtime. To run it on a
different agent, swap the run step for that agent's CLI and feed it
`dist/shrike.flat.md` — the hunt itself doesn't change.

Behaviour:
- Runs on PR open / push / ready-for-review. **Skips drafts and bot PRs.**
- Re-run on demand by commenting `/shrike-review`.
- Cancels in-flight runs when you push again, so a branch under active development
  doesn't burn tokens reviewing every intermediate commit.
- Posts **one** comment, not inline review spam.

### Cost control

A hunt is not cheap — it reads the diff, traces callers, and runs a second
adversarial pass. Ways to keep it sane:

- Add a `paths:` filter so docs-only and config-only PRs don't trigger it.
- Drop the `pull_request` trigger entirely and run comment-only (`/shrike-review`), so it
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
