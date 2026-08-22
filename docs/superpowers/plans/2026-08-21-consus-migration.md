# consus Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename `LRNZ09/dotgit` to `LRNZ09/consus`, restructure it into a
browsable repo at `~/Developer/LRNZ09/consus` that also holds the fish and
ghostty configuration, and activate it by pointing each tool's own default path
at it with a symlink — without deleting anything, and without a human at the
keyboard.

**Architecture:** One mechanism, not four. `~/.config/git` and `~/.config/fish`
become symlinks into the clone, so each tool reads the repo at its own default
path with zero configuration in its own language. Ghostty is the one exception —
its winning path on macOS is under `~/Library/Application Support`, which no
symlink under `~/.config` can outrank — so it gets a one-line `config-file`
include instead. `bin/install` creates the links and never deletes: every
displaced path is *moved* into a timestamped backup directory. `bin/doctor` is
the read-only probe for the one invariant git cannot express — that the links
still point here.

**Tech Stack:** POSIX `sh` (both scripts must pass `sh -n`), git 2.55.0, fish
4.8.0 + fisher, ghostty 1.3.1, lefthook 2.1.10, gitleaks 8.30.1, `gh` 2.96.0
for the rename and the CI gate.

**Spec:** `docs/superpowers/specs/2026-08-21-consus-migration-design.md` —
read it alongside this plan. Every "why" lives there; this plan argues from it
and does not restate its measurements.

## Running this unattended

Every task in this plan is executable with nobody watching. Three things make
that true, and each one is a change from the first draft:

1. **No command waits on a human.** `bin/install`'s prompt is replaced by
   declared resolutions (`--resolve`, `--expect-diff`) for Tasks 10 and 13; the
   prompt itself stays, and is still what a person at a terminal gets. The
   only other command that reads stdin is `fisher remove`, which does so
   whenever stdin is not a TTY, so it gets `</dev/null`. No command can open
   an editor: `GIT_EDITOR=false` makes an accidental invocation fail rather
   than wait.
2. **Every check is a command with an exit code.** The first draft had roughly
   40 checks written as prose or as a trailing `# expected value` comment. An
   unattended run cannot read those. They are now assertions.
3. **Nothing is hand-carried between tasks.** Four values used to be "write
   this down" (`BASELINE_COMMITS`, `$R`, `$BK`, `$SP`). They live in a state
   file that every task sources.

The one place the run can stop and wait for a person is Task 13's review queue,
and it stops *cleanly*: the machine is already activated and working, and only
the push is outstanding. That is by design — the alternative is guessing which
of two versions of a config file was right.

**Before going AFK, Task 0 must pass.** It verifies the two things this plan
cannot work around: that a signed commit completes without a passphrase prompt,
and that `gh` is authenticated without one.

## Global Constraints

Every task's requirements implicitly include this section.

- **Repo name and remote:** `LRNZ09/consus`,
  `https://github.com/LRNZ09/consus.git`. The rename happens before anything is
  cloned, so no artifact ever carries the old name.
- **Clone path:** `~/Developer/LRNZ09/consus`, mode `700`.
- **State file:** `~/Backups/consus-migration.env`. Tasks append `KEY=value`
  lines to it and later tasks open with `. ~/Backups/consus-migration.env`.
  Nothing in this plan is carried in a human's head or in a single shell.
- **`chmod 700 ~/Backups`.** It holds the config tarball — every credential
  under `~/.config` in the clear — and a sandbox containing copies of
  `git/config-local` and `git/config-work`. It is mode `755` today.
- **Backups never go to `~/Desktop` or `~/Documents`** — both are iCloud-synced.
  `~/Backups` only. The sandbox goes to `~/Backups/consus-sandbox`, never
  `/tmp`: a world-readable sandbox would expose the identity files the fixture
  copies.
- **Nothing is ever deleted.** No `rm`, no `rm -rf`, in any task. Every
  displaced path is moved — into the repo, or into a timestamped directory under
  `~/Backups`. Two exceptions, both narrow: `git rm -r .githooks` in Task 4
  removes *tracked* files that stay recoverable from history, and the sandbox
  fixture builder wipes and rebuilds its own scratch directory under
  `$SP` on every run.
- **Environment for the whole run:**

  ```sh
  export GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 GIT_EDITOR=false
  ```

  `GH_PROMPT_DISABLED` turns any overlooked interactive `gh` path into a fast
  failure instead of a hang. `GIT_EDITOR=false` does the same for git: the
  tracked config sets `core.editor = code --wait`, so a command that opens an
  editor would otherwise block forever on a GUI window.
- **Every commit passes `-m`.** Measured: with `commit.verbose = true` a `-m`
  commit never invokes the editor, so the `-m` commits in this plan are safe.
  There is no `git rebase -i`, no `git commit --amend` and no
  `git config --edit` anywhere in it.
- **Both scripts are POSIX `sh`** with `#!/bin/sh` and `set -eu`, and must pass
  `sh -n`. `chmod` on macOS rejects a `--` separator; every other tool used here
  accepts it. `read` has no portable timeout (`read -t` is not POSIX), which is
  why the AFK path declares decisions rather than feeding the prompt.
- **Executable bits must be set on disk, not only in the index.**
  `git add --chmod=+x` records mode `100755` while leaving the working-tree file
  at `644`, so `./bin/install` dies with exit 126. Always `chmod +x` then a
  plain `git add`.
- **Quote `%G?`.** `git log -1 --pretty=%G?` fails under zsh with
  `no matches found` because `?` is a glob. Always
  `git log -1 --pretty='%G?'`.
- **`.gitignore`: no pattern may carry a trailing comment.** gitignore honours
  `#` only at the start of a line, so `/git/.remember/    # 11 entries` is a
  pattern including the comment text and matches nothing.
- **`.gitignore`: the directory re-includes must come *after* `/fish/*`.**
  Measured: hoisted above it, only 2 files stage instead of 6, silently
  dropping four `conf.d` files and `functions/gfu.fish`.
- **The `includeIf` invariant:** `~/Developer/work` must be a real directory all
  the way down, and work repos must physically live inside it. A symlink in the
  *pattern* path, or a repo whose real path is outside it, never matches and
  says nothing. Verified today: both components are real directories, and a
  commit made inside `~/Developer/work` resolves the work identity and signs
  with the work key.
- **Never commit a non-noreply email address.** `.gitleaks.toml` flags every
  email that is not `*@users.noreply.github.com`, the pre-commit hook enforces
  it, and the workflow re-scans full history. This applies to this plan document
  too — which is why the hook-proof step below builds its fake finding from a
  split string.
- **Plugin pins, exactly:** `jorgebucaran/fisher` unpinned (it is the installer,
  kept current on purpose), `jhillyerd/plugin-git@v0.4` (upstream publishes
  minor tags only), `halostatue/fish-macos@v7`,
  `halostatue/fish-utils-core@v3` (both moving major ladders). No tag lookup is
  needed at execution time.
- **Counts that are gates:** 6 tracked files under `git/`, 6 under `fish/`, 97
  entries in the fish directory after Task 1, `abbr | count` 169,
  `functions | count` 108. The *total* tracked-file count is deliberately not a
  gate — Task 7 grows it on purpose.
- **`BASELINE_COMMITS`** is recorded in Task 3 and is the only history gate.
  Never assert against a literal commit count: this document and the design
  document both add commits.
- **Verification through fish compares stdout.** `proto activate fish | source`
  emits NDJSON in agent environments and produces ~20 lines of parse errors on
  stderr per startup. This is proto's behaviour, is not fixable from this
  config, and affects only agent-driven shells. Use `2>/dev/null` and read
  stdout.
- **`gh run list` cannot gate CI.** It exits 0 regardless of conclusion, and
  exits 0 when it matches nothing at all. Use the SHA-scoped gate in Task 3,
  and pass the full 40-character SHA — `--commit` with a short SHA silently
  returns an empty list.

## Execution order, and the one gate

- Tasks 0–3 (Phase 0) change this machine, and every one of them is worth doing
  whether or not the migration proceeds.
- Tasks 4–9 (Phase 1) happen entirely inside a fresh clone. `~/.config` is
  untouched. `~/.config/git` stays a complete, working, pushed checkout, which
  is what makes it the rollback.
- **Tasks 8–11 are the gate.** The two scripts ship with a sandbox harness that
  runs them against a redirected `XDG_CONFIG_HOME`, and Task 10 rehearses the
  real merge path against real drift. **No step in Task 12 or later may start
  until Task 11 passes.**
- Tasks 12–14 (Phases 3–4) are the only ones that change the *shape* of
  `~/.config` — the links, the stub, the displaced checkout. Tasks 1–3 edit
  files in place, and each of those edits stands on its own merit.

## Corrections this plan makes to the spec's prose

The design document warns that prose in it has a measured failure rate. Writing
the two scripts, testing them against a sandbox, and converting the plan for an
unattended run turned up fourteen, and an adversarial review of the finished
plan found ten more — every one of those ten a defect this plan introduced
rather than inherited, and every one a way the unattended run could have failed
silently. Each is fixed in the task that owns it;
they are collected here so a reviewer can see them at once.

1. **`chmod` rejects `--`.** `chmod 700 -- "$repo"` fails with
   `chmod: --: No such file or directory` on macOS. Use `chmod 700 "$repo"`.
   (`mv`, `cp`, `ln`, `cat`, `cmp`, `mkdir`, `readlink` all accept it.)
2. **`lefthook install` resolves its config from the caller's CWD, not the
   repo.** Measured: run from an unrelated git repo it *creates* a
   `lefthook.yml` there, installs hooks into that repo, exits 0 — and
   `bin/install` then prints a success line naming the consus clone, which is
   false. Run from outside any repo it exits 128, which with `set -eu` and
   `>/dev/null` kills the script silently *after* the links are made. Both are
   fixed by running it in a subshell that cds to the repo, and by reporting the
   failure. This matters most for `fides`, which will not have cd'd anywhere.
3. **`bin/doctor` must strip `@pin` on both sides of the declared-vs-installed
   check.** Task 7 pins `jhillyerd/plugin-git@v0.4`, while fisher's
   `_fisher_plugins` records the plugin without a pin until `fisher update`
   runs. A literal comparison reports "declared but not installed: 1" forever.
4. **`bin/doctor` must skip the fish checks when the fish link is not intact.**
   Measured: fish **creates** `$XDG_CONFIG_HOME/fish` when it is missing. A
   read-only probe that starts fish through a severed link therefore plants a
   real directory where the link belongs — which turns install's silent
   relink into a prompt on the next run. Found by a test doing exactly that.
5. **`fish --no-config` does not expose universal variables**, so doctor cannot
   use it to avoid conf.d noise; it starts a normal fish and sends stderr to
   `/dev/null`. Measured separately: reading a universal variable leaves
   `fish_variables` untouched, so doctor stays read-only.
6. **The sandbox must not live in `/tmp`.** The fixture copies `~/.config/git`
   wholesale, which includes `config-local`, `config-work` and the mode-700
   `.remember/`. `${TMPDIR:-/tmp}` is safe on macOS and world-readable on the
   fallback. Use `~/Backups/consus-sandbox` with mode 700.
7. **`gh repo rename` prompts without `--yes`**, and the plan's next line
   repointed `origin` unconditionally — so a failed rename plus a successful
   `set-url` would leave `origin` naming a repo that does not exist, surfacing
   only at the push. Fixed with `--yes` and `&&`.
8. **`gh run list -L 3` cannot gate CI.** Measured: exit 0 with months-old
   successful runs, and exit 0 with an empty result. The plan's "do not go on if
   it failed" was unenforceable. Replaced with a SHA-scoped wait whose exit code
   comes from `grep`.
9. **Task 12 recomputed `$(date +%F)` three times.** A run that crosses midnight
   writes one filename and verifies a different, nonexistent one — and
   `tar tzf` on a missing file reads like archive corruption. One `ARCHIVE`
   variable, recorded in the state file.
10. **`grep -c excludesfile` exits 1 exactly when the edit was correct.** Three
    other checks were also expected to exit non-zero. All four are now positive
    assertions.
11. **`mv "$CFG/git/.remember" "$repo/git/"` fails on a re-run** with
    `Directory not empty`, because the destination already exists from the first
    attempt. Found by running Task 13 twice in the sandbox. Task 13 now gates on
    the three destinations being absent, so a re-run refuses instead of failing
    halfway.
12. **`--pretty=%G?` must be quoted** or zsh globs it.
13. **The spec's Phase 4 signing check mixes fish syntax into an `sh` block** —
    `( cd (mktemp -d) && ... )`. Use `cd "$(mktemp -d)"`.
14. **The tracked count is 13, not 14.** The spec's "14 files — 7 fish, 6 git,
    1 ghostty" predates Task 1 removing `conf.d/abbr_tips_override.fish`. After
    it, the count is 6 fish + 6 git + 1 ghostty.

15. **A `!`-negated assertion cannot fail its step.** POSIX exempts a pipeline
    beginning with `!` from `set -e`, so `! git ls-files | grep -qE '…'` — the
    gate annotated "the one that matters", and the only guard against pushing a
    tracked `git/config-local` to a public repo — never aborted anything.
    Measured: `sh -c 'set -e; ! true | grep -q x; echo REACHED'` prints REACHED.
    Every negated assertion is now an `if … then echo FAIL; exit 1; fi`, which
    also names the offending path.
16. **`! grep -q PAT FILE` passes when FILE does not exist** (grep exits 2, `!`
    inverts it). Each such assertion is now preceded by `test -f FILE`.
17. **Piping a script through `tee` discards its exit status.** Both Task 10 and
    Task 13 drove their scripts that way, so `50 passed, 0 failed` and
    `38 passed, 12 failed` were indistinguishable — the rehearsal gate could pass
    with the merge path broken. Measured: `sh -c "exit 7" | tee /dev/null` gives
    a pipeline status of 0.
18. **Thirteen fenced blocks issued git commands with no `cd`.** Sourcing the
    state file per block concedes that each block is its own shell; the `cd` was
    only in each task's *first* block. The runner's default directory is
    `~/.config/git` — the old checkout, holding the same filenames — so Task 4's
    `git mv config … git/` would have restructured the live global config and
    then passed its own assertions. Every such block now sources and cds.
19. **`fisher remove` reads stdin when stdin is not a TTY.** Its own code opens
    with `isatty || read --local --null --array stdin`, so on an idle pipe the
    first mutating command of the whole migration blocks forever. Now
    `</dev/null`, and guarded so a repeat run is a no-op.
20. **The `--expect-diff` digest hashed file names only.** A `differ:` line is
    the same string whatever the file holds, so the documented guarantee — the
    digest goes stale the moment the machine drifts — was false for an edit to a
    file that already differed. The listing now carries both content hashes.
21. **`merge` was accepted for the git path**, by flag and by prompt, and would
    have copied the old checkout's `.git` into the repo as a nested repository
    `git status` never reports — the outcome this plan calls forbidden while
    nothing enforced it.
22. **`git log --diff-filter=R --name-status -1 -- git/config` prints nothing**
    on a *correct* migration: the pathspec filters out the rename's source side
    before detection runs. The assertion would have halted Task 4 on a repo in
    exactly the right state. Fixed with `--follow`.
23. **`test -z "$(git log --oneline @{u}..)"` passes when there is no upstream
    at all** — git exits 128 and writes nothing to stdout. The line that was
    supposed to prove the satellite is not ahead is now preceded by an upstream
    assertion.
24. **The rollback's guard was not fatal.** `test -d "$BK/git" && test -d
    "$BK/fish"` with no `|| exit` let the block continue and move the live
    `~/.config/git` and `~/.config/fish` aside before failing to restore
    anything. It is now `|| { echo …; exit 1; }`, with `: "${BK:?}"` above it.

Two clarifications that are not corrections, but matter when asserting:

- **Case 1 reports rather than staying mute.** The spec's case list says
  "already the correct link → nothing, silently", while its own rehearsal
  asserts a second run "reports the links already correct". Resolved as: print
  one `✓ ok` line per path, change nothing. "Silently" means no prompt and no
  diff.
- **The diff's own header names `.git/`** ("(.git/ and ignored files
  excluded)"), so an assertion that the listing excluded `.git/` must match the
  listing lines, not the whole log.

### What was changed in the spec, and why

Two edits to the design document were required before this plan could be
faithful to it, and both are already applied:

- **Case 5 now reads "No TTY, or `--non-interactive`, for case 4, and no
  resolution declared for that path → refuse and print, always."** The word
  "always" was load-bearing, so the exception is stated in the spec rather than
  argued for in a plan.
- **A new subsection, "Declaring a resolution instead of typing one"**, records
  what `--resolve` and `--expect-diff` do, why they do not weaken case 5 (they
  never prompt, and an undeclared path still refuses), and why a provisioner
  cannot use them durably (the digest goes stale the moment the machine drifts).

`.markdownlint.jsonc` was also added to the repo and to the spec's layout tree.
Prose in all three documents now wraps at 80 columns; the config exempts only
fenced code blocks and table rows, both of which cannot be reflowed without
damaging them. A prose hard tab or a long prose line is still an error.

## File Structure

```text
~/Developer/LRNZ09/consus/            mode 700, created by Task 4's clone
├── README.md                        Task 6  — operational: what is managed, quickstart, hazards
├── LICENSE                          Task 15 — MIT, matching vesta
├── .gitignore                       Task 6  — the fish allow-list; /git/.remember/
├── .gitleaks.toml                   arrives with the rename, unchanged
├── .markdownlint.jsonc              already added; travels with the rename
├── lefthook.yml                     Task 6  — pre-commit gitleaks
├── .github/workflows/gitleaks.yml   arrives with the rename, unchanged
├── bin/install                      Task 8  — plan, validate, apply; never deletes
├── bin/doctor                       Task 9  — read-only probe
├── docs/superpowers/specs/2026-08-21-consus-migration-design.md             arrives with the rename; Status line edited in Task 15
├── docs/superpowers/plans/2026-08-21-consus-migration.md   this plan
├── git/                             Task 4 (git mv) + Task 5 (ignore)
│   ├── config                       the global config, read through the link
│   ├── config-local.example
│   ├── config-work.example
│   ├── ignore                       git's own default excludes path
│   ├── README.md                    per-machine identity, next to the files
│   ├── .gitignore                   keeps config-local / config-work untracked
│   ├── config-local, config-work    untracked; arrive in Task 13
│   └── .remember/                   ignored; arrives in Task 13
├── fish/                            Task 7 — 97 entries, 6 of them tracked
│   ├── config.fish, fish_plugins
│   ├── conf.d/{android,proto,rustup}.fish
│   ├── functions/gfu.fish
│   └── (91 ignored entries: 82 fisher, 5 tool-generated, 3 OrbStack links, fish_variables)
└── ghostty/config.ghostty           Task 7 — four settings + one optional include
```

Files that change together live together: everything git reads is under `git/`,
everything fish reads is under `fish/`. The two scripts stay separate because a
reviewer can reject one while approving the other, and because `bin/doctor` must
stay defensibly read-only — it shares a three-line `find` idiom with
`bin/install` rather than a library, since the spec's layout has no room for
one.

Five scratch files live under `$SP/work` and are **deliberately not committed**:
`mkfixture.sh`, `tests-install.sh`, `tests-doctor.sh`, `rehearse.sh` and
`activate.sh`. The spec fixes the repo layout, and adding a `tests/` directory
is not a decision this plan gets to make. They are rebuilt from this document
when needed.

---

### Task 0: The unattended-run preflight

Nothing in this plan can work around a passphrase prompt or an expired token,
so both are verified before anything changes. This task also creates the state
file every later task sources, and hardens the directory that is about to hold
every credential on this machine in the clear.

**Files:**

- Create: `~/Backups/consus-migration.env` (the state file; never committed)
- Modify: `~/Backups` permissions

**Interfaces:**

- Consumes: nothing.
- Produces: `~/Backups/consus-migration.env`, which exports
  `GH_PROMPT_DISABLED`, `GH_NO_UPDATE_NOTIFIER` and `GIT_EDITOR`, defines `SP`
  and `CLONE`, and defines the shell function `ci_green <sha>`. Every later task
  opens with `. ~/Backups/consus-migration.env`.

- [ ] **Step 1: Create and harden the working directories**

```sh
mkdir -p ~/Backups
chmod 700 ~/Backups
test "$(stat -f '%Lp' ~/Backups)" = 700
mkdir -p ~/Backups/consus-sandbox/work
chmod 700 ~/Backups/consus-sandbox
```

`~/Backups` is mode `755` today and is about to hold the `~/.config` tarball —
all 32 credentials across seven stores — plus a sandbox holding copies of
`git/config-local` and `git/config-work`.

- [ ] **Step 2: Write the state file**

```sh
cat > ~/Backups/consus-migration.env <<'EOF'
# consus migration state. Sourced by every task in
# docs/superpowers/plans/2026-08-21-consus-migration.md.
# Appended to as the migration progresses; never committed.

# Any overlooked interactive gh path becomes a fast failure, not a hang.
export GH_PROMPT_DISABLED=1
export GH_NO_UPDATE_NOTIFIER=1
# The tracked config sets core.editor = code --wait, which would block forever
# on a GUI window. Every commit in this plan passes -m, so an editor invocation
# means something is wrong: fail rather than wait.
export GIT_EDITOR=false

SP=$HOME/Backups/consus-sandbox
CLONE=$HOME/Developer/LRNZ09/consus

