# Setup guide

There are **two kinds of repo** here, and mixing them up is the main way this goes
wrong.

1. **`shrike`** — one repo, created once. The skill lives here. It contains no
   application code and reviews nothing by itself.
2. **Project repos** — Rewado, JobPilot, WhereYahiaEats. These *consume* the skill.
   They get a symlink or a prompt file, optionally a workflow, and their own
   `review-rules.md`.

The workflow file is in `templates/` precisely because it must not run in the skills
repo — there's nothing there to review.

---

## Part 1 — Create the skills repo (once, ~5 minutes)

```bash
cd ~/dev
# unzip the downloaded folder here, then:
mv shrike-repo shrike
cd shrike

git init
git add .
git commit -m "deep-bug-hunter v0.1"

gh repo create shrike --private --source=. --push
```

Private is the right call — the stack checklists describe your codebases' internals.

Verify it built:

```bash
./scripts/build_portable.sh
```

Should print a word count and write `dist/bug-hunt.flat.md`.

---

## Part 2 — Wire it into one project (start with just one)

Pick the project where you'd most miss BugBot. Do that one, use it for two weeks,
then roll out.

There are two wiring paths. Pick the one your agent supports:

- **Agent Skills path** — for agents with a skill loader (Claude Code, and others
  adopting the `SKILL.md` format). The agent loads references on demand, so it's the
  cheapest on context.
- **Portable-prompt path** — for everything else (Codex, Cursor, Gemini CLI, Aider,
  Cline, Continue, raw API). Same hunt, flattened.

### Agent Skills path — the symlink

```bash
cd ~/dev/rewado
# path shown for Claude Code; adjust for your agent's skills dir
mkdir -p .claude/skills
ln -s ~/dev/shrike/skills/deep-bug-hunter .claude/skills/deep-bug-hunter
echo ".claude/skills/" >> .gitignore
```

The symlink is gitignored because it points at a path that only exists on your
machine. Teammates run the same two commands with their own clone path.

Test it in your agent:

```
> hunt for bugs in the diff against main
```

If it doesn't trigger on its own, say `use the deep-bug-hunter skill` explicitly. A
skill that won't auto-trigger usually means the `description` in the frontmatter needs
to name the phrasing you actually use.

### Portable-prompt path — any other agent

```bash
cd ~/dev/rewado
mkdir -p .agents
cp ~/dev/shrike/adapters/bug-hunt.prompt.md .agents/
cat ~/dev/shrike/adapters/AGENTS.md >> AGENTS.md
```

Codex reads `AGENTS.md` automatically. Cursor: copy the same prompt to
`.cursor/rules/bug-hunt.mdc` and set it to agent-requested rather than always-on.
Gemini CLI: append the pointer to `GEMINI.md` instead. Raw API: send
`dist/bug-hunt.flat.md` as the system prompt.

### Seed the rules file

Either path, do this:

```bash
cp ~/dev/shrike/templates/review-rules.example.md ./review-rules.md
```

Edit it down to invariants that are true for *this* project, delete the rest, and
commit it. Three real invariants beat twenty copied ones.

### CI — only after local use has earned it

```bash
mkdir -p .github/workflows
cp ~/dev/shrike/templates/workflows/bug-hunt.yml .github/workflows/
```

The shipped workflow uses Claude Code as the CI runtime; to run another agent, swap
the run step for that agent's CLI and feed it `dist/bug-hunt.flat.md`.

Then edit three things in that file:

1. **The clone URL** in the "Fetch skill" step — point at your actual skills repo.
2. **The dependency steps** — delete the Flutter block in JobPilot, delete the Node
   block in Rewado. Leaving both in doubles CI time for nothing.
3. **The trigger** — for the first few weeks, delete the `pull_request:` block and
   keep only `issue_comment:`. You then run it by commenting `/bughunt` on a PR. This
   caps your spend while you're still measuring whether the output is any good.

Add secrets:

```bash
gh secret set ANTHROPIC_API_KEY --repo ananmouaz/rewado
```

If `shrike` is private, `GITHUB_TOKEN` cannot reach it from another repo. Create
a fine-grained PAT with read access to `shrike`, add it as `SKILLS_TOKEN`, and
change the clone line to:

```bash
git clone --depth 1 https://x-access-token:${{ secrets.SKILLS_TOKEN }}@github.com/ananmouaz/shrike.git /tmp/skills
```

---

## Part 3 — Measure before scaling

Run it on ~10 PRs where you already know what's in them. Track one number:
**dismissed findings per review.**

- Above ~1 per review → precision problem. Raise the severity floor to Critical/High
  only, drop the cap from 5 to 3, and strengthen the falsification pass. Do this
  before changing anything else.
- Real bugs slipping through → recall problem. Widen Phase 1 caller traversal before
  loosening the evidence bar. Loosening the bar first is how you end up back at
  CodeRabbit-grade noise.
- Every dismissal → an entry in `review-rules.md`. This is the compounding part.

Only once that number is stable should you turn on automatic PR triggers, roll out to
the other repos, or make it a required check. A false positive that blocks a merge in
week one is how the tool gets deleted in week two.

---

## Updating

```bash
cd ~/dev/shrike
# edit skills/deep-bug-hunter/...
./scripts/build_portable.sh          # keep the flat build in sync
git commit -am "tighten falsification pass" && git push
```

Every symlinked project picks it up immediately. CI picks it up on the next run,
because the workflow clones `--depth 1` from the default branch.

Tag when something works well:

```bash
git tag v0.2 && git push --tags
```

Then a project that needs stability can pin to a tag via submodule instead of tracking
the branch.
