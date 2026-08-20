# Shrike

**A bug hunter for AI coding agents that would rather find nothing than waste your time.**

New here? Start with [SETUP.md](SETUP.md).

> A shrike is a small songbird that impales its prey on thorns and comes back for it
> later. Seemed about right.

## The problem

Ask any coding agent to "review this PR" and you get eighteen comments. Two are real
bugs. Sixteen are "consider extracting this into a helper," "this variable could be
named better," and a confident warning about a null that a guard three functions up
already handles.

You read all eighteen the first week. You skim them the second week. By the third week
you close the tab, and now the two real bugs are worthless too, because nobody's
reading.

**The economics nobody designs for: a false positive costs more than a miss.** A missed
bug was already in your code. A false positive spends your attention and, a few times
over, spends your trust in the whole tool.

## What Shrike does about it

It refuses to guess. Every finding has to survive a pass where the reviewer actively
tries to prove itself wrong.

1. **Run the tools first.** Compiler, linter, type checker, tests. A type error is the
   compiler's job, not a bug hunt. This also shows where the change is shaky.
2. **Read the change, then find every caller.** This is the part that actually earns its
   keep. The best bugs are almost never *in* the diff — they're in the code written
   against the old behavior that nobody updated.
3. **Ask a fixed list of questions.** Not "look for bugs" (which has no finish line, so
   the model stops when it gets bored and starts inventing). A bounded set of specific
   questions that reading code answers yes or no. When they're answered, the pass is over.
4. **Then turn hostile.** Switch sides and attack every candidate finding: is there a
   guard upstream? A type that makes the bad value impossible? A framework guarantee? A
   test that already covers it? **If the rebuttal can't be closed by pointing at actual
   code, the finding is deleted.** Not softened, not marked "low confidence." Deleted.
   Most candidates die here. If none died, the pass wasn't honest.
5. **Prove what's left.** Ideally by writing a failing test and running it. If the test
   passes, the finding was wrong — delete it.
6. **Report at most five things**, and show the body count.
7. **Hunt the diff you haven't reviewed** — the fixes the run just applied, and anything
   pushed since the commit the report covers. A reviewer that runs once loses to a bot
   that runs on every push, and it loses on coverage, not on reasoning.

## What a run looks like

```
## 🔪 Shrike — 1 finding — dark chrome fill eats photo shadows

|                  |                                                       |
|------------------|-------------------------------------------------------|
| **Target**       | `fix/forced-dark-card-captures` · `3ecbfe0...bb7622b`  |
| **Reviewed**     | 4 files, 31 hunks, 12 callers outside, 2 peers compared |
| **Not reviewed** | none                                                   |
| **Duration**     | 6m 12s — 300 hunks/hour                                |
| **Seeds worked** | 19 constructs · classes A,C,D,H live (B,E,F,G n/a)     |
| **Candidates**   | 9 raised → 8 killed in falsification → **1 reported**  |
| **Findings**     | 🔴 0 critical · 🟠 0 high · 🟡 1 medium                 |
```

**The row that matters is `Candidates`.** Nine raised, eight killed, one survived. A
tool that reports everything it thought of is not showing you its work — it's showing
you its stream of consciousness.

`Not reviewed` is the other honest row. A report is only true of the commit range in its
header, so anything outside it — a slice too big to hunt at depth, commits pushed after
the run, fixes the run itself applied — gets named instead of quietly counting as clean.

The numbers are measured, not vibes. Duration is stamped at the start and computed at
the end, because "took about 5 minutes" is exactly the kind of thing you shouldn't
believe from a language model.

Each finding then gives you: where, what triggers it, the traced path with line
numbers, what a user actually experiences, the guard it checked for and didn't find,
the minimal fix, and either a failing test or the one rebuttal it couldn't close.

Same markdown goes to your terminal and to **one** PR comment that updates in place. No
inline comment confetti.

## "Zero findings" is a good day

A clean run says: *"No correctness bugs found that meet the evidence bar,"* followed by
3–6 things it specifically checked and ruled out, with reasons.

That last part is the trust-builder. Anyone can print "looks good to me." A run that
tells you it checked the retry path, the transaction boundary, and the new caller in
the export job — and why each was fine — is one you can argue with.

**Target posture: 2 real bugs and 3 missed beats 2 real bugs and 15 maybes.**

## The eight questions

Bug hunts fail by turning into checklists. A 200-item checklist gets skimmed; a short
list of real questions gets worked. So the semantic layer is capped at **eight kinds of
wrongness**, permanently:

| | The question, in plain English |
|---|---|
| **A. Meaning drift** | Does this number mean what the code reading it thinks it means? (rows vs. pairs, cents vs. dollars, seconds vs. milliseconds) |
| **B. Uncovered guard** | Which way into this code skips the check — and which legitimate caller does the check now wrongly reject? |
| **C. Stale state** | Between reading this value and using it, what could have changed it? |
| **D. Partial population** | Is this the whole set, or page one of it — and what happened to everyone else? |
| **E. Duplicated truth** | What else in the repo encodes this same rule, and did all of them get updated? |
| **F. Failure that doesn't degrade** | When this breaks, what does the caller *think* happened, and what mess is left behind? |
| **G. Assumed ordering** | This depends on A happening before B. What actually guarantees that? |
| **H. Blast radius** | What outside this change depends on what the change altered? |

Plus a **grep layer**: mechanical syntax where bugs cluster — array indexing, division,
`!` assertions, `await` boundaries, `catch` blocks, write paths, truthiness checks on
values that can legitimately be `0`. Findable with ripgrep, so the list stays finite.

When a new bug class turns up, it gets folded into one of the eight as evidence — it
does **not** become rule #9. The budget is written into the file and enforced:
[eight classes, ≤12 example shapes each](skills/shrike/references/seeds-and-slicing.md).
The whole taxonomy fits on a page. That's the feature.

## What it will not tell you

Not a partial list. This is the actual scope contract:

**In:** wrong results, crashes, data loss or corruption, silent failure, leaks, security
holes (authz gaps, injection, leaked secrets), broken invariants, and contracts your
change just broke for its existing callers.

**Out, permanently:** style, naming, formatting, import order, "consider extracting
this," missing comments, test-coverage opinions, architectural preferences, performance
speculation, "this could be more idiomatic," dead code, and anything your linter already
says. Also visual polish and accessibility labelling — those are real problems, they're
just not this tool's problem.

The rule: if it can't be phrased as *"when X happens, the program does Y, which is
wrong"* — it's not a finding. Delete it.

Two deliberate exceptions, both because they're actually correctness bugs in disguise: a
UI that **asserts something false about the data** (a count labelled with the wrong
unit), and a change that leaves a control **impossible to reach or activate**. Losing a
button isn't a style nit.

## Where it works

The method is language-agnostic. Stack-specific checklists ship for:

- Flutter / Dart
- Next.js + TypeScript + Drizzle + Neon
- Python services and pipelines (SQLAlchemy, Alembic, worker pools)
- Anything calling a model provider (Anthropic, OpenAI, Gemini, AI SDK)

Other stacks work fine on the generic taxonomy — the run just says so out loud.

Agent-neutral too. The hunt is plain markdown: Claude Code, Codex, Cursor, Gemini CLI,
Aider, Cline, Continue, or a raw API call. If it can read files and run shell commands,
it can run this.

## What's in the repo

| Path | What it is |
|---|---|
| `skills/shrike/` | The real thing — the method in Agent Skills format (`SKILL.md` + references loaded on demand) |
| `dist/shrike.flat.md` | Same method, one flat file, for agents with no skill loader |
| `adapters/` | Drop-in wiring for `AGENTS.md`-convention agents |
| `commands/` | `/shrike-review` slash command for Claude Code |
| `templates/` | Starter `review-rules.md` and a GitHub Actions workflow |
| `scripts/build_portable.sh` | Rebuilds `dist/` from `skills/` so the two don't drift |
| `MISSES.md` | The ledger — every bug Shrike missed, why, and what changed as a result |

`MISSES.md` is the interesting one. Shrike gets better by being told what it failed to
catch, and the rule is that a miss must generalize into an existing class or it doesn't
get added at all. Otherwise you wake up one day with a 200-row checklist.

---

## Install

Two equivalent formats — pick what your agent eats:

- `skills/shrike/` — Agent Skills format. Cheapest on context, loads references only
  when needed.
- `dist/shrike.flat.md` — everything in one file, for agents without a skill loader.

| Agent | How to wire it |
|---|---|
| Claude Code | `/plugin marketplace add ananmouaz/shrike`, then `/plugin install shrike@shrike`. Gets you `/shrike-review` too. |
| Codex | Copy `adapters/shrike.prompt.md` to `.agents/`, append `adapters/AGENTS.md` to the repo's `AGENTS.md`. Drop the prompt in `~/.codex/prompts/shrike-review.md` for a slash command. |
| Cursor | `adapters/shrike.prompt.md` → `.cursor/rules/shrike.mdc`, set to manual / agent-requested |
| Gemini CLI | Append the `AGENTS.md` pointer to `GEMINI.md`, same prompt file |
| Aider / Cline / Continue | Point the conventions or rules file at `shrike.prompt.md` |
| Raw API | Send `dist/shrike.flat.md` as the system prompt. Needs file-read + shell tools. |