# ci_green <full-sha> — wait for the gitleaks workflow run for that commit and
# gate on its conclusion. `gh run list` cannot do this: it exits 0 regardless of
# conclusion, and exits 0 when it matches nothing at all. The exit code here
# comes from the case match. The repo is named explicitly rather than resolved
# from the CWD, an unknown SHA yields null/null and retries, and a transport or
# auth failure is reported as such instead of being mistaken for "not started".
ci_green() {
	_sha="$1"
	_slug="${CONSUS_SLUG:-LRNZ09/consus}"
	_deadline=$(( $(date +%s) + 600 ))
	_errors=0
	while [ "$(date +%s)" -lt "$_deadline" ]; do
		if _state=$(gh api \
			"repos/$_slug/actions/workflows/gitleaks.yml/runs?head_sha=$_sha&event=push&per_page=1" \
			--jq '.workflow_runs[0] | "\(.status)/\(.conclusion)"' 2>&1); then
			_errors=0
			case "$_state" in
			completed/success) echo "CI green for $_sha"; return 0 ;;
			completed/*) echo "CI failed for $_sha: $_state" >&2; return 1 ;;
			esac
		else
			# A transport or auth failure is not "queued": say so, and give up
			# after three in a row rather than burning the whole deadline.
			_errors=$((_errors + 1))
			echo "gh api failed ($_errors/3): $_state" >&2
			[ "$_errors" -lt 3 ] || { echo "giving up on the CI gate" >&2; return 1; }
		fi
		sleep 5
	done
	echo "no gitleaks run reported for $_sha within ten minutes" >&2
	return 1
}
EOF
. ~/Backups/consus-migration.env
test "$GIT_EDITOR" = false && test -n "$SP" && test -n "$CLONE"
```

`ci_green` polls with `sleep`. If the harness running this plan blocks
foreground sleeps, run the step that calls it as a background command rather
than rewriting the gate.

- [ ] **Step 3: Assert the toolchain is present**

```sh
for t in git fish ghostty gh lefthook gitleaks shasum markdownlint-cli2 script; do
	command -v "$t" >/dev/null || { echo "missing: $t"; exit 1; }
done
git --version | grep -q 'version 2\.'
fish --version | grep -q 'version 4\.'
```

- [ ] **Step 4: Assert the machine is in the state this plan was written
      against**

```sh
cd ~/.config/git
git remote get-url origin | grep -qx 'https://github.com/LRNZ09/dotgit.git'
test -d ~/.config/fish && test ! -L ~/.config/fish
test -d ~/.config/git && test ! -L ~/.config/git
test ! -e ~/.config/ghostty
test -f ~/.gitignore
test ! -L ~/Developer && test -d ~/Developer/work && test ! -L ~/Developer/work
test "$(fish -c 'abbr | count' 2>/dev/null)" -eq 169
test "$(fish -c 'functions | count' 2>/dev/null)" -eq 109
test "$(find ~/.config/fish ! -type d | wc -l | tr -d ' ')" -eq 104
test "$(wc -l < ~/.config/fish/fish_plugins | tr -d ' ')" -eq 6
```

Every one of these must pass, and they are also what tells a resumed run where it
is: if the remote already says `consus`, Task 3 has run and this step should be
skipped rather than fixed. If `abbr | count` is not 169 or the entry count is not
104, Task 1 has already run. Task 1 and Task 3 each refuse cleanly on their own
preconditions when repeated, so a retry cannot half-apply them.

- [ ] **Step 5: Verify a signed commit completes with no prompt**

This is the check the whole unattended run rests on. It signs for real, in a
throwaway repo, and asserts the signature came out good:

```sh
D=$(mktemp -d)
( cd "$D" && git init -q . && git commit -q --allow-empty -m 'signing preflight' \
	&& test "$(git log -1 --pretty='%G?')" = G \
	&& test "$(git log -1 --pretty='%GK')" = "$(git config --get user.signingkey)" \
	&& echo 'personal signing ok' ) || { echo 'FAIL: personal signing'; exit 1; }
```

Measured on this machine: it completes in under a second with no dialog, because
the passphrase lives in the macOS keychain and `pinentry-mac` reads it silently.
If this hangs on a dialog, **stop** — sign one commit by hand to prime the
agent, then re-run. Do not change `~/.gnupg/gpg-agent.conf`: raising the cache
TTLs or presetting the passphrase would weaken this machine's credential
handling to buy something the keychain already provides.

- [ ] **Step 6: Verify the work identity signs too**

Task 14 asserts this, and it needs a repo *physically* inside
`~/Developer/work`:

```sh
W=$(mktemp -d ~/Developer/work/consus-verify-XXXX)
( cd "$W" && git init -q . && git commit -q --allow-empty -m 'work signing preflight' \
	&& test "$(git config --get user.email)" = "$(git config -f ~/.config/git/config-work --get user.email)" \
	&& test "$(git log -1 --pretty='%G?')" = G \
	&& test "$(git log -1 --pretty='%GK')" = "$(git config --get user.signingkey)" \
	&& echo 'work signing ok' ) || { echo 'FAIL: work signing'; exit 1; }
mv "$W" ~/Backups/
```

The probe repo is moved, not deleted.

- [ ] **Step 7: Verify gh and ghostty need no interaction**

```sh
. ~/Backups/consus-migration.env
gh auth status 2>&1 | grep -q 'Logged in to github.com'
gh api rate_limit --jq '.resources.core.remaining' | grep -qE '^[0-9]+$'
gh repo view LRNZ09/dotgit --json viewerCanAdminister --jq .viewerCanAdminister | grep -qx true
ghostty +validate-config >/dev/null 2>&1
```

`viewerCanAdminister` is what the rename in Task 3 needs. `ghostty
+validate-config` is measured to exit promptly with no window in a non-TTY
shell, which matters because `bin/doctor` calls it and `fides` calls
`bin/doctor`.

- [ ] **Step 8: No commit**

Nothing here touches the repo.

---

### Task 1: Phase 0 — drop two fish plugins and the dead override

Two plugins come out before anything is copied, because Task 7 captures whatever
the fish directory looks like at that moment. This is a change to the machine's
configuration that the migration then records, not part of the migration
mechanism.

**Files:**

- Modify: `~/.config/fish/fish_plugins` (via `fisher remove`; untracked today)
- Move: `~/.config/fish/conf.d/abbr_tips_override.fish` → `~/Backups/`
- Removed by fisher: 5 files for `gazorby/fish-abbreviation-tips`, 1 for
  `2m/fish-history-merge`

**Interfaces:**

- Consumes: Task 0's assertions about the starting state.
- Produces: a fish directory of **97 entries** with a 4-line `fish_plugins`,
  `abbr | count` 169 and `functions | count` 108. Task 7 copies exactly this
  tree; Task 9's doctor arithmetic (82 fisher + 6 tracked + 5 generated + 3
  OrbStack + `fish_variables` = 97) depends on it.

- [ ] **Step 1: Remove the two plugins**

```sh
. ~/Backups/consus-migration.env
# < /dev/null is not decoration: fisher's install/update/remove case begins
# `isatty || read --local --null --array stdin`, so with stdin on an idle pipe
# — a plausible runner shape — it blocks forever before removing anything.
if fish -c 'contains gazorby/fish-abbreviation-tips $_fisher_plugins' </dev/null 2>/dev/null; then
	fish -c 'fisher remove 2m/fish-history-merge gazorby/fish-abbreviation-tips' </dev/null
else
	echo 'both plugins are already gone — nothing to remove'
fi
```

`gazorby/fish-abbreviation-tips` mirrored every abbreviation into two universal
**exported** arrays — 5,301 bytes of environment in every child process, and the
mechanism behind the CESU-8 crash that broke React Native builds. Its
`abbr_tips_uninstall` event erases every variable it set and restores the three
key bindings, so this reclaims everything. `2m/fish-history-merge` was one file:
a 2020 copy of `up-or-search`, which fish 4.8 provides as an embedded function.

- [ ] **Step 2: Move the now-dead override aside**

```sh
mkdir -p ~/Backups
test -e ~/.config/fish/conf.d/abbr_tips_override.fish \
	&& mv ~/.config/fish/conf.d/abbr_tips_override.fish ~/Backups/ \
	|| test -f ~/Backups/abbr_tips_override.fish
test -f ~/Backups/abbr_tips_override.fish
```

That file exists only to patch the plugin that just left. It is moved, not
deleted.

- [ ] **Step 3: Assert the numbers moved exactly as expected**

```sh
test "$(fish -c 'abbr | count' 2>/dev/null)" -eq 169
test "$(fish -c 'functions | count' 2>/dev/null)" -eq 108
test "$(find ~/.config/fish ! -type d | wc -l | tr -d ' ')" -eq 97
test "$(wc -l < ~/.config/fish/fish_plugins | tr -d ' ')" -eq 4
if grep -q gazorby ~/.config/fish/fish_plugins; then echo "FAIL: gazorby still declared"; exit 1; fi
if grep -q fish-history-merge ~/.config/fish/fish_plugins; then echo "FAIL: 2m plugin still declared"; exit 1; fi
test "$(fish -c 'set --names | string match "*ABBR_TIPS*" | count' 2>/dev/null)" -eq 0
test "$(fish -c 'set --names | string match "_fisher_*_files" | count' 2>/dev/null)" -eq 4
```

`! -type d` rather than `-type f`: three of those entries are OrbStack
completion symlinks into `/Applications/OrbStack.app`, and `-type f` misses all
three. `abbr | count` staying at 169 is the load-bearing one — all 169 come from
`plugin-git`, so a change there means something other than the two intended
plugins was removed. `functions | count` drops by exactly one, because fish's
embedded `up-or-search` takes over from the 2020 copy.

- [ ] **Step 4: No commit**

Nothing here is tracked yet: `~/.config/fish` is a plain directory and
`fish_plugins` enters the repo in Task 7. This step exists so nobody goes
looking for the commit.

---

### Task 2: Phase 0 — make the fish configuration portable

The repo's contract is that a clone works on any machine, not just this one.
Four spots break that today, and all four are whole-file rewrites applied before
Task 7 captures anything. A hardcoded `/Users/lorenzo` in a public repo is also
the exact objection the design uses to reject outward symlinks.

Every edit here is a complete file write rather than an in-place patch, so the
task is idempotent and needs no diffing: re-running it produces the same four
files.

**Files:**

- Modify: `~/.config/fish/config.fish`
- Modify: `~/.config/fish/conf.d/proto.fish`
- Modify: `~/.config/fish/conf.d/rustup.fish`
- Modify: `~/.config/fish/conf.d/android.fish`

**Interfaces:**

- Consumes: Task 1's 97-entry tree.
- Produces: the four files Task 7 copies into `fish/`, unchanged in behaviour on
  this machine.

- [ ] **Step 1: Write all four files**

```sh
. ~/Backups/consus-migration.env
F=~/.config/fish

cat > "$F/config.fish" <<'EOF'
if status is-interactive
    # Commands to run in interactive sessions can go here
    fastfetch
end

# Disable fish greeting
set -g fish_greeting

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init2.fish 2>/dev/null || :
set -gx PATH $HOME/.local/bin $PATH
EOF

cat > "$F/conf.d/rustup.fish" <<'EOF'
if test -f "$HOME/.cargo/env.fish"
    source "$HOME/.cargo/env.fish"
end
EOF

cat > "$F/conf.d/android.fish" <<'EOF'
# Android development environment (React Native / Gradle).
# JAVA_HOME: Android Studio's bundled JBR 21 — the proto-managed `java`
# shim resolves to OpenJDK 26, which Gradle 8.x cannot run on.
if test -d $HOME/Library/Android/sdk
    set -gx ANDROID_HOME $HOME/Library/Android/sdk
    fish_add_path --global $ANDROID_HOME/platform-tools $ANDROID_HOME/emulator
end

set -l jbr "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
if test -d $jbr
    set -gx JAVA_HOME $jbr
end
EOF

cat > "$F/conf.d/proto.fish" <<'EOF'
# proto version manager (https://moonrepo.dev/docs/proto)
# `proto` bootstraps from Homebrew's bin (brew is the install source);
# activation then prepends ~/.proto/bin, the real tool bin dirs from the
# nearest .prototools (e.g. ~/.proto/tools/node/<v>/bin), and the shims as
# fallback. It applies immediately for the current dir and re-applies on
# every cd/prompt — works in interactive and non-interactive (`fish -c`)
# shells alike, so no manual PATH setup is needed.
#
# In agent environments proto detects the agent and emits NDJSON, which
# `source` cannot parse: ~20 lines of errors on stderr per startup. That is
# proto's behaviour and cannot be fixed from here — `proto activate` rejects
# --format, and neither `env -u AI_AGENT` nor PROTO_JSON=false suppresses it.
# Compare stdout when verifying anything through `fish -c`.
if type -q proto
    proto activate fish | source
end
EOF
```

- [ ] **Step 2: Syntax-check every file before trusting the behaviour checks**

```sh
. ~/Backups/consus-migration.env
F=$HOME/.config/fish
for f in "$F/config.fish" "$F/conf.d/rustup.fish" "$F/conf.d/android.fish" \
	"$F/conf.d/proto.fish"; do
	fish --no-execute "$f" || { echo "syntax error in $f"; exit 1; }
done
```

`fish --no-execute` parses without running. A syntax error in a `conf.d` file
would otherwise show up as a mysterious behaviour change three steps later.

- [ ] **Step 3: Assert behaviour on this machine is unchanged**

```sh
. ~/Backups/consus-migration.env
F=$HOME/.config/fish
test "$(fish -c 'abbr | count' 2>/dev/null)" -eq 169
test "$(fish -c 'functions | count' 2>/dev/null)" -eq 108
test "$(fish -c 'echo $ANDROID_HOME' 2>/dev/null)" = "$HOME/Library/Android/sdk"
test -n "$(fish -c 'echo $JAVA_HOME' 2>/dev/null)"
test "$(fish -c 'contains $HOME/.local/bin $PATH; and echo yes' 2>/dev/null)" = yes
test "$(fish -c 'type -q proto; and echo yes' 2>/dev/null)" = yes
test -f "$F/config.fish"
if grep -q "/Users/" "$F/config.fish"; then echo "FAIL: a hardcoded home survives"; exit 1; fi
```

Verified: a fresh `fish -c` picks up `conf.d` edits immediately — no shell
restart, no new terminal. `core.editor = code --wait` and the
`difftool`/`mergetool` commands stay as they are: they are `PATH` lookups, not
absolute paths, and a machine without VS Code overrides them in `config-local`,
which is included last and therefore wins. Ghostty needs nothing for platform
differences — measured, `gtk-*` and `linux-cgroup` keys on macOS produce no
diagnostics and exit 0, so the `macos-*` keys are inert on Linux rather than
errors.

- [ ] **Step 4: No commit**

Same reason as Task 1: these files are not tracked until Task 7.

---

### Task 3: Phase 0 — portable credential helper, then rename and push

The rename comes first so that no artifact ever carries the old name, no clone
URL needs fixing afterwards, and nothing relies on GitHub's redirect. It is
reversible with `gh repo rename dotgit --yes`, and GitHub redirects both
directions.

**Files:**

- Modify: `~/.config/git/config` — `credential.helper`
- Commit: `docs/superpowers/plans/2026-08-21-consus-migration.md` (this plan),
  the design document (its amendments), `.markdownlint.jsonc` and `README.md`

**Interfaces:**

- Consumes: Task 0's state file.
- Produces: `origin` = `https://github.com/LRNZ09/consus.git` with everything
  pushed and CI green, and `BASELINE_COMMITS` in the state file — the number
  Task 11's history gate asserts against.

- [ ] **Step 1: Rename the repo and repoint the remote, in one chain**

```sh
. ~/Backups/consus-migration.env
cd ~/.config/git
gh repo rename consus -R LRNZ09/dotgit --yes \
	&& gh repo view LRNZ09/consus --json name --jq .name | grep -qx consus \
	&& git remote set-url origin https://github.com/LRNZ09/consus.git
git remote get-url origin | grep -qx 'https://github.com/LRNZ09/consus.git'
```

`--yes` skips the confirmation prompt. The `&&` chain matters: repointing
`origin` after a *failed* rename would leave it naming a repo that does not
exist, and the failure would only surface at the push.

- [ ] **Step 2: Make the credential helper portable**

In `~/.config/git/config`, under `[credential]`, drop the absolute path:

```gitconfig
[credential]
	gitLabAuthModes = pat
	helper = git-credential-manager
	# credentialStore is OS-specific — see config-local
```

Measured: the bare name resolves through `PATH` to
`/usr/local/bin/git-credential-manager` here, which is the same portability
argument the file's own `!gh` comment already makes one section further down.

- [ ] **Step 3: Assert the helper still resolves**

```sh
test "$(git config --get credential.helper)" = git-credential-manager
command -v git-credential-manager >/dev/null
```

- [ ] **Step 4: Commit the documents and the config edit**

```sh
. ~/Backups/consus-migration.env
cd ~/.config/git
git add docs/superpowers/plans/2026-08-21-consus-migration.md \
	docs/superpowers/specs/2026-08-21-consus-migration-design.md .markdownlint.jsonc README.md
git commit -m "Add the consus migration plan, and the spec amendments it needs"
git add config
git commit -m "Resolve credential-manager helper through PATH"
test -z "$(git status --porcelain)"
```

The pre-commit hook runs gitleaks on both. The tracked `config` carries a
`users.noreply.github.com` address, which the allow-list in `.gitleaks.toml`
permits by design.

- [ ] **Step 5: Push, and gate on CI rather than eyeballing it**

```sh
. ~/Backups/consus-migration.env
cd ~/.config/git
git push
ci_green "$(git rev-parse HEAD)"
```

`ci_green` is the function Task 0 put in the state file. It waits for the
gitleaks workflow run for *this* commit and returns non-zero on any conclusion
other than success — unlike `gh run list`, which exits 0 whatever happened.

- [ ] **Step 6: Record the baseline in the state file**

```sh
. ~/Backups/consus-migration.env
cd ~/.config/git
printf 'BASELINE_COMMITS=%s\n' "$(git rev-list --count HEAD)" \
	>> ~/Backups/consus-migration.env
. ~/Backups/consus-migration.env
test "$BASELINE_COMMITS" -ge 8
git ls-files | wc -l | tr -d ' '
```

Only the commit count is a gate. Task 7 deliberately grows the tracked-file
total, so a file-count assertion would fail by design. The `ls-files` line is
for the record.

Note on tooling: `gh repo rename` and the workflow-run query use the CLI because
no connected GitHub MCP exposes a repo rename or a workflow-run listing.

---

### Task 4: Phase 1 — clone, and restructure the git files into `git/`

Nothing happens inside `~/.config/git` in this phase. It stays a complete,
working, pushed checkout — which is what makes it the rollback.

**Files:**

- Create: `~/Developer/LRNZ09/consus/` (the clone)
- Move: `config`, `config-local.example`, `config-work.example`, `README.md`,
  `.gitignore` → `git/`
- Modify: `git/README.md` (rewritten — the Setup section no longer applies)
- Delete (tracked, recoverable): `.githooks/pre-commit`

**Interfaces:**

- Consumes: `BASELINE_COMMITS` and `CLONE` from the state file, and the pushed
  `consus` remote.
- Produces: the clone at `$CLONE` with 5 files under `git/`, and
  `git log --follow -- git/config` reaching through the rename. Task 5 adds the
  sixth file.

- [ ] **Step 1: Clone, and assert the history came with it**

```sh
. ~/Backups/consus-migration.env
git clone https://github.com/LRNZ09/consus.git "$CLONE"
cd "$CLONE"
test "$(git rev-list --count HEAD)" -eq "$BASELINE_COMMITS"
```

- [ ] **Step 2: `mkdir git` first, then one multi-source `git mv`**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
mkdir git
git mv config config-local.example config-work.example README.md .gitignore git/
git rm -q -r .githooks
```

The `mkdir` is not cosmetic. Measured: `git mv` with multiple sources fails
outright on a destination that does not exist
(`fatal: destination 'git/' is not a directory`), and the obvious per-file
workaround is worse — a single-source `git mv config git` with no `git/` present
silently creates a *file* named `git`. Since git tracks no directories, the bare
`mkdir` needs nothing else.

`.githooks/` is superseded by the root `lefthook.yml` in Task 6, whose gitleaks
hook covers what `.githooks/pre-commit` covers today. These are tracked files
and stay recoverable from history. Leave `.gitleaks.toml`,
`.markdownlint.jsonc` and `.github/workflows/gitleaks.yml` at the root; `docs/`
is already there.

- [ ] **Step 3: Rewrite `git/README.md`**

Do not just move it. Its Setup section tells the reader to run
`git config core.hooksPath .githooks`, and step 2 just deleted that directory.
Its per-machine identity section is what survives, and it stays next to the
`config-local` and `config-work` files it describes. Replace the file with:

````markdown
# git

My global Git configuration. Through `~/.config/git` — a symlink into this
repo, created by [`../bin/install`](../bin/install) — Git reads `config` here as
its global config file and `ignore` as its global excludes file. Neither needs
an `[include]` line or a `core.excludesfile` setting: both are Git's own
default paths, and the link is what makes them resolve here.

Because this *is* the global config, anything that writes to it — `git config
--global`, `gh auth setup-git`, `git-credential-manager configure` — shows up
as a worktree modification of `git/config`. A machine that has drifted from the
record says so in `git status`.

## Per-machine identity

Signing keys and identities differ per machine, so they live in untracked files
next to this one, loaded via `include` rules in `config`. Git silently skips a
missing include, so each machine only sets what it needs.

- **Signing key** — copy `config-local.example` to `config-local` and set your
  key. Loaded unconditionally, so it applies everywhere by default.
- **Work/per-directory identity** — copy `config-work.example` to `config-work`
  and fill in your details. Loaded via the `[includeIf "gitdir:…"]` rule, which
  is applied after `config-local` and so overrides it inside work directories.

For `includeIf` to match, `~/Developer/work` must be a real directory all the
way down and work repos must physically live inside it. A symlink anywhere in
the *pattern* path, or a repo whose real location is outside it, never matches
and says nothing — and the failure mode is signing work commits with the
personal key.

Secret scanning, the fish and ghostty configuration, and why any of this is a
symlink: see the [repo README](../README.md).
````

- [ ] **Step 4: Assert the restructure, then commit**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
test "$(git ls-files git/ | wc -l | tr -d ' ')" -eq 5
git ls-files | grep -qx 'git/config'
if git ls-files | grep -qx config; then echo "FAIL: config still tracked at the root"; exit 1; fi|if git ls-files | grep -qx config; then echo "FAIL: config still tracked at the root"; exit 1; fi
test ! -e .githooks
test -f git/README.md
if grep -q core.hooksPath git/README.md; then echo "FAIL: hooksPath still documented"; exit 1; fi
test -f .gitleaks.toml && test -f .markdownlint.jsonc
test -f .github/workflows/gitleaks.yml
git add git/README.md
git commit -m "Move the git configuration into git/, drop .githooks for lefthook"
test -z "$(git status --porcelain)"
```

- [ ] **Step 5: Assert the rename did not orphan the history**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
plain=$(git log --oneline -- git/config | wc -l | tr -d ' ')
follow=$(git log --follow --oneline -- git/config | wc -l | tr -d ' ')
test "$plain" -eq 1
test "$follow" -gt "$plain"
git log --follow --diff-filter=R --name-status -1 -- git/config | grep -q 'git/config'
```

Measured: after the move, plain `git log` reports 1 commit while `--follow`
reports 6, and the move registers as `rename config => git/config (100%)`.
Asserting that `--follow` sees strictly more proves the rename was detected
without hardcoding either count.

---

### Task 5: Phase 1 — track git's own default excludes file as `git/ignore`

`~/.gitignore` lives outside every repo, nothing backs it up, and the Task 12
tarball does not even reach it — that archive is rooted at `~/.config` and this
file sits one level up. Through the link, `$XDG_CONFIG_HOME/git/ignore` is git's
own documented default, so tracking it there needs no configuration at all.

**Files:**

- Create: `git/ignore` (copied from `~/.gitignore`)
- Modify: `git/config` — delete the `core.excludesfile` line

**Interfaces:**

- Consumes: Task 4's `git/` directory.
- Produces: 6 tracked files under `git/` — the count Task 11's gate asserts.

- [ ] **Step 1: Copy — `cp`, not `mv`**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
cp ~/.gitignore git/ignore
test -f ~/.gitignore && test -f git/ignore
```

`cp` matters. Until Task 13 the live global config is still
`~/.config/git/config`, which still points `core.excludesfile` at
`~/.gitignore`; moving that file now would silently stop `.remember/` from being
ignored anywhere, in exactly the window where a stray `git add -A` could stage
it. The original is displaced in Task 13 with everything else, and nothing
outside the repo is touched before then.

- [ ] **Step 2: Delete the `excludesfile` line from `git/config`**

The `[core]` section becomes:

```gitconfig
[core]
	editor = code --wait
```

- [ ] **Step 3: Assert, then commit**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
test -f git/config
if grep -q excludesfile git/config; then echo "FAIL: excludesfile survives"; exit 1; fi
grep -q 'editor = code --wait' git/config
git add git/ignore git/config
git commit -m "Track git's default excludes file as git/ignore"
test "$(git ls-files git/ | wc -l | tr -d ' ')" -eq 6
test -z "$(git status --porcelain)"
```

`! grep -q` rather than `grep -c`: `grep -c` prints `0` and exits **1** when the
edit is correct, which any `set -e` runner reads as a failure.

---

### Task 6: Phase 1 — the root README, the allow-list, and the hook

The root `.gitignore` must exist **before** `fish/` is added in Task 7, or
`fish_variables` walks straight into the index.

**Files:**

- Create: `README.md` (root)
- Create: `.gitignore` (root)
- Create: `lefthook.yml`

**Interfaces:**

- Consumes: `.gitleaks.toml` at the root, which arrived with the rename.
- Produces: the allow-list Task 7 depends on, and an installed pre-commit hook.
  `bin/install` (Task 8) runs `lefthook install` itself; this task's manual run
  is what gives *this* clone hooks now.

- [ ] **Step 1: Write the root `.gitignore`**

Exactly this, and mind both mechanical constraints — the re-includes come after
`/fish/*`, and no pattern carries a trailing comment:

```gitignore
.DS_Store

# .remember/ follows the link into the tree. Every annotation in this file sits
# on its own line: gitignore honours # only at the start of a line, so a
# trailing comment becomes part of the pattern and silently disables it.
/git/.remember/

# fish: the record is what I wrote. Tools generated the other 91 entries —
# fisher owns 82, fish_plugins is the declaration behind those, five are
# tool-generated and three are OrbStack completion symlinks.
#
# The two directory re-includes must stay below /fish/*: a file cannot be
# re-included once a parent directory is excluded. Measured — hoisted above it,
# only config.fish and fish_plugins stage, and the other four vanish silently.
/fish/*
!/fish/config.fish
!/fish/fish_plugins
!/fish/conf.d/
!/fish/functions/
/fish/conf.d/*
!/fish/conf.d/android.fish
!/fish/conf.d/proto.fish
!/fish/conf.d/rustup.fish
/fish/functions/*
!/fish/functions/gfu.fish
```

`config-local` and `config-work` are covered by `git/.gitignore`, which arrived
with the rename and needs no change. `/fish/completions/` needs no rule of its
own: `/fish/*` covers it and nothing re-includes it, because every file in it is
generated.

- [ ] **Step 2: Write `lefthook.yml`**

```yaml
assert_lefthook_installed: true
pre-commit:
  parallel: true
  commands:
    gitleaks:
      run: |
        command -v gitleaks >/dev/null || { echo "✖ gitleaks not installed — brew install gitleaks"; exit 1; }
        gitleaks git --staged --no-banner --redact -v --config .gitleaks.toml
```

- [ ] **Step 3: Write the root `README.md`**

This file carries everything a person needs to *do*, and delegates every *why*
to the design document with a single link. Do not restate measurements, rejected
alternatives or phases here — duplicating them is how the two documents begin to
disagree.

`````markdown
# consus

The configuration this machine's tools actually read. Each tool finds it at its
own default path, which is a symlink into this repo:

```text
~/.config/git   →  <this clone>/git
~/.config/fish  →  <this clone>/fish
```

Ghostty is the exception. Its winning config path on macOS is
`~/Library/Application Support/com.mitchellh.ghostty/config`, which no symlink
under `~/.config` can outrank, so it gets a one-line `config-file` include at
`~/.config/ghostty/config.ghostty` instead — written by `bin/install`.

## What is here

- **git** — the global config, its two per-machine examples, and `ignore`,
  which is git's own default global excludes path.
- **fish** — the hand-written configuration only: `config.fish`,
  `fish_plugins`, three files under `conf.d/` and one function. Everything
  fisher or a tool generated is ignored on purpose — `fish_plugins` is the
  record, and those 82 plugin files are its build output.
- **ghostty** — four settings, plus an optional per-machine include.

Deliberately not managed: **zed**, whose settings-sync extensions are in flight
and would compete with anything versioned here; **opencode**, which has no
binary installed anywhere on this machine; **gh**, whose entire payload is
`git_protocol: https` plus one alias; and **micro**, whose payload is literally
`{}`.

## A fresh machine

```sh
brew install lefthook gitleaks
git clone https://github.com/LRNZ09/consus.git ~/Developer/LRNZ09/consus
cd ~/Developer/LRNZ09/consus
./bin/install            # the two links, the ghostty include, lefthook, chmod 700
```

Then bootstrap fisher. A fresh clone has `fish_plugins` and no fisher at all —
fisher's own two files are among the ignored ones, so the command that reads the
record does not exist yet:

```fish
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
fisher install jorgebucaran/fisher   # makes fisher itself permanent
fisher update                        # materialises the rest from fish_plugins
```

Finally:

```sh
./bin/doctor             # exits 0 when this machine matches the record
```

`bin/install` never deletes anything. Anything in its way is *moved* into
`~/Backups/consus-install-<timestamp>/`, keeping its path relative to the config
root, so undoing it is a move back. Re-running it is a no-op. The run is
all-or-nothing: every path is classified and every decision settled before
anything moves. A real directory or file in the way needs a decision, which can
be typed at the prompt or declared with
`--resolve <fish|git>=<overwrite|merge|refuse>`; with neither, and no TTY, it
prints the diff and refuses.

## Per-machine settings

- **git** — `git/config-local`, untracked and included last, so it wins. Copy
  it from `git/config-local.example`. Work identity goes in `git/config-work`,
  which loads only inside `~/Developer/work/`; for that to match, that
  directory must be real all the way down and work repos must physically live
  inside it.
- **fish** — any new `conf.d/*.fish` file is machine-local by default: the
  allow-list in `.gitignore` ignores everything under `fish/` it does not name.
  `bin/doctor` reports such a file, which is the only way it becomes visible.
- **ghostty** — `~/.config/ghostty/local.ghostty`. The repo's config ends with
  an optional include of it, so a machine without one loads nothing and says
  nothing.

## The hazard of a linked directory

`~/.config/git` and `~/.config/fish` are symlinks **into this repo**, so
anything that writes through them writes here. In particular,
`rm -rf ~/.config/fish/` — with the trailing slash — follows the link and
empties this repo's `fish/` directory. `git restore` brings back the six tracked
files; the other 91 need `fisher update` (which needs network), a tool
regenerating its own completions, or OrbStack running again.

`bin/doctor` exists because link integrity is the one invariant git cannot
express: this repo can be pristine while `~/.config` points somewhere else, and
for git and fish a severed link is completely silent.

## Secret scanning

`lefthook` runs `gitleaks` over staged changes before every commit —
`bin/install` runs `lefthook install` for you. `.github/workflows/gitleaks.yml`
re-scans the full history on every push, as the backstop `--no-verify` cannot
bypass. Rules live in `.gitleaks.toml`, which flags any committed email address
that is not a GitHub noreply.

## Why any of this

The [design document][design] carries the eight mechanisms that were priced,
the five silent failure modes that killed the runner-up, the destruction
accounting, and the record of the migration itself.

[design]: docs/superpowers/specs/2026-08-21-consus-migration-design.md
`````

- [ ] **Step 4: Commit, then install the hook**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
git add README.md .gitignore lefthook.yml
git commit -m "Add the root README, the fish allow-list and lefthook"
# lefthook resolves its config from the CWD, so a bare call from elsewhere
# creates a lefthook.yml there and installs hooks into the wrong repo.
( cd "$CLONE" && lefthook install )
test -f "$CLONE/.git/hooks/pre-commit"
markdownlint-cli2 README.md git/README.md >/dev/null
```

A fresh clone has no `core.hooksPath` — that setting lives in the *old*
checkout's local config, which is not tracked and does not travel — so
`lefthook install` is what gives this clone hooks at all.

- [ ] **Step 5: Prove the hook blocks a secret, as a positive assertion**

The finding is built from a split string so that this plan document does not
itself contain an email address its own hook would reject:

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
printf 'contact = leak@%s\n' example.com > leaktest.txt
git add leaktest.txt
if git commit -m 'this must be blocked'; then
	echo 'FAIL: the pre-commit hook did not block a planted secret'
	exit 1
fi
git restore --staged leaktest.txt
mkdir -p ~/Backups
mv leaktest.txt ~/Backups/leaktest-$(date +%Y%m%dT%H%M%S).txt
test -z "$(git status --porcelain)"
```

Measured: gitleaks reports `leaks found: 1` and the commit exits non-zero. The
timestamp on the moved file means a retried Task 6 cannot clobber the previous
artefact.

---

### Task 7: Phase 1 — copy fish and ghostty in, and pin the plugins

**Files:**

- Create: `fish/` — the whole 97-entry tree, of which 6 files are tracked
- Modify: `fish/fish_plugins` — add the `plugin-git` pin
- Create: `ghostty/config.ghostty`

**Interfaces:**

- Consumes: Task 1's 97-entry fish tree, Task 2's portability edits, Task 6's
  allow-list.
- Produces: `fish/fish_plugins` with the pins Task 9's doctor compares against,
  and `ghostty/config.ghostty` — the include target `bin/install` writes a stub
  for and `bin/doctor` validates.

- [ ] **Step 1: Copy the fish directory whole**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
cp -R ~/.config/fish fish
test "$(find fish ! -type d | wc -l | tr -d ' ')" -eq 97
test "$(find fish -type l | wc -l | tr -d ' ')" -eq 3
```

All 97 entries, as they stand after Task 1. The allow-list stages only the 6
hand-written ones, and the other 91 have to be present in the working tree
regardless: after activation this directory *is* `~/.config/fish`, so fisher's
files must physically live here for fish to work at all. Ignored and absent are
different things. `cp -R` keeps the three OrbStack entries as symlinks into
`/Applications/OrbStack.app`, which is correct — they are machine-specific,
ignored, and a clone should not carry them.

- [ ] **Step 2: Assert the allow-list stages exactly six files**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
. ~/Backups/consus-migration.env
git add fish
test "$(git diff --cached --name-only | wc -l | tr -d ' ')" -eq 6
git diff --cached --name-only | sort > "$SP"/staged
printf '%s\n' fish/conf.d/android.fish fish/conf.d/proto.fish \
	fish/conf.d/rustup.fish fish/config.fish fish/fish_plugins \
	fish/functions/gfu.fish | sort > "$SP"/expected
diff -u "$SP"/expected "$SP"/staged
```

If anything else appears, stop: the `.gitignore` from Task 6 is wrong, most
likely in the ordering of the two directory re-includes.
`git check-ignore -v fish/fish_variables` names the rule that should have caught
it.

- [ ] **Step 3: Commit the fish record**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
git commit -m "Track the hand-written fish configuration"
test "$(git ls-files fish | wc -l | tr -d ' ')" -eq 6
test -z "$(git status --porcelain)"
```

An empty `git status` here is the real assertion: it means the allow-list covers
every one of the 91 generated entries.

- [ ] **Step 4: Pin the plugins**

`fish/fish_plugins` becomes exactly:

```text
jorgebucaran/fisher
jhillyerd/plugin-git@v0.4
halostatue/fish-macos@v7
halostatue/fish-utils-core@v3
```

No tag lookup is needed — the tags were resolved while the design was written.
`jorgebucaran/fisher` stays unpinned on purpose: it is the installer, and it
should stay current. `@v0.4` is the coarsest tag `jhillyerd/plugin-git`
publishes, so nothing floats there. The two `halostatue` majors *do* float,
which is a deliberate loosening: the pair is referenced by nothing in the
tracked set and unused in 14 months, so the exposure is bounded.

This edit is the one guaranteed conflict in Task 13's merge — the machine's copy
has no pin — and the merge rule is what resolves it.

- [ ] **Step 5: Assert and commit the pins**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
test "$(wc -l < fish/fish_plugins | tr -d ' ')" -eq 4
grep -qx 'jhillyerd/plugin-git@v0.4' fish/fish_plugins
grep -qx 'jorgebucaran/fisher' fish/fish_plugins
git add fish/fish_plugins
git commit -m "Pin the fish plugins that publish a stable major"
```

- [ ] **Step 6: Write `ghostty/config.ghostty`**

Keep only the four real settings out of a file that is otherwise the shipped
template's comments, and end with the optional per-machine include:

```text
macos-titlebar-style = tabs
shell-integration = fish
shell-integration-features = sudo,title,ssh-terminfo,ssh-env
window-save-state = always

# Optional per-machine overrides. The ? prefix makes a missing target exit 0
# with no diagnostic, while a present one still loads and still wins on
# precedence. This is the one place the ? form is correct: the stub that
# bin/install writes includes *this* file bare, so a broken link fails loudly
# instead of silently reverting to Application Support.
config-file = ?~/.config/ghostty/local.ghostty
```

- [ ] **Step 7: Assert, commit, and confirm the tree is clean**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
mkdir -p ghostty
grep -qx 'macos-titlebar-style = tabs' ghostty/config.ghostty
grep -qx 'window-save-state = always' ghostty/config.ghostty
grep -q 'config-file = ?' ghostty/config.ghostty
git add ghostty/config.ghostty
git commit -m "Track the ghostty configuration"
test -z "$(git status --porcelain)"
```

---

### Task 8: Phase 1 — `bin/install`, with a sandbox that proves it

**This task and the next three are the gate.** The design document says so
directly: both scripts are specified there in prose only, prose in that document
has a measured failure rate, and these scripts are the largest remaining body of
it. So they are written against a harness that runs them for real, against a
redirected `XDG_CONFIG_HOME`, before anything touches `~/.config`.

**Files:**

- Create: `bin/install`
- Create (scratch, **not committed**): `$SP/work/mkfixture.sh`,
  `$SP/work/tests-install.sh`

**Interfaces:**

- Consumes: `fish/`, `git/`, `ghostty/config.ghostty`, `.gitignore`,
  `lefthook.yml` from Tasks 4–7.
- Produces: `bin/install`, taking `--non-interactive`, `--backup-dir DIR`,
  `--resolve <fish|git>=<overwrite|merge|refuse>` and
  `--expect-diff <fish|git>=<digest>` (both repeatable), and
  exiting 0 on success, 1 on any unresolved path, and 2 on a bad argument.
  Backups default to `~/Backups/consus-install-<timestamp>/` and hold each
  displaced path at its position relative to the config root. It prints a
  12-hex-character digest at the end of every diff, which
  `--expect-diff` quotes back. Tasks 10 and 13 both drive it non-interactively.

- [ ] **Step 1: Write the sandbox fixture builder**

To `$SP/work/mkfixture.sh`. It copies the clone's working tree (without its
history) and the machine's real `fish` and `git` trees, then applies the three
kinds of drift that actually happen. Nothing under `~/.config` is written by it.

```sh
#!/bin/sh
# Builds a throwaway sandbox that mimics this clone plus a drifted machine, so
# bin/install and bin/doctor can be exercised without touching a real path.
#
#   REPO — the consus clone to test (its bin/ scripts are the ones exercised)
#   SB   — the sandbox directory; wiped and rebuilt on every run
#   FISH_SRC, GIT_SRC — default to the machine's real trees; override to point the
#            harness at a simulated tree instead
#
# $SB/repo   a standalone copy of the clone, re-inited so git status means
#            something without touching the real clone's history
# $SB/xdg    a drifted config home: the machine's fish and git trees, plus the
#            three kinds of drift that actually happen
# $SB/xdg2   a second, untouched drifted copy, for the no-TTY assertion
set -eu
REPO="${REPO:?set REPO to the consus clone}"
SB="${SB:?set SB to a scratch directory}"

rm -rf "$SB"
mkdir -p "$SB/repo" "$SB/xdg" "$SB/xdg2"

# The clone's working tree, without its history.
( cd "$REPO" && find . -name .git -prune -o -print | sed 's|^\./||' ) |
	while IFS= read -r entry; do
		[ -n "$entry" ] && [ "$entry" != "." ] || continue
		if [ -d "$REPO/$entry" ] && [ ! -L "$REPO/$entry" ]; then
			mkdir -p "$SB/repo/$entry"
		else
			mkdir -p "$(dirname "$SB/repo/$entry")"
			cp -R "$REPO/$entry" "$SB/repo/$entry"
		fi
	done

# The machine as it stands: fish real, git still the old checkout with its .git.
cp -R "${FISH_SRC:-$HOME/.config/fish}" "$SB/xdg/fish"
cp -R "${GIT_SRC:-$HOME/.config/git}" "$SB/xdg/git"

# Three kinds of drift that actually happen.
printf '\n# drifted by hand\n' >> "$SB/xdg/fish/config.fish"
printf 'function drifted\nend\n' > "$SB/xdg/fish/functions/drifted.fish"
sed -i '' 's|fish-macos@v7|fish-macos|' "$SB/xdg/fish/fish_plugins"

cp -R "$SB/xdg/fish" "$SB/xdg2/fish"
cp -R "$SB/xdg/git" "$SB/xdg2/git"

# A history, so `git status` and `git check-ignore` mean something. hooksPath is
# neutralised because the fixture has no hooks and no lefthook install.
cd "$SB/repo"
git init -q -b main .
git add -A
git -c core.hooksPath=/dev/null commit -q --no-gpg-sign -m 'fixture'
echo "fixture ready at $SB — $(git ls-files | wc -l | tr -d ' ') tracked files, $(git ls-files fish | wc -l | tr -d ' ') under fish/"
```

`$SB` is under `$SP`, which Task 0 created as `~/Backups/consus-sandbox` with
mode 700 — **not** under `/tmp`. The fixture copies `~/.config/git` wholesale,
which means `config-local`, `config-work` and the mode-700 `.remember/`, so a
world-readable sandbox would leak all three.

- [ ] **Step 2: Write the install suite**

To `$SP/work/tests-install.sh`. Every assertion here was run while this plan was
written; the counts in the expectations are what it actually printed.

```sh
#!/bin/sh
# Exercises bin/install against the sandbox fixture. No real path is touched:
# every run is aimed at a redirected XDG_CONFIG_HOME under $SB.
set -u
SP="${SP:?set SP to the scratch directory}"; SB="$SP/sb"
pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1"; fi; }

SB="$SB" REPO="${REPO:?set REPO to the consus clone}" sh "$SP/work/mkfixture.sh" >/dev/null 2>&1 || { echo "fixture build failed"; exit 1; }
cd "$SB/repo" || exit 1

check "install parses under sh"            'sh -n bin/install'
check "allow-list stages 6 fish files"     '[ "$(git ls-files fish | wc -l | tr -d " ")" -eq 6 ]'
check "nothing untracked-and-unignored"    '[ -z "$(git status --porcelain)" ]'

# --- no TTY: refuse, print, change nothing ---------------------------------
XDG_CONFIG_HOME="$SB/xdg2" ./bin/install --non-interactive --backup-dir "$SB/backup2" >"$SB/ni.log" 2>&1
ni_rc=$?
check "non-interactive exits 1"            '[ "$ni_rc" -eq 1 ]'
check "  prints the refusal"               'grep -q "no TTY to ask" "$SB/ni.log"'
check "  xdg2/fish is still a real dir"    '[ -d "$SB/xdg2/fish" ] && [ ! -L "$SB/xdg2/fish" ]'
check "  backup2 was never created"        '[ ! -e "$SB/backup2" ]'
check "  diff named config.fish"           'grep -q "differ:          config.fish" "$SB/ni.log"'
check "  diff named fish_plugins"          'grep -q "differ:          fish_plugins" "$SB/ni.log"'
check "  diff hid ignored fish files"      '! grep -qE "^  differ: .*(fish_variables|functions/fisher)" "$SB/ni.log"'
check "  git diff named .githooks"         'grep -q "only on machine: .githooks/pre-commit" "$SB/ni.log"'
check "  git diff named .github"           'grep -q "only on machine: .github/workflows/gitleaks.yml" "$SB/ni.log"'
check "  git diff named .gitleaks.toml"    'grep -q "only on machine: .gitleaks.toml" "$SB/ni.log"'
check "  git diff named docs/"             'grep -q "only on machine: docs/superpowers/specs/2026-08-21-consus-migration-design.md" "$SB/ni.log"'
check "  git diff excluded .git/"          '! grep -qE "^  (differ|only[^:]*): +\.git/" "$SB/ni.log"'
check "  git diff excluded config-local"   '! grep -qE "config-local$" "$SB/ni.log"'

# --- with a TTY: merge at fish, overwrite at git ---------------------------
{ sleep 1; printf 'm\n'; sleep 2; printf 'o\n'; sleep 1; } |
	script -q /dev/null env XDG_CONFIG_HOME="$SB/xdg" ./bin/install --backup-dir "$SB/backup" >"$SB/i.log" 2>&1
check "interactive run completed"          'grep -q "install complete" "$SB/i.log"'
check "  fish is a link into the repo"     '[ "$(readlink "$SB/xdg/fish")" = "$SB/repo/fish" ]'
check "  git is a link into the repo"      '[ "$(readlink "$SB/xdg/git")" = "$SB/repo/git" ]'
check "  the stub names this clone"        '[ "$(cat "$SB/xdg/ghostty/config.ghostty")" = "config-file = $SB/repo/ghostty/config.ghostty" ]'
check "  status: exactly the 2 fish files" '[ "$(git status --porcelain)" = " M fish/config.fish
 M fish/fish_plugins" ]'
check "  machine won in config.fish"       'grep -q "drifted by hand" fish/config.fish'
check "  machine won in fish_plugins"      'grep -qx "jhillyerd/plugin-git" fish/fish_plugins'
check "  the hidden file arrived"          '[ -f fish/functions/drifted.fish ]'
check "  and is invisible to git status"   '[ -z "$(git status --porcelain fish/functions/drifted.fish)" ]'
check "  backup holds the old fish tree"   '[ -f "$SB/backup/fish/config.fish" ]'
check "  backup holds the old checkout"    '[ -d "$SB/backup/git/.git" ]'
check "  overwrite copied nothing in"      '[ ! -e git/.githooks ] && [ ! -e git/.gitleaks.toml ]'
check "  repo root is mode 700"            '[ "$(stat -f "%Lp" "$SB/repo")" = "700" ]'

# --- convergence ----------------------------------------------------------
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --backup-dir "$SB/backup" >"$SB/i2.log" 2>&1
i2_rc=$?
check "a second run exits 0"               '[ "$i2_rc" -eq 0 ]'
check "  reports both links already right" '[ "$(grep -c "already linked" "$SB/i2.log")" -eq 2 ]'
check "  reports the stub already right"   'grep -q "already includes this clone" "$SB/i2.log"'
check "  wrote no new backup entries"      '[ "$(ls "$SB/backup" | wc -l | tr -d " ")" -eq 2 ]'

# --- a wrong link self-heals, even without a TTY --------------------------
unlink "$SB/xdg/fish"; ln -s /tmp/nowhere-consus "$SB/xdg/fish"
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive --backup-dir "$SB/backup3" >"$SB/i3.log" 2>&1
i3_rc=$?
check "a wrong link is relinked, rc 0"     '[ "$i3_rc" -eq 0 ]'
check "  the link is now correct"          '[ "$(readlink "$SB/xdg/fish")" = "$SB/repo/fish" ]'
check "  the old link moved to backup3"    '[ -L "$SB/backup3/fish" ]'
check "  its target was untouched"         '[ -f "$SB/repo/fish/config.fish" ]'

# --- an occupied backup slot is refused ----------------------------------
unlink "$SB/xdg/fish"; ln -s /tmp/nowhere-consus "$SB/xdg/fish"
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive --backup-dir "$SB/backup3" >"$SB/i4.log" 2>&1
i4_rc=$?
check "an occupied slot exits 1"           '[ "$i4_rc" -eq 1 ]'
check "  says the slot is occupied"        'grep -q "already occupied" "$SB/i4.log"'
check "  leaves the wrong link alone"      '[ "$(readlink "$SB/xdg/fish")" = "/tmp/nowhere-consus" ]'
unlink "$SB/xdg/fish"; ln -s "$SB/repo/fish" "$SB/xdg/fish"

# --- an empty config home -------------------------------------------------
mkdir -p "$SB/xdg3"
XDG_CONFIG_HOME="$SB/xdg3" ./bin/install --non-interactive --backup-dir "$SB/backup4" >"$SB/i5.log" 2>&1
i5_rc=$?
check "an empty config home exits 0"       '[ "$i5_rc" -eq 0 ]'
check "  fish linked from nothing"         '[ "$(readlink "$SB/xdg3/fish")" = "$SB/repo/fish" ]'
check "  git linked from nothing"          '[ "$(readlink "$SB/xdg3/git")" = "$SB/repo/git" ]'
check "  no backup directory created"      '[ ! -e "$SB/backup4" ]'

./bin/install --nonsense >/dev/null 2>&1; a_rc=$?
check "an unknown argument exits 2"        '[ "$a_rc" -eq 2 ]'


# --- argument validation ---------------------------------------------------
./bin/install --resolve fsh=merge >"$SB/r1.log" 2>&1; r1=$?
check "a typo'd path exits 2"              '[ "$r1" -eq 2 ]'
check "  names the unknown path"           'grep -q "unknown path .fsh." "$SB/r1.log"'
./bin/install --resolve fish=bogus >"$SB/r2.log" 2>&1; r2=$?
check "an unknown action exits 2"          '[ "$r2" -eq 2 ]'
check "  names the unknown action"         'grep -q "unknown action .bogus." "$SB/r2.log"'
./bin/install --resolve fish >"$SB/r3.log" 2>&1; r3=$?
check "a missing = exits 2"                '[ "$r3" -eq 2 ]'
./bin/install --resolve fish=merge --resolve fish=overwrite >"$SB/r4.log" 2>&1; r4=$?
check "conflicting resolutions exit 2"     '[ "$r4" -eq 2 ]'
check "  names the conflict"               'grep -q "given twice" "$SB/r4.log"'
./bin/install --resolve ghostty/config.ghostty=overwrite >"$SB/r5.log" 2>&1; r5=$?
check "the stub is not resolvable, exit 2" '[ "$r5" -eq 2 ]'
./bin/install --expect-diff fish=nothex123456 >"$SB/r6.log" 2>&1; r6=$?
check "a non-hex digest exits 2"           '[ "$r6" -eq 2 ]'
./bin/install --expect-diff fish=abc123 >"$SB/r7.log" 2>&1; r7=$?
check "a short digest exits 2"             '[ "$r7" -eq 2 ]'
check "  says how long a digest is"        'grep -q "12 hex characters" "$SB/r7.log"'
./bin/install --nonsense >/dev/null 2>&1; a_rc=$?
check "an unknown argument exits 2"        '[ "$a_rc" -eq 2 ]'

# --- no TTY, nothing declared: print the diff and its digest, change nothing
SB="$SB" REPO="${REPO}" sh "$SP/work/mkfixture.sh" >/dev/null 2>&1 || { echo "fixture rebuild failed"; exit 1; }
cd "$SB/repo" || exit 1
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive --backup-dir "$SB/backupN" >"$SB/n.log" 2>&1
n_rc=$?
check "an undeclared no-TTY run exits 1"   '[ "$n_rc" -eq 1 ]'
check "  prints a digest for fish"         'grep -qE "end of diff, digest fish=[0-9a-f]{12}" "$SB/n.log"'
check "  prints a digest for git"          'grep -qE "end of diff, digest git=[0-9a-f]{12}" "$SB/n.log"'
check "  suggests the exact merge flags"   'grep -qE "resolve fish=merge --expect-diff fish=[0-9a-f]{12}" "$SB/n.log"'
check "  reports 2 unresolved paths"       'grep -q "2 path(s) unresolved" "$SB/n.log"'
check "  fish untouched"                   '[ -d "$SB/xdg/fish" ] && [ ! -L "$SB/xdg/fish" ]'
check "  git untouched"                    '[ -d "$SB/xdg/git" ] && [ ! -L "$SB/xdg/git" ]'
check "  no stub written"                  '[ ! -e "$SB/xdg/ghostty/config.ghostty" ]'
check "  no backup directory created"      '[ ! -e "$SB/backupN" ]'

# --- all-or-nothing: one undeclared path stops the whole run --------------
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive --resolve git=overwrite \
	--backup-dir "$SB/backupP" >"$SB/p.log" 2>&1
p_rc=$?
check "a half-declared run exits 1"        '[ "$p_rc" -eq 1 ]'
check "  git was NOT overwritten"          '[ -d "$SB/xdg/git" ] && [ ! -L "$SB/xdg/git" ]'
check "  and nothing was backed up"        '[ ! -e "$SB/backupP" ]'

# --- merge needs a reviewed diff -----------------------------------------
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive \
	--resolve fish=merge --resolve git=overwrite --backup-dir "$SB/backupM" >"$SB/m.log" 2>&1
m_rc=$?
check "merge without a digest exits 1"     '[ "$m_rc" -eq 1 ]'
check "  says which digest it wants"       'grep -qE "needs --expect-diff fish=[0-9a-f]{12}" "$SB/m.log"'
check "  changed nothing"                  '[ ! -L "$SB/xdg/fish" ] && [ ! -L "$SB/xdg/git" ] && [ ! -e "$SB/backupM" ]'

XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive \
	--resolve fish=merge --expect-diff fish=000000000000 --resolve git=overwrite \
	--backup-dir "$SB/backupW" >"$SB/w.log" 2>&1
w_rc=$?
check "a stale digest exits 1"             '[ "$w_rc" -eq 1 ]'
check "  names both digests"               'grep -q "expected fish=000000000000" "$SB/w.log"'
check "  changed nothing"                  '[ ! -L "$SB/xdg/fish" ] && [ ! -e "$SB/backupW" ]'

# --- the digest from the review pass unlocks the apply pass --------------
FD=$(sed -n 's/^  --- end of diff, digest fish=\([0-9a-f]*\) ---$/\1/p' "$SB/n.log")
check "a digest was recoverable from the log" '[ -n "$FD" ]'
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive \
	--resolve fish=merge --expect-diff "fish=$FD" --resolve git=overwrite \
	--backup-dir "$SB/backupR" >"$SB/rd.log" 2>&1
rd_rc=$?
check "declared + digest exits 0"          '[ "$rd_rc" -eq 0 ]'
check "  the diff precedes the decision"   '[ "$(grep -n "differ:          config.fish" "$SB/rd.log" | head -1 | cut -d: -f1)" -lt "$(grep -n "declared   .*fish: merge" "$SB/rd.log" | head -1 | cut -d: -f1)" ]'
check "  fish links into the repo"         '[ "$(readlink "$SB/xdg/fish")" = "$SB/repo/fish" ]'
check "  git links into the repo"          '[ "$(readlink "$SB/xdg/git")" = "$SB/repo/git" ]'
check "  the stub names this clone"        '[ "$(cat "$SB/xdg/ghostty/config.ghostty")" = "config-file = $SB/repo/ghostty/config.ghostty" ]'
check "  same queue as the typed run"      '[ "$(git status --porcelain)" = " M fish/config.fish
 M fish/fish_plugins" ]'
check "  the hidden file arrived"          '[ -f fish/functions/drifted.fish ]'
check "  overwrite copied nothing into git/" '[ ! -e git/.githooks ] && [ ! -e git/.gitleaks.toml ]'
check "  backup holds both trees"          '[ -f "$SB/backupR/fish/config.fish" ] && [ -d "$SB/backupR/git/.git" ]'
check "  warns that a merge needs review"  'grep -q "declared merge put the machine.s content" "$SB/rd.log"'

# --- a converged re-run is a no-op, same command line -------------------
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive \
	--resolve fish=merge --expect-diff "fish=$FD" --resolve git=overwrite \
	--backup-dir "$SB/backupR" >"$SB/rd2.log" 2>&1
rd2_rc=$?
check "a converged re-run exits 0"         '[ "$rd2_rc" -eq 0 ]'
check "  says both resolutions unneeded"   '[ "$(grep -c "was not needed here" "$SB/rd2.log")" -eq 2 ]'
check "  wrote no new backup entries"      '[ "$(ls "$SB/backupR" | wc -l | tr -d " ")" -eq 2 ]'

# --- an occupied slot is caught before anything moves ------------------
SB="$SB" REPO="${REPO}" sh "$SP/work/mkfixture.sh" >/dev/null 2>&1 || { echo "fixture rebuild failed"; exit 1; }
cd "$SB/repo" || exit 1
mkdir -p "$SB/backupO"; printf 'squatter\n' > "$SB/backupO/fish"
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive \
	--resolve fish=overwrite --resolve git=overwrite --backup-dir "$SB/backupO" >"$SB/o.log" 2>&1
o_rc=$?
check "an occupied slot exits 1"           '[ "$o_rc" -eq 1 ]'
check "  says the slot is occupied"        'grep -q "already occupied" "$SB/o.log"'
check "  git was NOT overwritten either"   '[ -d "$SB/xdg/git" ] && [ ! -L "$SB/xdg/git" ]'
check "  the squatter is untouched"        '[ "$(cat "$SB/backupO/fish")" = "squatter" ]'

# --- an explicit refuse still refuses ---------------------------------
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive \
	--resolve fish=refuse --resolve git=refuse --backup-dir "$SB/backupF" >"$SB/rf.log" 2>&1
rf_rc=$?
check "declared refuse exits 1"            '[ "$rf_rc" -eq 1 ]'
check "  says it refused as declared"      '[ "$(grep -c "refused as declared" "$SB/rf.log")" -eq 2 ]'
check "  both paths left alone"            '[ -d "$SB/xdg/fish" ] && [ ! -L "$SB/xdg/fish" ] && [ -d "$SB/xdg/git" ] && [ ! -L "$SB/xdg/git" ]'
check "  no backup directory created"      '[ ! -e "$SB/backupF" ]'
check "  the equals form parses too"       'XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive --resolve=fish=refuse --backup-dir "$SB/backupF2" >/dev/null 2>&1; [ $? -eq 1 ] && [ ! -e "$SB/backupF2" ]'


# --- the digest commits to content, not only to file names ---------------
SB="$SB" REPO="${REPO}" sh "$SP/work/mkfixture.sh" >/dev/null 2>&1 || { echo "fixture rebuild failed"; exit 1; }
cd "$SB/repo" || exit 1
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive --backup-dir "$SB/bkD1" >"$SB/d1.log" 2>&1
D1=$(sed -n 's/^  --- end of diff, digest fish=\([0-9a-f]*\) ---$/\1/p' "$SB/d1.log")
printf '\n# edited again, same file list\n' >> "$SB/xdg/fish/config.fish"
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive --backup-dir "$SB/bkD2" >"$SB/d2.log" 2>&1
D2=$(sed -n 's/^  --- end of diff, digest fish=\([0-9a-f]*\) ---$/\1/p' "$SB/d2.log")
check "editing a differing file moves the digest" '[ -n "$D1" ] && [ -n "$D2" ] && [ "$D1" != "$D2" ]'
check "  the file list is unchanged"              '[ "$(grep -c "^  differ:" "$SB/d1.log")" -eq "$(grep -c "^  differ:" "$SB/d2.log")" ]'
check "  the stale digest is refused"             'XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive --resolve fish=merge --expect-diff "fish=$D1" --resolve git=overwrite --backup-dir "$SB/bkD3" >/dev/null 2>&1; [ $? -eq 1 ] && [ ! -e "$SB/bkD3" ]'

# --- merge is only defined for fish -------------------------------------
./bin/install --resolve git=merge >"$SB/gm.log" 2>&1; gm=$?
check "--resolve git=merge exits 2"          '[ "$gm" -eq 2 ]'
check "  says merge is fish-only"            'grep -q "merge is only defined for fish" "$SB/gm.log"'
{ sleep 1; printf 'o\n'; sleep 2; printf 'm\n'; sleep 1; } |
	script -q /dev/null env XDG_CONFIG_HOME="$SB/xdg" ./bin/install --backup-dir "$SB/bkGM" >"$SB/gm2.log" 2>&1
gm2=$?
check "typing m at the git prompt refuses"   'grep -q "merge is only defined for fish" "$SB/gm2.log"'
check "  the prompt does not offer merge for git" 'grep -q "Resolve .*/git — \[o\]verwrite (repo wins) / \[r\]efuse:" "$SB/gm2.log"'
check "  and nothing was linked"             '[ ! -L "$SB/xdg/fish" ] && [ ! -L "$SB/xdg/git" ]'

# --- a missing record refuses, rather than linking to nothing ----------
SB="$SB" REPO="${REPO}" sh "$SP/work/mkfixture.sh" >/dev/null 2>&1 || { echo "fixture rebuild failed"; exit 1; }
cd "$SB/repo" || exit 1
mv git "$SB/git-moved-away"
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive --resolve fish=refuse \
	--backup-dir "$SB/bkMR" >"$SB/mr.log" 2>&1
mr=$?
check "a missing record exits 1"             '[ "$mr" -eq 1 ]'
check "  names the missing record"           'grep -q "the record is missing" "$SB/mr.log"'
check "  the live path was not displaced"    '[ -d "$SB/xdg/git" ] && [ ! -L "$SB/xdg/git" ]'
mv "$SB/git-moved-away" git

# --- an unwritable backup directory refuses before anything moves -----
printf 'not a directory\n' > "$SB/bkFile"
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive \
	--resolve fish=overwrite --resolve git=overwrite --backup-dir "$SB/bkFile" >"$SB/bf.log" 2>&1
bf=$?
check "an unusable backup dir exits 1"       '[ "$bf" -eq 1 ]'
check "  says it cannot be written"          'grep -q "cannot be created or written" "$SB/bf.log"'
check "  nothing was linked"                 '[ ! -L "$SB/xdg/fish" ] && [ ! -L "$SB/xdg/git" ]'