### Skill-loader agents: clone instead

For tighter version control than a plugin manager gives you.

**Option A — one clone, symlinked everywhere.** (Paths shown for Claude Code; swap in
your agent's skills directory.)

```bash
git clone git@github.com:ananmouaz/shrike.git ~/dev/shrike

# per project
mkdir -p .claude/skills
ln -s ~/dev/shrike/skills/shrike .claude/skills/shrike

# or once, for every project on the machine
mkdir -p ~/.claude/skills
ln -s ~/dev/shrike/skills/shrike ~/.claude/skills/shrike
```

`git pull` in the clone updates it everywhere. Gitignore the skills dir in consuming
repos if you don't want the symlink committed.

**Option B — submodule, pinned per project.**

```bash
git submodule add git@github.com:ananmouaz/shrike.git .claude/vendor/skills
ln -s ../vendor/skills/skills/shrike .claude/skills/shrike
```

Use this when a project should stay on a known-good version and update deliberately.

---

## Run it locally

Just ask:

```
> hunt for bugs in this branch
```

It's written to trigger on "review this PR", "did I break anything", "is this safe to
merge", and friends. To force it:

```
> use the shrike skill on the diff against main
```

Or use the command, in agents that have one:

```
/shrike-review              # the current working diff
/shrike-review 123          # PR #123
/shrike-review my-branch    # a branch, against main
/shrike-review src/auth.ts  # one file
```

---

## Run it on GitHub PRs

Copy `templates/workflows/shrike.yml` into the repo you want reviewed, then:

1. Add `ANTHROPIC_API_KEY` to that repo's Actions secrets.
2. Point the "Fetch skill" step at your actual skills repo URL.
3. Delete the setup steps for stacks you don't use — the Flutter steps are dead weight
   on a Next.js repo and vice versa.

Ships with Claude Code as the CI runtime. To use a different agent, swap the run step
for its CLI and feed it `dist/shrike.flat.md`. The hunt doesn't change.

Out of the box:

- Runs on PR open / push / ready-for-review. **Skips drafts and bot PRs.**
- Re-run any time by commenting `/shrike-review`.
- Cancels in-flight runs when you push again, so an active branch doesn't burn tokens
  reviewing every intermediate commit.
- Posts **one** comment. Updates it in place. Never spams inline.

### Keeping the bill sane

A real hunt isn't cheap — it reads the diff, chases callers across the repo, and runs a
whole second adversarial pass. If that's too much:

- Add a `paths:` filter so docs-only and config-only PRs don't trigger it.
- Drop the `pull_request` trigger entirely and go comment-only, so it runs when you
  actually want it.
- Lower `--max-turns` if runs go longer than they're worth.

### Making it a required check

Once you trust the precision: have the workflow exit non-zero when a **Critical**
finding survives, and mark it required in branch protection.

**Not on day one.** A false positive that blocks a merge is how a tool gets uninstalled
with prejudice.

---

## review-rules.md — teaching it your codebase

Shrike reads a `review-rules.md` from the root of the repo being reviewed. This is the
memory. Two kinds of entries pull their weight:

**Suppressions** — things you've dismissed and don't want to see again:

```markdown
- Don't flag missing `await` on `analytics.track()` — fire-and-forget is intentional.
- Don't flag missing authz in `app/api/public/**` — that tree is deliberately open.
```

**Invariants** — the better half, because these kill false positives *and* create real
findings when something violates them:

```markdown
- All money and coin balances are integer minor units. Any `double`/`number` holding
  currency is a bug.
- Every route under `app/(admin)` is authz-gated by middleware — don't flag those.
- Reward claims must carry an idempotency key. A mutation without one is Critical.
```

Commit it. It compounds.

---

## Does it actually work?

Don't take anyone's word for it, including this README's. Run it on ~10 PRs where you
already know the answer and track one number: **how many comments you dismissed.**

- Precision too low → raise the severity threshold, shrink the cap, make the
  falsification pass meaner.
- Real bugs slipping through → widen the context first (chase more callers) before
  loosening the evidence bar. Loosening the bar is how you get back to eighteen comments.