# --- an unreadable machine path refuses rather than diffing partially --
chmod 000 "$SB/xdg/fish"
XDG_CONFIG_HOME="$SB/xdg" ./bin/install --non-interactive \
	--resolve fish=overwrite --resolve git=overwrite --backup-dir "$SB/bkUR" >"$SB/ur.log" 2>&1
ur=$?
chmod 700 "$SB/xdg/fish"
check "an unreadable path exits 1"           '[ "$ur" -eq 1 ]'
check "  says it is not readable"            'grep -q "is not readable" "$SB/ur.log"'
check "  git was not linked either"          '[ ! -L "$SB/xdg/git" ] && [ ! -e "$SB/bkUR" ]'

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
```

Three notes on the harness. The interactive resolutions are fed through
`script -q /dev/null`, because `bin/install` refuses without a TTY by design and
a plain pipe cannot exercise the prompt — the `sleep`s matter, since `script`
forwards EOF immediately otherwise, and without them the answers shift by one
and `m` lands on the *git* path, which is the one outcome Task 13 forbids. That
fragility is exactly why Tasks 10 and 13 declare decisions instead of feeding
the prompt, and why this pty test stays confined to a fixture whose state is
fixed. Finally, the `.git/` assertion matches the *listing* lines: the diff's
own header contains the string `.git/` in its explanatory text.

- [ ] **Step 3: Run the suite and watch it fail**

```sh
. ~/Backups/consus-migration.env
SP="$SP" REPO="$CLONE" sh "$SP/work/tests-install.sh"
```

Expected: `FAIL  install parses under sh` and every later assertion failing too,
because `bin/install` does not exist yet.

- [ ] **Step 4: Write `bin/install`**

```sh
#!/bin/sh
# consus/bin/install — point each tool's own default path at this clone.
#
#   $XDG_CONFIG_HOME/fish                    -> <repo>/fish   (symlink)
#   $XDG_CONFIG_HOME/ghostty/config.ghostty                   (one-line include)
#   $XDG_CONFIG_HOME/git                     -> <repo>/git    (symlink, last)
#
# Nothing is ever deleted: every displaced path is MOVED into a timestamped
# backup directory, and every move reverses by moving it back. Re-running is a
# no-op.
#
# The run is all-or-nothing. Every path is classified and every decision settled
# BEFORE anything moves, so a run that cannot finish changes nothing at all
# rather than leaving a half-linked machine behind.
#
# A real directory or file in the way needs a decision. It can be typed at the
# prompt, or declared up front with --resolve <path>=<action>. With neither, and
# no TTY, install prints the diff, prints a digest of it, and refuses — so
# automation that has not been told what to do cannot decide on its own.
#
# --resolve <path>=merge additionally REQUIRES --expect-diff <path>=<digest>,
# the digest install printed for the diff you reviewed. Merge is the only action
# that writes machine content into this repo's working tree, and the digest is
# what ties that write to a diff somebody actually looked at. It also means a
# provisioner cannot carry a durable "always merge" instruction: the digest goes
# stale the moment the machine drifts, and a stale digest refuses.
#
# Usage: bin/install [--non-interactive] [--backup-dir DIR]
#                    [--resolve <fish|git>=<overwrite|merge|refuse>]...
#                    [--expect-diff <fish|git>=<digest>]...
# Why links rather than tool-native includes: the design document under docs/.
set -eu

# The only two paths that can ever need a decision. The ghostty stub is
# install's own output rather than machine content, so it is backed up and
# rewritten without asking.
KNOWN_PATHS='fish git'

usage() {
	echo "usage: bin/install [--non-interactive] [--backup-dir DIR]" >&2
	echo "                   [--resolve <fish|git>=<overwrite|merge|refuse>]..." >&2
	echo "                   [--expect-diff <fish|git>=<digest>]..." >&2
	exit 2
}

non_interactive=0
backup_dir=''
resolutions=''
expectations=''

# known_path <path> — is this one of the paths that can take a decision?
known_path() {
	case " $KNOWN_PATHS " in
	*" $1 "*) return 0 ;;
	esac
	return 1
}

# already_keyed <list> <path> — the value already recorded for <path>, if any.
already_keyed() {
	for k_pair in $1; do
		case "$k_pair" in
		"$2"=*) printf '%s' "${k_pair#*=}"; return 0 ;;
		esac
	done
	return 0
}

# add_resolution <path>=<action>, add_expectation <path>=<digest> — both
# validated here rather than at the point of use, so a typo fails loudly and
# immediately instead of turning into a silent refusal an hour later.
add_resolution() {
	case "$1" in
	*=*) ;;
	*) echo "install: --resolve needs <path>=<action>, got: $1" >&2; usage ;;
	esac
	a_rel=${1%%=*}
	a_action=${1#*=}
	known_path "$a_rel" || {
		echo "install: --resolve: unknown path '$a_rel' (expected one of: $KNOWN_PATHS)" >&2
		usage
	}
	case "$a_action" in
	overwrite | merge | refuse) ;;
	*)
		echo "install: --resolve $a_rel: unknown action '$a_action' (expected overwrite, merge or refuse)" >&2
		usage
		;;
	esac
	# merge copies the machine tree over the repo's, which for the git path
	# would drag the old checkout's whole .git into this repo as a nested
	# repository git status never reports. Only fish has merge semantics.
	if [ "$a_action" = merge ] && [ "$a_rel" != fish ]; then
		echo "install: --resolve $a_rel=merge: merge is only defined for fish" >&2
		echo "  the git path takes overwrite or refuse" >&2
		usage
	fi
	a_prev=$(already_keyed "$resolutions" "$a_rel")
	if [ -n "$a_prev" ] && [ "$a_prev" != "$a_action" ]; then
		echo "install: --resolve $a_rel: given twice ($a_prev, $a_action) — pick one" >&2
		usage
	fi
	resolutions="$resolutions $a_rel=$a_action"
}

add_expectation() {
	case "$1" in
	*=*) ;;
	*) echo "install: --expect-diff needs <path>=<digest>, got: $1" >&2; usage ;;
	esac
	e_rel=${1%%=*}
	e_digest=${1#*=}
	known_path "$e_rel" || {
		echo "install: --expect-diff: unknown path '$e_rel' (expected one of: $KNOWN_PATHS)" >&2
		usage
	}
	case "$e_digest" in
	*[!0-9a-f]*)
		echo "install: --expect-diff $e_rel: '$e_digest' is not a digest install printed" >&2
		usage
		;;
	esac
	if [ "${#e_digest}" -ne 12 ]; then
		echo "install: --expect-diff $e_rel: digests are 12 hex characters, got ${#e_digest}" >&2
		usage
	fi
	e_prev=$(already_keyed "$expectations" "$e_rel")
	if [ -n "$e_prev" ] && [ "$e_prev" != "$e_digest" ]; then
		echo "install: --expect-diff $e_rel: given twice ($e_prev, $e_digest) — pick one" >&2
		usage
	fi
	expectations="$expectations $e_rel=$e_digest"
}

while [ $# -gt 0 ]; do
	case "$1" in
	--non-interactive) non_interactive=1 ;;
	--backup-dir) [ $# -ge 2 ] || usage; backup_dir="$2"; shift ;;
	--backup-dir=*) backup_dir="${1#--backup-dir=}" ;;
	--resolve) [ $# -ge 2 ] || usage; add_resolution "$2"; shift ;;
	--resolve=*) add_resolution "${1#--resolve=}" ;;
	--expect-diff) [ $# -ge 2 ] || usage; add_expectation "$2"; shift ;;
	--expect-diff=*) add_expectation "${1#--expect-diff=}" ;;
	-h | --help) usage ;;
	*) echo "install: unknown argument: $1" >&2; usage ;;
	esac
	shift
done

# The repo path comes from this script's own location, so any clone path works.
# CDPATH is cleared because it can make a relative `cd` land somewhere else.
unset CDPATH
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
[ -n "$backup_dir" ] || backup_dir="$HOME/Backups/consus-install-$(date +%Y%m%dT%H%M%S)"

# lefthook backs the repo's own secret scanning. Checked up front so a missing
# tool cannot leave a half-linked machine behind.
if ! command -v lefthook >/dev/null 2>&1; then
	echo "✖ lefthook is not installed — run: brew install lefthook" >&2
	exit 1
fi

# Scratch files for the diff. These are the script's own temporaries; the
# never-delete rule is about machine paths, not about /tmp.
d_machine=$(mktemp); d_repo=$(mktemp); d_ignored=$(mktemp)
d_scratch=$(mktemp); d_only_m=$(mktemp); d_only_r=$(mktemp); d_both=$(mktemp)
d_listing=$(mktemp)
trap 'rm -f "$d_machine" "$d_repo" "$d_ignored" "$d_scratch" "$d_only_m" "$d_only_r" "$d_both" "$d_listing"' EXIT

# entries <dir> — every non-directory entry relative to <dir>, symlinks
# included (which -type f would miss), with any .git pruned.
entries() {
	( cd -- "$1" && find . -name .git -prune -o ! -type d -print ) | sed 's|^\./||' | sort
}

# show_diff <rel> <machine-path> — what differs between the machine's tree and
# the repo's, skipping .git/ and everything the repo ignores. Without the ignore
# filter, ~/.config/git alone drowns the output in its old object store.
#
# Sets diff_digest to a digest of the listing itself — of the very lines printed
# below, so what the digest commits to is what a reader reviewed. Paths are
# relative, so the digest is stable across clone locations.
show_diff() {
	d_rel="$1"
	d_m="$2"
	d_r="$repo/$1"

	entries "$d_m" > "$d_machine"
	entries "$d_r" > "$d_repo"

	# check-ignore refuses paths outside the repository, so ask it from inside
	# the repo with repo-relative paths, then strip the prefix back off.
	sort -u "$d_machine" "$d_repo" | sed "s|^|$d_rel/|" > "$d_scratch"
	( cd -- "$repo" && git check-ignore --stdin < "$d_scratch" ) 2>/dev/null |
		sed "s|^$d_rel/||" | sort > "$d_ignored" || true

	comm -23 "$d_machine" "$d_ignored" > "$d_scratch"; cp -- "$d_scratch" "$d_machine"
	comm -23 "$d_repo" "$d_ignored" > "$d_scratch"; cp -- "$d_scratch" "$d_repo"

	comm -23 "$d_machine" "$d_repo" > "$d_only_m"
	comm -13 "$d_machine" "$d_repo" > "$d_only_r"
	comm -12 "$d_machine" "$d_repo" > "$d_both"

	: > "$d_listing"
	while IFS= read -r d_entry; do
		[ -n "$d_entry" ] || continue
		if ! cmp -s -- "$d_m/$d_entry" "$d_r/$d_entry" 2>/dev/null; then
			echo "  differ:          $d_entry" >> "$d_listing"
			# The digest has to commit to content, not only to the name: a
			# `differ:` line reads the same whatever the file now holds, so a
			# name-only digest would go stale when a new file appears but not
			# when an already-differing file is edited again.
			printf '    machine %s  repo %s\n' \
				"$(shasum -a 256 -- "$d_m/$d_entry" 2>/dev/null | cut -c1-12)" \
				"$(shasum -a 256 -- "$d_r/$d_entry" 2>/dev/null | cut -c1-12)" \
				>> "$d_listing"
		fi
	done < "$d_both"
	sed '/^$/d; s|^|  only on machine: |' "$d_only_m" >> "$d_listing"
	sed '/^$/d; s|^|  only in repo:    |' "$d_only_r" >> "$d_listing"

	diff_digest=$(shasum -a 256 < "$d_listing" | cut -c1-12)

	echo "  --- $d_m  vs  $d_r   (.git/ and ignored files excluded) ---"
	cat -- "$d_listing"
	echo "  --- end of diff, digest $d_rel=$diff_digest ---"
}

# ---------------------------------------------------------------------------
# Plan. Classify every path and settle every decision before anything moves.
# ---------------------------------------------------------------------------
plan_fish=''; plan_git=''; plan_stub=''
slot_fish=0; slot_git=0; slot_stub=0
unresolved=0
declared_merge=0

# classify <rel> — sets plan_result to one of ok / link / relink / overwrite /
# merge / refuse, and slot_result to 1 when the path will be moved into the
# backup directory.
classify() {
	c_rel="$1"
	c_target="$repo/$1"
	c_path="$config_home/$1"
	plan_result=''
	slot_result=0

	# Never link to something that is not in this clone: without this, a
	# missing $repo/git would send the live global config to the backup and
	# leave a dangling link in its place, with git silently unconfigured.
	if [ ! -d "$c_target" ]; then
		echo "✖ $c_rel: the record is missing — $c_target is not in this clone" >&2
		unresolved=$((unresolved + 1))
		plan_result=refuse
		return 0
	fi
	# A partial diff is worse than no diff: refuse rather than compute one.
	if [ -e "$c_path" ] && [ ! -L "$c_path" ] &&
		{ [ ! -r "$c_path" ] || [ ! -x "$c_path" ]; }; then
		echo "✖ $c_path is not readable — refusing rather than diffing it partially" >&2
		unresolved=$((unresolved + 1))
		plan_result=refuse
		return 0
	fi
	c_declared=$(already_keyed "$resolutions" "$c_rel")
	c_expected=$(already_keyed "$expectations" "$c_rel")

	if [ -L "$c_path" ]; then
		if [ "$(readlink -- "$c_path")" = "$c_target" ]; then
			echo "✓ ok         $c_path -> $c_target (already linked)"
			[ -z "$c_declared" ] || echo "· note      --resolve $c_rel=$c_declared was not needed here"
			plan_result=ok
			return 0
		fi
		# A link pointing anywhere else, dangling included. Moving a link never
		# touches its target, so no machine content is at risk and no decision
		# is needed — this is why a relocated clone self-heals even under
		# --non-interactive.
		echo "→ relink     $c_path is a link to $(readlink -- "$c_path")"
		[ -z "$c_declared" ] || echo "· note      --resolve $c_rel=$c_declared was not needed here"
		plan_result=relink
		slot_result=1
		return 0
	fi

	if [ ! -e "$c_path" ]; then
		echo "→ link       $c_path (nothing there)"
		[ -z "$c_declared" ] || echo "· note      --resolve $c_rel=$c_declared was not needed here"
		plan_result=link
		return 0
	fi

	echo "‼ $c_path is a real path, and the record lives at $c_target"
	show_diff "$c_rel" "$c_path"

	if [ -n "$c_declared" ]; then
		if [ "$c_declared" = merge ]; then
			if [ -z "$c_expected" ]; then
				echo "✖ $c_path: --resolve $c_rel=merge needs --expect-diff $c_rel=$diff_digest" >&2
				echo "  merge is the one action that writes machine content into this repo, so it" >&2
				echo "  only runs against a diff somebody reviewed. Re-run with that digest." >&2
				unresolved=$((unresolved + 1))
				plan_result=refuse
				return 0
			fi
			if [ "$c_expected" != "$diff_digest" ]; then
				echo "✖ $c_path: the diff is not the one you reviewed" >&2
				echo "  expected $c_rel=$c_expected, this machine is $c_rel=$diff_digest" >&2
				unresolved=$((unresolved + 1))
				plan_result=refuse
				return 0
			fi
			declared_merge=1
		fi
		echo "→ declared   $c_path: $c_declared (--resolve $c_rel=$c_declared)"
		c_answer="$c_declared"
	elif [ "$non_interactive" -eq 1 ] || [ ! -t 0 ]; then
		echo "✖ $c_path: a real path is in the way, nothing was declared for it and there is no TTY to ask — refusing" >&2
		echo "  re-run from a terminal, or declare the decision:" >&2
		echo "    --resolve $c_rel=overwrite" >&2
		echo "    --resolve $c_rel=merge --expect-diff $c_rel=$diff_digest" >&2
		unresolved=$((unresolved + 1))
		plan_result=refuse
		return 0
	else
		if [ "$c_rel" = fish ]; then
			printf 'Resolve %s — [o]verwrite (repo wins) / [m]erge (machine wins per file) / [r]efuse: ' "$c_path"
		else
			printf 'Resolve %s — [o]verwrite (repo wins) / [r]efuse: ' "$c_path"
		fi
		read -r c_answer || c_answer=refuse
	fi

	case "$c_answer" in
	o | O | overwrite)
		plan_result=overwrite
		slot_result=1
		;;
	m | M | merge)
		if [ "$c_rel" != fish ]; then
			echo "✖ $c_path: merge is only defined for fish — the machine's git tree" >&2
			echo "  would bring its whole .git into this repo. Use overwrite or refuse." >&2
			unresolved=$((unresolved + 1))
			plan_result=refuse
			return 0
		fi
		if [ ! -d "$c_path" ] || [ ! -d "$c_target" ]; then
			echo "✖ $c_path: merge needs two directories — $c_path and $c_target" >&2
			unresolved=$((unresolved + 1))
			plan_result=refuse
			return 0
		fi
		plan_result=merge
		slot_result=1
		;;
	*)
		if [ -n "$c_declared" ]; then
			echo "✖ $c_path: refused as declared, nothing will change" >&2
		else
			echo "✖ $c_path: refused, nothing will change" >&2
		fi
		unresolved=$((unresolved + 1))
		plan_result=refuse
		;;
	esac
}

# classify_stub — the ghostty include. Never asks: it is install's own output,
# and any file already there is backed up rather than overwritten in place.
classify_stub() {
	s_path="$config_home/ghostty/config.ghostty"
	s_line="config-file = $repo/ghostty/config.ghostty"
	plan_result=''
	slot_result=0

	if [ -f "$s_path" ] && [ ! -L "$s_path" ] && [ "$(cat -- "$s_path")" = "$s_line" ]; then
		echo "✓ ok         $s_path (already includes this clone)"
		plan_result=ok
		return 0
	fi
	if [ -e "$s_path" ] || [ -L "$s_path" ]; then
		echo "→ rewrite    $s_path holds something else"
		plan_result=rewrite
		slot_result=1
		return 0
	fi
	echo "→ write      $s_path (nothing there)"
	plan_result=write
}

echo "consus install"
echo "  repo:        $repo"
echo "  config home: $config_home"
echo "  backups:     $backup_dir (created only if something is displaced)"
[ -z "$resolutions" ] || echo "  resolutions:$resolutions"
[ -z "$expectations" ] || echo "  expect-diff:$expectations"
echo
echo "plan:"

classify fish; plan_fish="$plan_result"; slot_fish="$slot_result"
classify_stub; plan_stub="$plan_result"; slot_stub="$slot_result"
classify git; plan_git="$plan_result"; slot_git="$slot_result"

# ---------------------------------------------------------------------------
# Validate. Nothing has moved yet, and nothing will unless the whole plan is
# executable — including every backup slot, since a slot is never reused.
# ---------------------------------------------------------------------------
check_slot() {
	if [ "$1" -eq 1 ]; then
		v_dest="$backup_dir/$2"
		if [ -e "$v_dest" ] || [ -L "$v_dest" ]; then
			echo "✖ $2: backup slot $v_dest is already occupied — a slot is never written into twice" >&2
			unresolved=$((unresolved + 1))
		fi
	fi
}
check_slot "$slot_fish" fish
check_slot "$slot_stub" ghostty/config.ghostty
check_slot "$slot_git" git

# Nothing has moved yet, so this is the last place a run can refuse cleanly.
# The apply phase cannot recover from an unwritable backup directory: it would
# fail after earlier paths were already linked, which is the half-linked
# machine the refusal above promises is impossible.
if [ "$unresolved" -eq 0 ] && [ $((slot_fish + slot_stub + slot_git)) -ne 0 ]; then
	if ! mkdir -p -- "$backup_dir" 2>/dev/null || [ ! -w "$backup_dir" ]; then
		echo "✖ backup directory $backup_dir cannot be created or written to" >&2
		unresolved=$((unresolved + 1))
	fi
fi

if [ "$unresolved" -ne 0 ]; then
	echo >&2
	echo "✖ install: $unresolved path(s) unresolved — nothing was changed." >&2
	echo "  The run is all-or-nothing on purpose: a partly linked machine is worse" >&2
	echo "  than an untouched one." >&2
	exit 1
fi

# ---------------------------------------------------------------------------
# Apply. Every decision is settled, so from here on there are no questions.
# ---------------------------------------------------------------------------
echo
echo "apply:"

# ~/.config is mode 700 while ~/Developer/LRNZ09 is 755, and a fresh clone
# materialises 644 files. Do it here or it gets forgotten.
chmod 700 "$repo"

move_aside() {
	m_dest="$backup_dir/$1"
	mkdir -p -- "$(dirname -- "$m_dest")"
	mv -- "$2" "$m_dest"
	echo "  moved $2 -> $m_dest"
}

apply_path() {
	p_rel="$1"
	p_plan="$2"
	p_target="$repo/$1"
	p_path="$config_home/$1"

	case "$p_plan" in
	ok) ;;
	link)
		mkdir -p -- "$(dirname -- "$p_path")"
		ln -s -- "$p_target" "$p_path"
		echo "✓ linked     $p_path -> $p_target"
		;;
	relink)
		move_aside "$p_rel" "$p_path"
		ln -s -- "$p_target" "$p_path"
		echo "✓ linked     $p_path -> $p_target"
		;;
	overwrite)
		move_aside "$p_rel" "$p_path"
		ln -s -- "$p_target" "$p_path"
		echo "✓ linked     $p_path -> $p_target (the repo's content wins)"
		;;
	merge)
		move_aside "$p_rel" "$p_path"
		# The machine's tree wins per file: files the repo lacks arrive, and
		# files that differ land as unstaged modifications, so `git status`
		# becomes the review queue. Ignored files come too — fish_variables is
		# runtime state, and dropping it would discard every `set -U`.
		cp -R -- "$backup_dir/$p_rel/." "$p_target/"
		ln -s -- "$p_target" "$p_path"
		echo "✓ merged     the machine's $p_rel into $p_target, then linked $p_path"
		;;
	*)
		echo "✖ apply_path: unreachable plan '$p_plan' for $p_rel" >&2
		exit 1
		;;
	esac
}

apply_path fish "$plan_fish"

s_path="$config_home/ghostty/config.ghostty"
s_line="config-file = $repo/ghostty/config.ghostty"
case "$plan_stub" in
ok) ;;
rewrite | write)
	[ "$plan_stub" = write ] || move_aside ghostty/config.ghostty "$s_path"
	mkdir -p -- "$(dirname -- "$s_path")"
	printf '%s\n' "$s_line" > "$s_path"
	echo "✓ wrote      $s_path"
	;;
esac

# git goes last, and its backup-move and link creation are adjacent with nothing
# between them: in that window there is no global git config at all. Every
# decision was settled in the plan phase, so nothing can interrupt it here.
apply_path git "$plan_git"

# lefthook resolves its config from the CWD, so a bare call from another repo
# would create a lefthook.yml there and report success for this one. Measured.
if ( cd -- "$repo" && lefthook install >/dev/null 2>&1 ); then
	echo "✓ lefthook   hooks installed in $repo"
else
	echo "✖ lefthook install failed in $repo" >&2
	echo "  the links are in place; run 'lefthook install' there by hand" >&2
	exit 1
fi

echo
if [ "$declared_merge" -eq 1 ]; then
	echo "· a declared merge put the machine's content in this repo's working tree."
	echo "  Work the queue before committing: git -C $repo status"
fi
echo "✓ install complete. Verify with: $repo/bin/doctor"
```

The parts that are load-bearing rather than stylistic:

- **The run is all-or-nothing.** Every path is classified and every decision
  settled in the plan phase; the validate phase then refuses the whole run if
  any path is unresolved or any backup slot is occupied. A half-linked machine
  is worse than an untouched one, and under the old shape a typo'd
  `--resolve` refused `fish` and then still overwrote `git`.
- **`git` is applied last, and its backup-move and link creation are adjacent.**
  In the window between them there is no global git config at all. Because every
  prompt happens in the plan phase, nothing can interrupt that window.
- **A wrong link is relinked with no decision, even under
  `--non-interactive`.** Moving a link never touches its target, so no machine
  content is at risk — which is what lets a relocated clone self-heal from an
  automated run.
- **Merge is "back up, then copy the machine's tree over the repo's".** Files
  the repo lacks arrive; files that differ land as unstaged modifications, so
  `git status` becomes the review queue and `git restore` / `git commit` are the
  two answers. Ignored files are copied too: `fish_variables` is runtime state,
  and dropping it would discard every `set -U`, including fisher's own
  bookkeeping.
- **A declared merge requires `--expect-diff`.** Merge is the only action that
  writes machine content into the repo, and the digest ties that write to a diff
  somebody read. It also means a provisioner cannot carry a durable "always
  merge" instruction: the digest goes stale the moment the machine drifts, and a
  stale digest refuses.
- **The digest covers content, not just file names.** A `differ:` line reads the
  same whatever the file now holds, so a name-only digest would go stale when a
  new file appeared but *not* when an already-differing file was edited again —
  which is the most common kind of drift, and would have made the guarantee
  above false. Each `differ:` line is therefore followed by the two content
  hashes, and the digest is taken over the listing that was printed.
- **merge is only defined for fish**, rejected at parse time for `--resolve` and
  again at the decision point for a typed answer, and the prompt does not offer
  it for the git path. The merge copy is `cp -R "$backup_dir/$rel/."`, which for
  the git path would drag the old checkout's whole `.git` into this repo as a
  nested repository `git status` never reports.
- **A missing record refuses.** Without that guard a missing `$repo/git` would
  send the live global config to the backup and leave a dangling link in its
  place, with git silently unconfigured and only `bin/doctor` any the wiser.
- **An unreadable machine path refuses** rather than printing a partial diff and
  a digest that commits to it.
- **The validate phase proves the backup directory is usable**, because an
  unwritable one would otherwise fail mid-apply, after earlier paths were
  already linked — the half-linked machine the refusal claims is impossible.
- **`chmod 700 "$repo"` has no `--`.** macOS `chmod` rejects the separator.
- **`lefthook install` runs in a subshell that cds to the repo.** Measured: a
  bare call resolves its config from the caller's CWD, so from an unrelated git
  repo it creates a `lefthook.yml` *there*, installs hooks *there*, exits 0, and
  then this script prints a success line naming the consus clone. Outside a repo
  it exits 128, which with `set -eu` and `>/dev/null` would kill the script
  silently after the links were already made.

- [ ] **Step 5: Make it executable on disk, then run the suite green**

```sh
. ~/Backups/consus-migration.env
chmod +x bin/install
SP="$SP" REPO="$CLONE" sh "$SP/work/tests-install.sh"
```

Expected last line: `115 passed, 0 failed`.

`chmod` first, then `git add` — never `git add --chmod=+x`, which records
`100755` in the index while leaving the file at `644` on disk, so the very next
`./bin/install` dies with exit 126.

- [ ] **Step 6: Commit**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
git add bin/install
git ls-files -s bin/install | grep -q '^100755'
git commit -m "Add bin/install"
test -z "$(git status --porcelain)"
```

---

### Task 9: Phase 1 — `bin/doctor`, the read-only probe

Link integrity is the one invariant git cannot express: the repo can be pristine
while `~/.config` points somewhere else, and for git and fish a severed link is
completely silent. That is what makes this script load-bearing rather than a
convenience — and what makes it the probe half of `fides`' probe/apply pattern.

**Files:**

- Create: `bin/doctor`
- Create (scratch, **not committed**): `$SP/work/tests-doctor.sh`

**Interfaces:**

- Consumes: `fish/fish_plugins` and its pins (Task 7), `ghostty/config.ghostty`
  (Task 7), the layout `bin/install` produces (Task 8).
- Produces: `bin/doctor`, exiting 0 when the machine matches the record and 1
  when it does not, touching nothing either way. Task 11's gate requires it to
  exit **1** — specifically failing its link check, not 126 from a missing
  executable bit. Task 14 requires it to exit 0.

- [ ] **Step 1: Write the doctor suite**

To `$SP/work/tests-doctor.sh`, alongside the fixture builder Task 8 wrote. It
builds the links by hand rather than calling `bin/install`, so a failure here is
a doctor failure and nothing else.

```sh
#!/bin/sh
# Exercises bin/doctor against the sandbox fixture. The links are made by hand
# here, so this suite does not depend on bin/install.
set -u
SP="${SP:?set SP to the scratch directory}"; SB="$SP/sb"
pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1"; fi; }

SB="$SB" REPO="${REPO:?set REPO to the consus clone}" sh "$SP/work/mkfixture.sh" >/dev/null 2>&1 || { echo "fixture build failed"; exit 1; }
cd "$SB/repo" || exit 1

check "doctor exists and parses under sh"  'sh -n bin/doctor'

# A machine that has not been installed yet.
rc=0; XDG_CONFIG_HOME="$SB/xdg" ./bin/doctor >"$SB/d0.log" 2>&1 || rc=$?
check "fails before install, rc 1"         '[ "$rc" -eq 1 ]'
check "  names the missing git link"       'grep -q "xdg/git is not a symlink" "$SB/d0.log"'
check "  names the missing stub"           'grep -q "config.ghostty is missing" "$SB/d0.log"'

# Hand-build the installed state: two links, one stub, one hidden hand-written
# file that the allow-list keeps out of git status.
rm -rf "$SB/xdg/fish" "$SB/xdg/git"
ln -s "$SB/repo/fish" "$SB/xdg/fish"
ln -s "$SB/repo/git" "$SB/xdg/git"
mkdir -p "$SB/xdg/ghostty"
printf 'config-file = %s\n' "$SB/repo/ghostty/config.ghostty" > "$SB/xdg/ghostty/config.ghostty"
printf 'function drifted\nend\n' > fish/functions/drifted.fish

rc=0; XDG_CONFIG_HOME="$SB/xdg" ./bin/doctor >"$SB/d1.log" 2>&1 || rc=$?
check "passes once installed, rc 0"        '[ "$rc" -eq 0 ]'
check "  reports both links"               '[ "$(grep -c "✓ link" "$SB/d1.log")" -eq 2 ]'
check "  reports the stub"                 'grep -q "✓ stub" "$SB/d1.log"'
check "  ran ghostty +validate-config"     'grep -q "+validate-config exits 0" "$SB/d1.log"'
check "  every declared plugin installed"  'grep -q "every plugin in fish/fish_plugins is installed" "$SB/d1.log"'
check "  finds the hidden hand-written file" 'grep -q "functions/drifted.fish" "$SB/d1.log"'
check "  and only it"                      'grep -q "1 unclassified" "$SB/d1.log"'
check "  git status still shows nothing"   '[ -z "$(git status --porcelain fish/functions/drifted.fish)" ]'

# The pin the declaration carries is not in fisher's installed record. Stripping
# it on both sides is what keeps this from being a permanent false positive.
check "declaration is pinned"              'grep -qx "jhillyerd/plugin-git@v0.4" fish/fish_plugins'
check "  a pinned declaration still passes" 'XDG_CONFIG_HOME="$SB/xdg" ./bin/doctor 2>&1 | grep -q "every plugin in fish/fish_plugins is installed"'

# A wrong link is named, not merely a missing one.
unlink "$SB/xdg/fish"; ln -s /tmp/nowhere-consus "$SB/xdg/fish"
rc=0; XDG_CONFIG_HOME="$SB/xdg" ./bin/doctor >"$SB/d2.log" 2>&1 || rc=$?
check "a wrong link fails, rc 1"           '[ "$rc" -eq 1 ]'
check "  prints the actual target"         'grep -q "nowhere-consus" "$SB/d2.log"'

# The severed-link case must not plant a directory: fish creates
# $XDG_CONFIG_HOME/fish when it is missing, and a read-only probe must not.
unlink "$SB/xdg/fish"
rc=0; XDG_CONFIG_HOME="$SB/xdg" ./bin/doctor >"$SB/d3.log" 2>&1 || rc=$?
check "a severed link fails, rc 1"         '[ "$rc" -eq 1 ]'
check "  did not create xdg/fish"          '[ ! -e "$SB/xdg/fish" ]'
check "  says it skipped the fish checks"  'grep -q "skipped —" "$SB/d3.log"'
ln -s "$SB/repo/fish" "$SB/xdg/fish"

# A stub that names a different clone is a finding, not a pass.
printf 'config-file = %s\n' "/somewhere/else/ghostty/config.ghostty" > "$SB/xdg/ghostty/config.ghostty"
rc=0; XDG_CONFIG_HOME="$SB/xdg" ./bin/doctor >"$SB/d4.log" 2>&1 || rc=$?
check "a foreign stub fails, rc 1"         '[ "$rc" -eq 1 ]'
check "  quotes the line it wanted"        'grep -q "config-file = $SB/repo/ghostty/config.ghostty" "$SB/d4.log"'

# --- the advisory review-queue report -----------------------------------
# put the stub back first, or the previous check's foreign stub is what fails
printf "config-file = %s\\n" "$SB/repo/ghostty/config.ghostty" > "$SB/xdg/ghostty/config.ghostty"
printf "\n# dirtied by the test\n" >> fish/config.fish
XDG_CONFIG_HOME="$SB/xdg" ./bin/doctor >"$SB/d5.log" 2>&1
d5_rc=$?
check "a dirty tree does not fail doctor"  '[ "$d5_rc" -eq 0 ]'
check "  but is reported as the queue"     'grep -q "uncommitted changes" "$SB/d5.log" && grep -q "M fish/config.fish" "$SB/d5.log"'
git restore fish/config.fish
XDG_CONFIG_HOME="$SB/xdg" ./bin/doctor >"$SB/d6.log" 2>&1
check "a clean tree is reported clean"     'grep -q "clean — the committed record" "$SB/d6.log"'

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it and watch it fail**

```sh
. ~/Backups/consus-migration.env
SP="$SP" REPO="$CLONE" sh "$SP/work/tests-doctor.sh"
```

Expected: `FAIL  doctor exists and parses under sh`, and the rest failing behind
it.

- [ ] **Step 3: Write `bin/doctor`**

```sh
#!/bin/sh
# consus/bin/doctor — read-only. Exits 0 when this machine matches the record,
# non-zero when it does not, and touches nothing either way.
#
# Link integrity is the one invariant git cannot express: the repo can be
# pristine while $XDG_CONFIG_HOME points somewhere else, and for git and fish a
# severed link is completely silent. That is what makes this script load-bearing
# rather than a convenience. See the design document under docs/superpowers/.
set -eu

unset CDPATH
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
fish_dir="$repo/fish"
failed=0
fish_link_ok=0

present=$(mktemp); classified=$(mktemp); unclassified=$(mktemp)
trap 'rm -f "$present" "$classified" "$unclassified"' EXIT

echo "consus doctor"
echo "  repo:        $repo"
echo "  config home: $config_home"
echo

# --- the two links ----------------------------------------------------------
# check_link <rel> — returns non-zero when the link is missing or wrong.
check_link() {
	c_target="$repo/$1"
	c_path="$config_home/$1"
	if [ ! -L "$c_path" ]; then
		echo "✖ $c_path is not a symlink (expected -> $c_target)" >&2
		return 1
	fi
	c_current=$(readlink -- "$c_path")
	if [ "$c_current" != "$c_target" ]; then
		echo "✖ $c_path -> $c_current (expected -> $c_target)" >&2
		return 1
	fi
	echo "✓ link       $c_path -> $c_target"
}

check_link git || failed=1
if check_link fish; then fish_link_ok=1; else failed=1; fi

# --- the ghostty include ----------------------------------------------------
# The stub assertion is not redundant: +validate-config exits 1 when the stub
# names a missing target, but 0 when the stub is absent altogether — ghostty
# falls back to Application Support and reports success.
stub="$config_home/ghostty/config.ghostty"
want="config-file = $repo/ghostty/config.ghostty"
if [ ! -f "$stub" ]; then
	echo "✖ $stub is missing — ghostty falls back to Application Support in silence" >&2
	failed=1
elif [ "$(cat -- "$stub")" != "$want" ]; then
	echo "✖ $stub does not name this clone; expected exactly:" >&2
	echo "    $want" >&2
	failed=1
else
	echo "✓ stub       $stub"
	if command -v ghostty >/dev/null 2>&1; then
		if ghostty +validate-config >/dev/null 2>&1; then
			echo "✓ ghostty    +validate-config exits 0"
		else
			echo "✖ ghostty +validate-config failed — run it directly for the reason" >&2
			failed=1
		fi
	else
		echo "· ghostty    not installed — skipped +validate-config"
	fi
fi

# --- fish: the declaration, then the unclassified report ---------------------
# Gated on the link, and not merely for tidiness: fish CREATES
# $XDG_CONFIG_HOME/fish when it is missing, so querying fisher through a severed
# link would plant a real directory where the link belongs — turning install's
# silent relink into a prompt on the next run. Measured.
if [ "$fish_link_ok" -eq 0 ]; then
	echo "· fish       skipped — $config_home/fish is not the expected link, and"
	echo "·            starting fish would create a real directory there."
elif ! command -v fish >/dev/null 2>&1; then
	echo "· fish       not installed — skipped the plugin checks"
else
	# `fish -c` is safe here: measured, reading a universal variable leaves
	# fish_variables untouched. conf.d noise goes to stderr, hence 2>/dev/null.
	installed=$(fish -c 'string join \n -- $_fisher_plugins' 2>/dev/null || true)
	if [ -z "$installed" ]; then
		echo "· fisher     never ran here (_fisher_plugins is unset) — skipped the plugin"
		echo "·            checks. A fresh clone has fish_plugins and no fisher, because"
		echo "·            fisher's own files are among the ignored ones. Bootstrap it:"
		echo "·              curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source"
		echo "·              fisher install jorgebucaran/fisher"
		echo "·              fisher update"
	else
		# Declared-but-not-installed. Pins are stripped from both sides: the
		# declaration carries pins the installed record does not, and this check
		# is about a plugin being present, not about which tag it came from.
		missing=0
		while IFS= read -r declared; do
			[ -n "$declared" ] || continue
			if ! printf '%s\n' "$installed" | sed 's|@.*||' | grep -qxF "${declared%%@*}"; then
				echo "✖ declared but not installed: $declared" >&2
				missing=$((missing + 1))
			fi
		done < "$fish_dir/fish_plugins"
		if [ "$missing" -ne 0 ]; then
			echo "✖ declared but not installed: $missing — run: fisher update (needs network)" >&2
			failed=1
		else
			echo "✓ plugins    every plugin in fish/fish_plugins is installed"
		fi

		# Unclassified entries. The allow-list hides a new hand-written file from
		# `git status` entirely — measured, not even as untracked — so this
		# report is the only way it becomes visible. Advisory: never fails.
		( cd -- "$fish_dir" && find . -name .git -prune -o ! -type d -print ) |
			sed 's|^\./||' | sort > "$present"
		{
			git -C "$repo" ls-files fish | sed 's|^fish/||'
			# Fisher records its paths with a literal ~/.config/fish/ prefix, so
			# strip that (and the real forms) or nothing ever matches.
			fish -c 'for v in (set --names | string match "_fisher_*_files"); string join \n -- $$v; end' 2>/dev/null |
				sed "s|^~/\\.config/fish/||; s|^$HOME/\\.config/fish/||; s|^$fish_dir/||"
			printf '%s\n' \
				completions/copilot.fish \
				completions/pipx.fish \
				completions/proto.fish \
				conf.d/fish_frozen_key_bindings.fish \
				conf.d/fish_frozen_theme.fish \
				fish_variables
			# OrbStack's completions are symlinks into /Applications/OrbStack.app.
			# Matched by target rather than by name, so a fourth one does not
			# report as unclassified forever.
			while IFS= read -r entry; do
				if [ -L "$fish_dir/$entry" ]; then
					case "$(readlink -- "$fish_dir/$entry")" in
					*OrbStack.app*) printf '%s\n' "$entry" ;;
					esac
				fi
			done < "$present"
		} | sort -u > "$classified"

		comm -23 "$present" "$classified" > "$unclassified"
		count=$(wc -l < "$unclassified" | tr -d ' ')
		if [ "$count" -eq 0 ]; then
			echo "✓ fish       every entry under fish/ is accounted for"
		else
			echo "· fish       $count unclassified under fish/ — hand-written and hidden by"
			echo "·            the allow-list, or output from a tool nobody classified:"
			sed 's|^|·              |' "$unclassified"
			echo "·            Add a .gitignore negation for anything that belongs in the"
			echo "·            record. Advisory — this never fails the run."
		fi
	fi
fi


# --- the review queue -------------------------------------------------------
# Advisory, like the unclassified report, and deliberately not a failure. The
# tools read the working tree, so the machine and the working tree agree by
# construction; what a dirty tree means is that the *committed* record has not
# caught up, and the design wants that difference visible in `git status` rather
# than hidden. It is reported here so an unattended log carries it, and the
# migration tasks gate on it themselves before pushing.
queue=$(git -C "$repo" status --porcelain 2>/dev/null || true)
if [ -n "$queue" ]; then
	echo "· tree       uncommitted changes — the review queue:"
	printf '%s\n' "$queue" | sed 's|^|·              |'
	echo "·            git restore <path> if the record was right, git commit if the"
	echo "·            machine was. Advisory — this never fails the run."
else
	echo "✓ tree       clean — the committed record matches this machine"
fi

echo
if [ "$failed" -ne 0 ]; then
	echo "✖ doctor: findings above" >&2
	exit 1
fi
echo "✓ doctor: this machine matches the record"
```

Five things here are not obvious, and three of them are corrections to the
design document's prose:

- **The stub assertion is not redundant.** `ghostty +validate-config` exits 1
  when the stub names a missing target, but **0** when the stub is absent
  altogether — ghostty falls back to Application Support and reports success. So
  ghostty self-reports a broken include and stays silent about no include at
  all.
- **The fish checks are gated on the link.** Measured: fish *creates*
  `$XDG_CONFIG_HOME/fish` when it is missing. Querying fisher through a severed
  link would plant a real directory where the link belongs, which turns
  install's silent relink into a prompt on the next run — a read-only probe
  cannot do that.
- **Pins are stripped from both sides of the declared-vs-installed check.** The
  declaration carries `@v0.4`; fisher's record does not until `fisher update`
  runs. Comparing literally reports "declared but not installed: 1" forever.
- **OrbStack's completions are matched by symlink target, not by name.** The
  spec names the three files; matching `*OrbStack.app*` classifies a fourth one
  the same way instead of reporting it as unclassified forever. The arithmetic
  still closes at three today.
- **Fisher stores its paths with a literal `~/.config/fish/` prefix**, so doctor
  strips that prefix (and the two real-path forms) before comparing against the
  directory it is actually enumerating. Without it nothing ever matches and all
  97 entries report as unclassified.

Two reports are advisory and never fail the run. The unclassified-files report
exists because a new hand-written `functions/newthing.fish` produces **no
`git status` output at all** — measured, not even as untracked. The review-queue
report exists because an unattended merge can leave machine content in the
working tree, and a log that does not mention it reads as clean; it does not
fail, because the tools read the working tree, so a dirty tree means the
*committed* record has not caught up, not that the machine is broken. The
migration tasks gate on it themselves. By contrast the
declared-but-not-installed check **does** fail: without it there is no probe for
a correct clone with correct links, green links, and not one of the 82 plugin
files on disk.

- [ ] **Step 4: Make it executable, then run both suites green**

```sh
. ~/Backups/consus-migration.env
chmod +x bin/doctor
SP="$SP" REPO="$CLONE" sh "$SP/work/tests-doctor.sh"    # 24 passed, 0 failed
SP="$SP" REPO="$CLONE" sh "$SP/work/tests-install.sh"   # 115 passed, 0 failed
```

- [ ] **Step 5: Confirm doctor is read-only against the real machine**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
rc=0; ./bin/doctor >/dev/null 2>&1 || rc=$?
test "$rc" -eq 1
test ! -e ~/.config/ghostty
test -d ~/.config/fish && test ! -L ~/.config/fish
```

This is exactly the state Task 11's gate asserts: doctor fails its link check
with rc 1, and touches nothing while doing it — in particular it does not create
`~/.config/ghostty`, and it does not let fish create `~/.config/fish`.

- [ ] **Step 6: Commit**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
git add bin/doctor
git ls-files -s bin/doctor | grep -q '^100755'
git commit -m "Add bin/doctor"
test -z "$(git status --porcelain)"
```

---

### Task 10: Phase 2 — rehearse the merge path against real drift

Required, not optional. The merge path is the one piece of this design that no
measurement in the design document covers, and its conflict rule only matters
when there is a conflict — so it has to be exercised against drift that is real
rather than imagined. It happens on this machine, but against a redirected
`XDG_CONFIG_HOME`, so no real path is touched.

The rehearsal runs in two passes, and the second one quotes back a digest the
first one printed. That is the unattended substitute for a human reading a diff
and then answering a prompt: the decision still cannot be made without the diff,
because a digest that no longer matches refuses.

**Files:**

- Create (scratch, **not committed**): `$SP/work/rehearse.sh`
- Create: `~/Backups/consus-rehearsal-<timestamp>/{xdg,xdg2,backup}` and its logs
- Temporarily modify: `fish/config.fish`, `fish/fish_plugins`,
  `fish/functions/drifted.fish` in the clone — all restored by the script's last
  step

**Interfaces:**

- Consumes: `bin/install` and `bin/doctor` from Tasks 8–9.
- Produces: a clean tree, and the confidence Task 11's gate is signing off on.
  The gate requires a clean tree, so the restore at the end is not optional.

- [ ] **Step 1: Write the rehearsal script**

To `$SP/work/rehearse.sh`. `FISH_SRC` and `GIT_SRC` default to the machine's
real trees; they exist so the script could be verified against a simulated
post-Task-1 tree while this plan was written.

```sh
. ~/Backups/consus-migration.env
#!/bin/sh
# rehearse.sh — Task 10. Rehearses bin/install against a drifted machine with
# nobody at the keyboard. Two passes — review, which prints both diffs and a
# digest of each and changes nothing, then apply, which declares the two
# resolutions and quotes back the digest of the diff the review pass printed.
# Every assertion is mechanical: an unattended run cannot eyeball a diff.
set -eu
CLONE="${CLONE:?set CLONE to the consus clone}"
RROOT="${RROOT:?set RROOT to where the rehearsal directory goes}"

cd "$CLONE"
REPO_P=$(pwd -P)
R="$RROOT/consus-rehearsal-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$R/xdg" "$R/xdg2"
echo "rehearsal: $R"

cp -R "${FISH_SRC:-$HOME/.config/fish}" "$R/xdg/fish"
cp -R "${GIT_SRC:-$HOME/.config/git}" "$R/xdg/git"

# three kinds of drift that actually happen
printf '\n# drifted by hand\n' >> "$R/xdg/fish/config.fish"
printf 'function drifted\nend\n' > "$R/xdg/fish/functions/drifted.fish"
sed -i '' 's|fish-macos@v7|fish-macos|' "$R/xdg/fish/fish_plugins"
cp -R "$R/xdg/fish" "$R/xdg2/fish"
cp -R "$R/xdg/git" "$R/xdg2/git"

p=0; f=0
check() { if eval "$2" >/dev/null 2>&1; then p=$((p+1)); echo "PASS  $1"; else f=$((f+1)); echo "FAIL  $1"; fi; }

# --- pass 1: review. Prints both diffs and their digests, changes nothing. --
rc=0
XDG_CONFIG_HOME="$R/xdg" ./bin/install --non-interactive --backup-dir "$R/backup" \
	> "$R/review.log" 2>&1 || rc=$?
check "review pass exits 1"                  '[ "$rc" -eq 1 ]'
check "  refused both paths"                 '[ "$(grep -c "nothing was declared for it" "$R/review.log")" -eq 2 ]'
check "  reported 2 unresolved"              'grep -q "2 path(s) unresolved" "$R/review.log"'
check "  fish diff: config.fish"             'grep -q "^  differ:          config.fish$" "$R/review.log"'
check "  fish diff: fish_plugins"            'grep -q "^  differ:          fish_plugins$" "$R/review.log"'
check "  fish diff hid the ignored files"    '! grep -qE "^  (differ|only[^:]*): +(fish_variables|functions/fisher\.fish)$" "$R/review.log"'
check "  git diff: .githooks/pre-commit"     'grep -qF "only on machine: .githooks/pre-commit" "$R/review.log"'
check "  git diff: .github workflow"         'grep -qF "only on machine: .github/workflows/gitleaks.yml" "$R/review.log"'
check "  git diff: .gitleaks.toml"           'grep -qF "only on machine: .gitleaks.toml" "$R/review.log"'
check "  git diff: the design document"  'grep -qF "only on machine: docs/superpowers/specs/2026-08-21-consus-migration-design.md" "$R/review.log"'
check "  git diff excluded .git/"            '! grep -qE "^  (differ|only[^:]*): +\.git/" "$R/review.log"'
check "  git diff excluded the identities"   '! grep -qE "^  (differ|only[^:]*): +config-(local|work)$" "$R/review.log"'
check "  printed a digest for fish"          'grep -qE "end of diff, digest fish=[0-9a-f]{12}" "$R/review.log"'
check "  printed a digest for git"           'grep -qE "end of diff, digest git=[0-9a-f]{12}" "$R/review.log"'
check "  created no backup directory"        '[ ! -e "$R/backup" ]'
check "  wrote no ghostty stub"              '[ ! -e "$R/xdg/ghostty/config.ghostty" ]'
check "  left fish a real directory"         '[ -d "$R/xdg/fish" ] && [ ! -L "$R/xdg/fish" ]'
check "  left git a real directory"          '[ -d "$R/xdg/git" ] && [ ! -L "$R/xdg/git" ]'

FISH_DIGEST=$(sed -n 's/^  --- end of diff, digest fish=\([0-9a-f]*\) ---$/\1/p' "$R/review.log")
check "the fish digest is recoverable"       '[ -n "$FISH_DIGEST" ]'

# --- pass 2: apply, quoting back the digest that was just reviewed --------
rc=0
XDG_CONFIG_HOME="$R/xdg" ./bin/install --non-interactive \
	--resolve fish=merge --expect-diff "fish=$FISH_DIGEST" \
	--resolve git=overwrite --backup-dir "$R/backup" \
	> "$R/apply.log" 2>&1 || rc=$?
check "apply pass exits 0"                   '[ "$rc" -eq 0 ]'
check "  the diff preceded the decision"     '[ "$(grep -n "differ:          config.fish" "$R/apply.log" | head -1 | cut -d: -f1)" -lt "$(grep -n "declared   .*fish: merge" "$R/apply.log" | head -1 | cut -d: -f1)" ]'
check "  fish links into the clone"          '[ "$(readlink "$R/xdg/fish")" = "$REPO_P/fish" ]'
check "  git links into the clone"           '[ "$(readlink "$R/xdg/git")" = "$REPO_P/git" ]'
check "  the stub names this clone"          '[ "$(cat "$R/xdg/ghostty/config.ghostty")" = "config-file = $REPO_P/ghostty/config.ghostty" ]'
check "  queue is exactly the 2 fish files"  '[ "$(git status --porcelain)" = " M fish/config.fish
 M fish/fish_plugins" ]'
check "  the machine won in config.fish"     'grep -q "drifted by hand" fish/config.fish'
check "  the machine won in fish_plugins"    'grep -qx "halostatue/fish-macos" fish/fish_plugins'
check "  the hidden file arrived"            '[ -f fish/functions/drifted.fish ]'
check "  and stays invisible to git"         '[ -z "$(git status --porcelain fish/functions/drifted.fish)" ]'
check "  backup holds the old fish tree"     '[ -f "$R/backup/fish/config.fish" ]'
check "  backup holds the old checkout"      '[ -d "$R/backup/git/.git" ]'
check "  overwrite copied nothing into git/" '[ ! -e git/.githooks ] && [ ! -e git/.gitleaks.toml ] && [ ! -e git/docs ]'
check "  warned that the merge needs review" 'grep -q "declared merge put the machine.s content" "$R/apply.log"'

# --- a stale digest must refuse, and change nothing ----------------------
rc=0
XDG_CONFIG_HOME="$R/xdg2" ./bin/install --non-interactive \
	--resolve fish=merge --expect-diff fish=000000000000 \
	--resolve git=overwrite --backup-dir "$R/backup3" \
	> "$R/stale.log" 2>&1 || rc=$?
check "a stale digest exits 1"               '[ "$rc" -eq 1 ]'
check "  named both digests"                 'grep -q "expected fish=000000000000" "$R/stale.log"'
check "  xdg2 untouched"                     '[ -d "$R/xdg2/fish" ] && [ ! -L "$R/xdg2/fish" ] && [ ! -e "$R/backup3" ]'

# --- doctor sees the file the allow-list hides -------------------------
rc=0
XDG_CONFIG_HOME="$R/xdg" ./bin/doctor > "$R/doctor.log" 2>&1 || rc=$?
check "doctor exits 0"                       '[ "$rc" -eq 0 ]'
check "  names functions/drifted.fish"       'grep -q "functions/drifted.fish" "$R/doctor.log"'
check "  and only it"                        'grep -q "1 unclassified" "$R/doctor.log"'
check "  reports the review queue too"       'grep -q "uncommitted changes" "$R/doctor.log"'

# --- convergence: the same command line is a no-op --------------------
rc=0
XDG_CONFIG_HOME="$R/xdg" ./bin/install --non-interactive \
	--resolve fish=merge --expect-diff "fish=$FISH_DIGEST" \
	--resolve git=overwrite --backup-dir "$R/backup" \
	> "$R/second.log" 2>&1 || rc=$?
check "the same command re-run exits 0"      '[ "$rc" -eq 0 ]'
check "  both links reported already right"  '[ "$(grep -c "already linked" "$R/second.log")" -eq 2 ]'
check "  both resolutions reported unneeded" '[ "$(grep -c "was not needed here" "$R/second.log")" -eq 2 ]'
check "  no new backup entries"              '[ "$(ls "$R/backup" | wc -l | tr -d " ")" -eq 2 ]'

# --- the untouched copy still refuses when nothing is declared --------
rc=0
XDG_CONFIG_HOME="$R/xdg2" ./bin/install --non-interactive --backup-dir "$R/backup2" \
	> "$R/refuse.log" 2>&1 || rc=$?
check "an undeclared run still exits 1"      '[ "$rc" -eq 1 ]'
check "  xdg2/fish is still a real dir"      '[ -d "$R/xdg2/fish" ] && [ ! -L "$R/xdg2/fish" ]'
check "  backup2 was never created"          '[ ! -e "$R/backup2" ]'

# --- put the clone back, deleting nothing ----------------------------
git restore fish/config.fish fish/fish_plugins
mv fish/functions/drifted.fish "$R/backup"/
check "the clone is clean again"             '[ -z "$(git status --porcelain)" ]'
check "  the pin is back"                    'grep -qx "halostatue/fish-macos@v7" fish/fish_plugins'
check "  drifted.fish is in the backup"      '[ -f "$R/backup/drifted.fish" ]'

echo; echo "$p passed, $f failed"; echo "logs: $R"; [ "$f" -eq 0 ]
```

- [ ] **Step 2: Run it**

```sh
. ~/Backups/consus-migration.env
mkdir -p ~/Backups
# Not piped through tee: a pipeline reports tee's status, so the script's own
# verdict — its closing [ "$f" -eq 0 ] — would be discarded.
CLONE="$CLONE" RROOT="$HOME/Backups" sh "$SP/work/rehearse.sh" \
	> "$SP/rehearse.out" 2>&1; rc=$?
cat "$SP/rehearse.out"
test "$rc" -eq 0
```

Expected last lines: `50 passed, 0 failed`, then the log directory. Every
assertion the first draft wrote as prose — "the diff must have named
`config.fish`", "doctor must name `functions/drifted.fish` and only it" — is one
of those 50.

- [ ] **Step 3: Record the rehearsal directory, and confirm the clone is clean**

```sh
. ~/Backups/consus-migration.env
printf 'R=%s\n' "$(sed -n 's/^logs: //p' "$SP/rehearse.out" | tail -1)" \
	>> ~/Backups/consus-migration.env
. ~/Backups/consus-migration.env
test -d "$R"
cd "$CLONE" && test -z "$(git status --porcelain)"
grep -qx 'halostatue/fish-macos@v7' fish/fish_plugins
```

The script restores `fish/config.fish` and `fish/fish_plugins` and moves
`fish/functions/drifted.fish` into the backup, so the clone ends clean and the
pin is back. Nothing is deleted.

---

### Task 11: Phase 2 — the gate, then push

Nothing is pushed until all of these pass. They are written as assertions rather
than observations, because two of them pass by *exiting non-zero*.

**Files:** none — this task only asserts and pushes.

**Interfaces:**

- Consumes: `BASELINE_COMMITS` from the state file, everything Tasks 4–10
  produced, and `ci_green` from Task 0.
- Produces: a pushed `main` **with an upstream**. Without `push -u`,
  `git log @{u}..` exits 128 and no caller — including `fides` and Task 14 — can
  tell whether the satellite is ahead.

- [ ] **Step 1: Run the gate**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
test -n "$BASELINE_COMMITS"

test -z "$(git status --porcelain)"                                  # clean tree
if git ls-files | grep -E 'hosts\.yml|adc\.json|keys\.txt|rclone\.conf|apps\.json|config-local$|config-work$|fish_variables|\.DS_Store|prompts/'; then
	echo "FAIL: an identity or credential path is tracked"; exit 1
fi
                                                                     # the one that matters
gitleaks git --no-banner --redact -v --config .gitleaks.toml .       # clean over full history
test "$(git rev-list --count HEAD)" -ge "$BASELINE_COMMITS"          # no history lost
test "$(git ls-files git/ | wc -l | tr -d ' ')" -eq 6                # 5 moved + git/ignore
test "$(git ls-files fish | wc -l | tr -d ' ')" -eq 6                # the allow-list held
test "$(git log --follow --oneline -- git/config | wc -l)" -gt "$(git log --oneline -- git/config | wc -l)"
                                                                     # the rename didn't orphan history
test -x bin/install && test -x bin/doctor                            # modes are on disk
sh -n bin/install && sh -n bin/doctor                                # both parse
rc=0; ./bin/doctor >/dev/null 2>&1 || rc=$?; test "$rc" -eq 1        # fails the link check, not 126
for f in README.md git/README.md docs/superpowers/specs/2026-08-21-consus-migration-design.md \
	docs/superpowers/plans/2026-08-21-consus-migration.md; do
	test -f "$f" || { echo "FAIL: $f is missing"; exit 1; }
done
markdownlint-cli2 README.md git/README.md docs/superpowers/specs/2026-08-21-consus-migration-design.md \
	docs/superpowers/plans/*.md >/dev/null
```

Every line must exit 0. `$BASELINE_COMMITS` comes from the state file rather
than from a human's notes — asserting against it rather than a literal is what
keeps this gate meaningful after this document is committed again.

The `--follow` line is self-relative on purpose: after the move, a plain
`git log -- git/config` reports 1 commit while `--follow` reports 6, and the move
registers as `rename config => git/config (100%)`. Asserting that `--follow`
sees strictly more proves the rename was detected without hardcoding either
count.

- [ ] **Step 2: Push with an upstream, and gate on CI**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
git push -u origin main
git rev-parse --abbrev-ref '@{u}' | grep -qx 'origin/main'
ci_green "$(git rev-parse HEAD)"
```

`ci_green` waits for the gitleaks run for *this* commit and returns non-zero on
any conclusion other than success. Task 12 is the first step that touches the
live `~/.config`, so this is the last point where stopping costs nothing.

---

### Task 12: Phase 3 — the one backup that matters

For everything under `~/.config` that this repo does not touch — which includes
all 32 credentials across seven stores, and every dropped tool's directory —
this archive is the only copy that exists anywhere. There is no Time Machine
destination on this machine and no restic, borg, arq, kopia, duplicati or
Backblaze installed.

**Files:**

- Create: `~/Backups/config-backup-<date>.tar.gz`

**Interfaces:**

- Consumes: nothing.
- Produces: `ARCHIVE` in the state file — the path the rollback section falls
  back to. It cannot supply `~/.gitignore`, which sits one level above the
  archive root; Task 13 handles that file separately.

- [ ] **Step 1: Archive `~/.config` whole, with no exclusions**

```sh
. ~/Backups/consus-migration.env
mkdir -p ~/Backups
chmod 700 ~/Backups
ARCHIVE=~/Backups/config-backup-$(date +%F).tar.gz
printf 'ARCHIVE=%s\n' "$ARCHIVE" >> ~/Backups/consus-migration.env
tar czf "$ARCHIVE" -C ~ .config
```

The path is computed once and recorded, not recomputed: a run that crosses
midnight would otherwise write one filename and verify a different, nonexistent
one, and `tar tzf` on a missing file reads like archive corruption.

Not `~/Desktop` and not `~/Documents`: both are iCloud-synced, and this archive
contains every credential under `~/.config` in the clear. An earlier revision of
the design excluded `gatsby/` and `raycast/` as regenerable cache; measured,
that was not a trade worth making — `~/.config` is 279 MB on disk and the
complete archive is 22 MB against roughly 7.5 MB pruned. The exclusions bought
14.5 MB and cost completeness.

- [ ] **Step 2: Verify the archive before going further**

```sh
. ~/Backups/consus-migration.env
test -s "$ARCHIVE"
tar tzf "$ARCHIVE" >/dev/null
test "$(tar tzf "$ARCHIVE" | wc -l | tr -d ' ')" -gt 1000
tar tzf "$ARCHIVE" | grep -q '^\.config/git/config$'
tar tzf "$ARCHIVE" | grep -q '^\.config/fish/fish_plugins$'
```

Measured: `~/.config/micro` is root-owned but world-readable, so the archive
needs no `sudo` and produces no partial result.

---

### Task 13: Phase 3 — activate

Nothing in this phase is deleted. Three machine-local items move to their final
home first, while `~/.config/git` is still live, and then one `bin/install` run
covers all three remaining paths.

The preflight is what makes this safe to run unattended. `git=overwrite` moves
the old checkout into the backup, so anything uncommitted there would survive
only as a backup nobody reads — the interactive flow relied on a human noticing
that in the diff. Here it is asserted instead, along with the three destinations
the moves need to be free.

**Files:**

- Create (scratch, **not committed**): `$SP/work/activate.sh`
- Move: `~/.config/git/{config-local,config-work,.remember}` → `<clone>/git/`
- Move: `~/.gitignore` → `$BK/gitignore-home`
- Displace (moved to `$BK` by install): `~/.config/git`, and the machine's
  `~/.config/fish` tree
- Create: `~/.config/{git,fish}` symlinks, `~/.config/ghostty/config.ghostty`

**Interfaces:**

- Consumes: `bin/install` (Task 8), the pushed repo (Task 11), the archive
  (Task 12).
- Produces: `BK` and `FISH_DIGEST` in the state file. `BK` is the path every
  rollback command starts from.

- [ ] **Step 1: Write the activation script**

To `$SP/work/activate.sh`. `SKIP_HOME_EXCLUDES` exists only because this script
was verified against a redirected `XDG_CONFIG_HOME` while the plan was written;
leave it unset for the real run.

```sh
. ~/Backups/consus-migration.env
#!/bin/sh
# activate.sh — Task 13. Activates this machine with nobody at the keyboard.
#
# Preflight refuses to start unless the old checkout is clean AND pushed —
# `git=overwrite` moves that checkout into the backup, so anything uncommitted
# there would survive only as a backup nobody reads. The interactive flow relied
# on a human noticing that in the diff; this asserts it instead.
#
# Then two passes: review, which prints both diffs and a digest of each and
# changes nothing, and apply, which declares the two resolutions and quotes back
# the fish digest the review pass printed. If the machine drifts between the two
# passes, the digest no longer matches and the apply pass refuses.
set -eu
CLONE="${CLONE:?set CLONE to the consus clone}"
BKROOT="${BKROOT:?set BKROOT to where the migration backup goes}"
STATE="${STATE:?set STATE to the migration state file}"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
SKIP_HOME_EXCLUDES="${SKIP_HOME_EXCLUDES:-0}"   # dry-run seam only

cd "$CLONE"
REPO_P=$(pwd -P)
p=0; f=0
check() { if eval "$2" >/dev/null 2>&1; then p=$((p+1)); echo "PASS  $1"; else f=$((f+1)); echo "FAIL  $1"; fi; }
gate()  { if eval "$2" >/dev/null 2>&1; then echo "GATE OK   $1"; else echo "GATE FAIL $1"; echo "refusing to activate — nothing was changed"; exit 1; fi; }

# --- preflight: everything that must hold before anything moves ---------
gate "the clone's tree is clean"             '[ -z "$(git status --porcelain)" ]'
gate "the clone has an upstream"             'git rev-parse --abbrev-ref @{u}'
gate "the clone is pushed"                   '[ -z "$(git log --oneline @{u}..)" ]'
gate "the old checkout is a git repo"        'git -C "$CFG/git" rev-parse --git-dir'
gate "the old checkout is clean"             '[ -z "$(git -C "$CFG/git" status --porcelain)" ]'
gate "the old checkout is pushed"            '[ -z "$(git -C "$CFG/git" log --oneline @{u}..)" ]'
gate "the identity files are where expected" '[ -f "$CFG/git/config-local" ] && [ -f "$CFG/git/config-work" ]'
gate "the repo has no git/config-local yet"   '[ ! -e "$REPO_P/git/config-local" ]'
gate "the repo has no git/config-work yet"    '[ ! -e "$REPO_P/git/config-work" ]'
gate "the repo has no git/.remember yet"     '[ ! -e "$REPO_P/git/.remember" ]'
gate "lefthook is installed"                 'command -v lefthook'
gate "gitleaks is installed"                 'command -v gitleaks'
gate "doctor fails before activation"        'rc=0; ./bin/doctor >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 1 ]'

BK="$BKROOT/consus-migration-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$BK"
printf 'BK=%s\n' "$BK" >> "$STATE"
echo "migration backup: $BK  (recorded in $STATE)"

# --- pass 1: review. Refuses, prints both diffs and digests. -----------
rc=0
XDG_CONFIG_HOME="$CFG" ./bin/install --non-interactive --backup-dir "$BK" \
	> "$BK/review.log" 2>&1 || rc=$?
check "review pass exits 1"                  '[ "$rc" -eq 1 ]'
check "  refused both paths"                 '[ "$(grep -c "nothing was declared for it" "$BK/review.log")" -eq 2 ]'
check "  diff excluded .git/"                '! grep -qE "^  (differ|only[^:]*): +\.git/" "$BK/review.log"'
check "  diff excluded the identities"       '! grep -qE "^  (differ|only[^:]*): +config-(local|work)$" "$BK/review.log"'
check "  fish still a real directory"        '[ -d "$CFG/fish" ] && [ ! -L "$CFG/fish" ]'
check "  git still a real directory"         '[ -d "$CFG/git" ] && [ ! -L "$CFG/git" ]'
check "  nothing was backed up"              '[ -z "$(ls -A "$BK" | grep -v "\.log$" || true)" ]'

FISH_DIGEST=$(sed -n 's/^  --- end of diff, digest fish=\([0-9a-f]*\) ---$/\1/p' "$BK/review.log")
gate "the fish digest is recoverable"        '[ -n "$FISH_DIGEST" ]'
printf 'FISH_DIGEST=%s\n' "$FISH_DIGEST" >> "$STATE"

# --- move the three machine-local items, then link, adjacently ---------
# From here until the link exists, git's [include] path = config-local target is
# gone, so identity and signing key are silently absent. No commits in between.
# The moved files are all ignored, so they are absent from the diff and the
# digest above is still the digest of this machine.
mv "$CFG/git/config-local" "$CFG/git/config-work" "$REPO_P/git/"
mv "$CFG/git/.remember" "$REPO_P/git/"
if [ "$SKIP_HOME_EXCLUDES" -eq 0 ]; then
	mv "$HOME/.gitignore" "$BK/gitignore-home"
fi
rc=0
XDG_CONFIG_HOME="$CFG" ./bin/install --non-interactive \
	--resolve fish=merge --expect-diff "fish=$FISH_DIGEST" \
	--resolve git=overwrite --backup-dir "$BK" \
	> "$BK/apply.log" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
	echo "GATE FAIL the apply pass refused — see $BK/apply.log"
	echo "  install itself changed nothing, but the three machine-local items are"
	echo "  already in $REPO_P/git and ~/.gitignore is in $BK. Put them back before"
	echo "  retrying, or the preflight will refuse on its own destination gates:"
	echo "    mv $REPO_P/git/config-local $REPO_P/git/config-work $CFG/git/"
	echo "    mv $REPO_P/git/.remember $CFG/git/"
	echo "    mv $BK/gitignore-home $HOME/.gitignore"
	exit 1
fi
echo "GATE OK   the apply pass linked every path"
check "  fish links into the clone"          '[ "$(readlink "$CFG/fish")" = "$REPO_P/fish" ]'
check "  git links into the clone"           '[ "$(readlink "$CFG/git")" = "$REPO_P/git" ]'
check "  the stub names this clone"          '[ "$(cat "$CFG/ghostty/config.ghostty")" = "config-file = $REPO_P/ghostty/config.ghostty" ]'
check "  the identities are in the repo"     '[ -f git/config-local ] && [ -f git/config-work ]'
check "  and stay untracked"                 '[ -z "$(git status --porcelain git/config-local git/config-work)" ]'
check "  .remember is in the repo, ignored"  '[ -d git/.remember ] && [ -z "$(git status --porcelain git/.remember)" ]'
check "  the old checkout is in the backup"  '[ -d "$BK/git/.git" ]'
check "  the old fish tree is in the backup" '[ -f "$BK/fish/config.fish" ]'
check "  overwrite copied nothing into git/" '[ ! -e git/.githooks ] && [ ! -e git/.gitleaks.toml ] && [ ! -e git/docs ]'

# --- resolve the review queue deterministically -----------------------
# The one guaranteed conflict is the pin Task 7 added, which the machine's copy
# does not carry. Anything else is a real decision: leave it in the tree, do not
# push, and stop. The machine is already fully functional — the links are live —
# so stopping here is safe.
if [ -n "$(git status --porcelain fish/fish_plugins)" ]; then
	git restore fish/fish_plugins
	echo "· restored fish/fish_plugins — the repo's pin wins"
fi
check "the pin survived the merge"           'grep -qx "jhillyerd/plugin-git@v0.4" fish/fish_plugins'
queue=$(git status --porcelain)
if [ -n "$queue" ]; then
	echo "✖ the review queue is not empty, and every entry left in it is a decision"
	echo "  somebody has to make. Nothing is pushed."
	printf '%s\n' "$queue"
	echo "  The machine is activated and working; only the push is outstanding."
	f=$((f + 1))
else
	check "the review queue is empty"        'true'
fi

rc=0; ./bin/doctor > "$BK/doctor.log" 2>&1 || rc=$?
check "doctor exits 0"                       '[ "$rc" -eq 0 ]'
check "  reports a clean tree"               'grep -q "clean — the committed record" "$BK/doctor.log"'

echo; echo "$p passed, $f failed"; echo "logs: $BK"; [ "$f" -eq 0 ]
```

- [ ] **Step 2: Run it**

```sh
. ~/Backups/consus-migration.env
CLONE="$CLONE" BKROOT="$HOME/Backups" STATE="$HOME/Backups/consus-migration.env" \
	sh "$SP/work/activate.sh" > "$SP/activate.out" 2>&1; rc=$?
cat "$SP/activate.out"
test "$rc" -eq 0
```

Expected: fifteen `GATE OK` lines, then `20 passed, 0 failed`. If a gate fails,
nothing has changed and the message names what to fix. That includes the apply
gate: if the diff drifted between the two passes the digest no longer matches,
install refuses, and the gate prints the exact commands that put the three
relocated items back before a retry. If the review queue turns out to hold
anything other than `fish/fish_plugins`, the script says so and stops without
pushing — the machine is activated and working at that point, and only the push
is outstanding. That is the one place this plan deliberately waits for a person:
the alternative is guessing which of two versions of a config file was right.

- [ ] **Step 3: Push, now that the queue is empty**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
test -z "$(git status --porcelain)"
if git log --oneline @{u}.. | grep -q .; then
	git push
	ci_green "$(git rev-parse HEAD)"
else
	echo 'nothing new to push — Task 11 already gated this commit'
fi
```

- [ ] **Step 4: Confirm the shape, and that the state file has what rollback
      needs**

```sh
. ~/Backups/consus-migration.env
test "$(readlink ~/.config/git)" = "$CLONE/git"
test "$(readlink ~/.config/fish)" = "$CLONE/fish"
test "$(cat ~/.config/ghostty/config.ghostty)" = "config-file = $CLONE/ghostty/config.ghostty"
test -f "$CLONE/git/config-local" && test -f "$CLONE/git/config-work"
test -d "$CLONE/git/.remember"
test -d "$BK/git/.git" && test -f "$BK/fish/config.fish"
test -f "$BK/gitignore-home"
test ! -e ~/.gitignore
```

Deleting `~/Library/Application Support/com.mitchellh.ghostty/config` is
**optional and not recommended** — the include already overrides it, and Ghostty
rewrites that file itself.

Optional, and not a gate: `fisher update` reconciles the `@v0.4` declaration
with what is actually installed. Doctor passes either way, because its
declared-vs-installed check compares plugin names with pins stripped.

---

### Task 14: Phase 4 — verify the machine, end to end

Run this only once Task 13 is complete and pushed, or the first two checks fail
by design.

**Files:** none — assertions only.

**Interfaces:**

- Consumes: the activated machine.
- Produces: the green state Task 15's aftercare records.

- [ ] **Step 1: The record matches the machine**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
./bin/doctor
test -z "$(git status --porcelain)"
git rev-parse --abbrev-ref '@{u}' | grep -qx 'origin/main' \
	&& test -z "$(git log --oneline @{u}..)"
```

A bare `git log @{u}..` exits 0 whether or not it prints, which is why this
compares its output instead.

- [ ] **Step 2: git reads the repo, and identity resolves through it**

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
git config --list --show-origin | grep -q "^file:$HOME/.config/git/config"
git config --show-origin --get user.signingkey | grep -q "^file:$HOME/.config/git/config-local"
git check-ignore -v --no-index .remember/x | grep -q 'git/ignore'
W=$(ls -d ~/Developer/work/*/ | head -1)
test "$(git -C "$W" config --get user.email)" \
	= "$(git config -f "$CLONE/git/config-work" --get user.email)"
```

Measured, and the reason `--show-origin` is asserted against the link path
rather than the clone path: git reports the path it was given, so the origin
reads `$HOME/.config/git/config-local`, not the resolved location.
`git config --global --list` does **not** expand includes — using it here is how
a false negative gets recorded.

- [ ] **Step 3: Signing works, which is not the same as a key resolving**

```sh
. ~/Backups/consus-migration.env
D=$(mktemp -d)
( cd "$D" && git init -q . && git commit -q --allow-empty -m t \
	&& test "$(git log -1 --pretty='%G?')" = G \
	&& echo 'personal signing ok' ) || { echo 'FAIL: personal signing'; exit 1; }

W2=$(mktemp -d ~/Developer/work/consus-verify-XXXX)
( cd "$W2" && git init -q . && git commit -q --allow-empty -m t \
	&& test "$(git log -1 --pretty='%G?')" = G \
	&& test "$(git log -1 --pretty='%GK')" \
		= "$(git config -f "$CLONE/git/config-work" --get user.signingkey)" \
	&& echo 'work signing ok' ) || { echo 'FAIL: work signing'; exit 1; }
mv "$W2" ~/Backups/
```

The `|| { echo …; exit 1; }` wrappers matter: an `&&` chain that prints nothing
on failure is indistinguishable from success to an unattended runner. The work
repo has to be *physically* inside `~/Developer/work` — a link into it never
matches the `includeIf` pattern, and says nothing about it.

- [ ] **Step 4: fish and ghostty read the repo**

```sh
. ~/Backups/consus-migration.env
test "$(fish -c 'abbr | count' 2>/dev/null)" -eq 169
test "$(fish -c 'functions | count' 2>/dev/null)" -eq 108
test "$(fish -c 'echo $__fish_config_dir' 2>/dev/null)" = "$HOME/.config/fish"
ghostty +validate-config
ghostty +show-config | grep -q 'macos-titlebar-style = tabs'
ghostty +show-config | grep -q 'window-save-state = always'
grep -qF "$CLONE/ghostty/config.ghostty" ~/.config/ghostty/config.ghostty
```

`$__fish_config_dir` resolving to the link path rather than the clone is the
point: fish reaches the repo through its own default path with nothing
configured.

- [ ] **Step 5: The link is live, and `~/.config` is still not a repo**

```sh
. ~/Backups/consus-migration.env
test "$(cd ~/.config/fish && git rev-parse --show-toplevel)" = "$CLONE"
if git -C ~/.config rev-parse --git-dir >/dev/null 2>&1; then
	echo 'FAIL: ~/.config resolved as a git repository'
	exit 1
fi
```

That last one is a feature, not a failure: `~/.config` itself is still not a
repo, so nothing that walks up from an unlinked tool's config directory finds
one.

---

### Task 15: Phase 5 — aftercare

**Files:**

- Create: `LICENSE`
- Modify: the design document — the `Status:` line and the four stale counts
- Modify: `/Users/lorenzo/.claude/memory/reference-git-signing-setup.md`
- Create: `/Users/lorenzo/.claude/memory/reference-machine-restore-checklist.md`
- Modify: `/Users/lorenzo/.claude/memory/MEMORY.md` — one pointer line

**Interfaces:**

- Consumes: a green Task 14.
- Produces: the satisfied `fides` prerequisite.

- [ ] **Step 1: Add a LICENSE**

`vesta` has one and this repo does not, which is ordinary housekeeping for a
public repo rather than a decision.

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
cp ~/Developer/LRNZ09/vesta/LICENSE .
grep -q 'MIT License' LICENSE
grep -q 'Lorenzo Pieri' LICENSE
git add LICENSE
git commit -m "Add MIT license"
```

- [ ] **Step 2: Turn the design document into a record**

Change its `Status:` line to `executed <date>`, and correct the four stale
counts that correction #14 names — they are the only other edits this step
makes, because the phases stop being instructions and become the record of what
was done to this machine:

- line 148: `tracks 14 files on purpose — 7 fish, 6 git, 1 ghostty` becomes
  `tracks 13 files on purpose — 6 fish, 6 git, 1 ghostty`
- line 616: `as written above, 7 files stage` becomes `6 files stage`, and the
  `7 files still stage` after it becomes `6 files still stage`
- line 619: `silently dropping all four tracked conf.d files` becomes
  `all three tracked conf.d files`

Leave everything else alone. The measured-facts section is why nobody
re-derives whether ghostty outranks a symlink or what `git add --chmod=+x` does,
and the README is the operational document, so there is no ambiguity about where
to look.

```sh
. ~/Backups/consus-migration.env
cd "$CLONE"
grep -q '^\*\*Status:\*\* executed' docs/superpowers/specs/2026-08-21-consus-migration-design.md
grep -q 'tracks 13 files on purpose' docs/superpowers/specs/2026-08-21-consus-migration-design.md
if grep -q '7 fish, 6 git' docs/superpowers/specs/2026-08-21-consus-migration-design.md; then echo 'FAIL: stale count'; exit 1; fi
git add docs/superpowers/specs/2026-08-21-consus-migration-design.md
git commit -m "Mark the consus design executed"
git push
ci_green "$(git rev-parse HEAD)"
```

- [ ] **Step 3: Correct the stale memory**

`/Users/lorenzo/.claude/memory/reference-git-signing-setup.md` states that the
global config is "its own version-controlled repo at `~/.config/git/` (XDG
native: no symlink, no env var, works in GUI clients too)". Under this design
`~/.config/git` **is** a symlink into `~/Developer/LRNZ09/consus`. Three edits,
not one:

- the layout sentence, which is now wrong;
- the "if the config is ever symlinked into `$HOME`" gotcha, which is now
  actively misleading — note that the relative-include hazard it describes does
  *not* apply here, because git resolves `include.path` against the directory of
  the file containing it, which through a directory link is the repo;
- any reference to the repo as `dotgit`, which is now `consus`.

The signing facts in that file — two keys, which one covers `~/Developer/work`,
the `config-local` / `config-work` split — are all still correct and stay.

```sh
M=/Users/lorenzo/.claude/memory/reference-git-signing-setup.md
test -f "$M"
grep -q 'consus' "$M"
if grep -q "no symlink" "$M"; then echo "FAIL: the stale layout claim survives"; exit 1; fi
```

- [ ] **Step 4: Create the restore checklist the plan keeps referring to**

There is no restore checklist on this machine today, so the plan creates one
rather than pointing at a file that does not exist. Write
`/Users/lorenzo/.claude/memory/reference-machine-restore-checklist.md`:

```markdown
---
name: reference-machine-restore-checklist
description: What a rebuilt machine needs that no repo restores by itself
metadata:
  type: reference
---

Things a rebuilt machine needs that nothing in [[consus]] restores on its own:

- **fisher, before anything else fish-related.** A fresh consus clone has
  `fish_plugins` and no fisher — fisher's own two files are among the ignored
  ones. The three-line bootstrap is in the consus README, it needs network, and
  `bin/doctor` reports "declared but not installed" until it has run.
- **gh** is deliberately untracked; its whole payload is
  `gh config set git_protocol https` plus the `co` alias.
- **micro**, if it is ever configured for real, needs
  `sudo chown` on `~/.config/micro` — the directory is root-owned.
- **The `includeIf` invariant:** `~/Developer/work` must be a real directory all
  the way down, with work repos physically inside it. A symlink in the pattern
  path never matches, and says nothing about it — work commits then get signed
  with the personal key.
- **GPG signing** depends on the passphrase living in the macOS keychain, which
  is what makes unattended signing work. See [[reference-git-signing-setup]].
```

Then add the pointer line to `/Users/lorenzo/.claude/memory/MEMORY.md`:

```sh
M=/Users/lorenzo/.claude/memory/reference-machine-restore-checklist.md
test -f "$M"
grep -q 'reference-machine-restore-checklist' /Users/lorenzo/.claude/memory/MEMORY.md
```

- [ ] **Step 5: Note what the open terminals will look like**

Already-running fish sessions keep the removed plugins' abbreviations and
universal variables until they are restarted. "It still looks wrong in my open
terminal" is expected, and is not a reason to roll back. A new tab is the check.

- [ ] **Step 6: Leave the backups alone, deliberately**

The migration backup under `$BK`, the rehearsal directory under `$R`, and the
sandbox under `$SP` are all redundant once Task 14 passes and the push is
confirmed, but nothing in this plan deletes them. Discard them when you want to,
however you prefer to discard things. `$ARCHIVE` is the one to keep: for every
untracked tool under `~/.config`, it is the only copy that exists.

The state file `~/Backups/consus-migration.env` is worth keeping until the
backups are gone, because the rollback section reads `BK` and `ARCHIVE` from it.

- [ ] **Step 7: Hand off to `fides`**

The prerequisite is now satisfied: a plain clone at a real path, with an
upstream, an idempotent `bin/install` that refuses without a TTY unless the
decision was declared, and a read-only `bin/doctor` probe. The `fides` spec
(`docs/superpowers/specs/2026-08-20-fides-design.md` in `LRNZ09/fides`) still
describes the superseded shape — a `consus → ~/.config` graft, satellites "cloned
to their real paths with no symlink layer", and "adding a newly-configured tool
is a gitignore line". All three were replaced. Those sections need **rewriting
against the contract in "What this repo guarantees a provisioner", not
patching**: eight bullet edits applied to an architecture section describing the
old shape would leave that document contradicting itself. That rewrite is its
own piece of work, not a step here.

One thing to carry into it: `fides` must call `bin/install --non-interactive`
with **no** `--resolve`. A satellite entry that declared a resolution would be
deciding on drift nobody looked at — and if it declared `merge`, the
`--expect-diff` digest it carried would go stale on the first drift and refuse
anyway. The refusal is the contract.

---

## If it goes wrong: rollback

Not a task — the plan's escape hatch. Before Task 13 there is nothing to roll
back that matters: `~/.config` is untouched, the clone can be deleted, and
`gh repo rename dotgit --yes` undoes the rename.

After Task 13, four paths changed — `~/.config/git`, `~/.config/fish`, the
ghostty stub and `~/.gitignore` — and rollback needs no deletion either. **The
links must be moved aside before anything is restored over them, or a restore
writes straight through them into the repo's working tree.** Moving a link moves
the link itself and never touches its target; measured.

```sh
. ~/Backups/consus-migration.env
: "${BK:?the state file has no BK — see the paragraph below}"
test -d "$BK/git" \
	&& test -d "$BK/fish" \
	&& test -f "$BK/gitignore-home" \
	|| { echo "rollback: $BK is not a complete migration backup"; exit 1; }

B=~/Backups/consus-rollback-$(date +%Y%m%dT%H%M%S); mkdir -p "$B"
mv ~/.config/git ~/.config/fish "$B"/
mv ~/.config/ghostty/config.ghostty "$B"/

mv "$BK"/git "$BK"/fish ~/.config/
mv "$BK"/gitignore-home ~/.gitignore
mv "$CLONE"/git/config-local "$CLONE"/git/config-work ~/.config/git/
mv "$CLONE"/git/.remember ~/.config/git/
git -C ~/.config/git branch --unset-upstream

test -d ~/.config/git/.git && test ! -L ~/.config/git
test -f ~/.gitignore
```

`BK` comes from the state file rather than from a note, which is the whole
reason the state file exists: this block may run days later, in a shell that
never saw Task 13. If the state file is gone too,
`BK=$(ls -d ~/Backups/consus-migration-* | tail -1)` recovers it.

`~/.gitignore` has to come back explicitly, and the tarball **cannot** supply
it: that archive is rooted at `~/.config` and this file sits one level up. The
restored `git/config` still points `core.excludesfile` at it, so skipping that
line leaves the setting dangling and stops `.remember/` being ignored anywhere —
the exposure Task 5 exists to avoid. If `$BK` has already been discarded,
recreate the file by copying `git/ignore` out of the repo.

The `--unset-upstream` line matters. The restored `~/.config/git` is a live
checkout whose remote was repointed in Task 3 and whose branch tracks a `main`
that now contains the restructure — so it reports itself behind, and a
`git pull` there would redo the migration underneath you. Unsetting the upstream
(or removing the remote outright) stops that. Making it a normal tracking clone
again means reverting the restructure commits on origin first.

If `fides` has been given a `consus` satellite entry by then, disable it before
rolling back, or its `./bin/install --non-interactive` will recreate the links
on the next run.

If the migration backup is already discarded, the tarball is the fallback for
the same paths:

```sh
. ~/Backups/consus-migration.env
tar xzf "$ARCHIVE" -C ~ .config/git .config/fish
```

## What this plan does not do

- It does not rewrite the `fides` spec. Task 15 records what needs rewriting and
  why patching it would be worse.
- It does not delete anything, ever — including the backups it creates.
- It does not change `~/.gnupg/gpg-agent.conf`. Unattended signing already works
  because the passphrase lives in the macOS keychain; raising the agent's cache
  TTLs or presetting the passphrase would weaken this machine's credential
  handling to buy something it already has. Task 0 verifies rather than
  reconfigures.
- It does not touch `~/.claude`, `~/.proto`, `~/.agents`, `~/.hammerspoon`,
  `zed/`, `raycast/` or VS Code. All of them are out of scope by design, and all
  of them are inside the Task 12 archive.
- It does not test the fresh-machine bootstrap end to end, because testing that
  means rebuilding a machine. The sequence is documented in the README, it needs
  network, and `bin/doctor` detects the state that calls for it.
