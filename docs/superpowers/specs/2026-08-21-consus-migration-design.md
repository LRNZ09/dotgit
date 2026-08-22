# consus — design and migration plan

**Date:** 2026-08-21
**Status:** design settled, not yet executed
**Supersedes:** the 2026-08-20 revision of this document, which activated each
tool through its own configuration language. Measurement retired that choice —
see "Options considered" and "Verified facts".
**Prerequisite for:** the `fides` machine record, whose `satellites` role cannot
run until `consus` exists and is pushed. That spec
(`docs/superpowers/specs/2026-08-20-fides-design.md` in `LRNZ09/fides`) still
describes a superseded layout — see "What this repo guarantees a provisioner".

## What this does

Renames `LRNZ09/dotgit` to `LRNZ09/consus` and relocates its checkout to
`~/Developer/LRNZ09/consus`, where it becomes an ordinary browsable repo in
the same directory as `vesta` and `fides`. Five of its tracked files — `config`,
both `.example` files, `README.md` and `.gitignore` — move into a `git/`
subdirectory by `git mv`; `.gitleaks.toml`, the gitleaks workflow and `docs/`
stay at the root, and `.githooks/` is removed. The repo's entire linear history
stays intact: no second repo, no `git subtree`, no synthetic merge commit and
nothing to archive afterwards. (No commit or file totals are quoted here on
purpose — they grow every time this document is committed, and Phase 2 asserts
against a baseline recorded in Phase 0 instead.) GitHub redirects the old URL,
so no clone or remote anywhere breaks.

The name follows the family convention, where the name's domain matches the
repo's function: `vesta` the hearth for the homelab interior, `janus` the
doorway for its gateway, `fides` good faith for the machine record. A consus
is the one member of that family that is not a deity but the fixture the deities
stand in — the shrine niche built into the wall of every Roman house, holding
the gods of that particular household. That is what this repo is: not the
configuration itself but the niche that holds it and puts it where each tool
already looks. Every house had one, the contents were much the same house to
house, and a family moving in installed theirs and the place became home.
Installing it twice changes nothing, which is the claim `bin/install` makes.

The repo's central property is safety by construction: no credential can enter
the working tree, nothing is ever deleted, and every move reverses.

`~/.config` never becomes a repo and holds no `.git`. Each tool finds its
configuration at its **own default path**, which is a symlink into the repo:

```text
~/.config/git   →  ~/Developer/LRNZ09/consus/git
~/.config/fish  →  ~/Developer/LRNZ09/consus/fish
```

One tool is the exception. Ghostty's winning config path on macOS is
`~/Library/Application Support/com.mitchellh.ghostty/config`, which no symlink
under `~/.config` can outrank, so ghostty gets a one-line `config-file` include
instead. Four tools are dropped outright.

## Why ~/.config never becomes a repo

The first draft of this plan grafted a repo onto `~/.config` itself. That was
rejected, and the reasoning is unchanged by this revision. Everything under
`~/.config` sits in one namespace: 1,138 files, of which 32 across seven stores
are credentials — `gh/hosts.yml`, `gcloud/legacy_credentials/*/adc.json`,
`sops/age/keys.txt`, `rclone/rclone.conf` (mode `644`),
`github-copilot/apps.json`, seven mode-`600` `acli/*_config.yaml` files and
`libvirt/secrets/` — plus 271 MB of `gatsby/` and `raycast/` cache. A worktree
there means:

- A deny-by-default `/*` allow-list is the only thing between those files and a
  commit. Measured: with the allow-list correct, `git add -A` stages the 8
  intended files. With **one character** of line 1 corrupted (`/*` typed as
  `/ *`), 17 files stage, 5 of them credentials including the age key.
- `git clean -fdx` deletes them unrecoverably and `git stash --all` removes them
  at rc=0. Neither needs `--force`.
- The `/*` rule blinds ripgrep and every gitignore-respecting agent tool inside
  the directory it is pointed at. Measured: `rg --files` sees 88 of 249 files;
  searches for `oauth_token`, `AGE-SECRET` and `gcloud` return nothing.
- `.git`, `README.md`, `lefthook.yml`, `.gitleaks.toml` and `.github/` all live
  in the XDG namespace, where every tool enumerates entries.

gitleaks is not a sufficient backstop for the first item. Tested with the
family's own `.gitleaks.toml` against realistic synthetic credentials, it caught
3 of 5 — `hosts.yml`, `apps.json` and `adc.json`. It found nothing in a
correctly-shaped age secret key or an rclone token block, and the age key is the
one that decrypts everything else.

Under the design below the repo's working tree contains no credential at all —
no linked directory holds a credential store — so a gitignore mistake can only
ever cause a *missing* file, never a leak.

## Options considered

Eight mechanisms were priced with sandboxed tests. The per-tool symlink farm won
on measurement after the 2026-08-20 revision had provisionally chosen tool-native
includes.

**Per-tool inward symlinks — chosen.** One mechanism, and zero configuration in
any tool's own language. Measured: git needs *no* stub and no `[include]` at all
through a directory link, and fish reaches exact baseline parity with no stub and
none of the five lines the include design required.

Be honest about the scope of that argument as it now stands. The mechanism
generalises to GUI apps that inherit no shell environment and to tools with no
include directive — that is a real property of links and not of includes — but
with zed out of scope, nothing currently linked needs it: git and fish are both
CLI tools, and the one GUI app left is ghostty, which is handled by an include.
So the live justification is narrower than the general one: zero configuration,
and none of the five silent failure modes below. Directory links are
structurally immune to
temp-file-plus-rename, because `rename(2)` acts on the final path component and
the kernel resolves the directory component first, so a tool's atomic write
lands inside the repo working tree where `git status` shows it as an ordinary
modification. Its one real weakness is that link integrity is an invariant git
cannot express — the repo can be pristine while `~/.config` points elsewhere —
which is why `bin/doctor` is load-bearing rather than a convenience.

**Tool-native includes — superseded, not wrong.** The 2026-08-20 revision's
choice: a two-line `[include]` for git, a five-line `source` stub for fish, a
`config-file` line for ghostty, and `OPENCODE_CONFIG*` env vars for opencode.
It works, and each mechanism
was verified end to end. It lost on three counts. It is four mechanisms with five
distinct silent failure modes: a missing include target is ignored with no way to
mark an include required; include *ordering* silently decides whether a later
`git config --global` write shadows the record or is quietly ineffective;
`git config --global --unset` of an included key returns rc=5 and cannot work;
omitting the undocumented `set -g fisher_path` line makes 169 abbreviations
disappear with no error; and env-var activation is dead for any GUI-launched
program. It could not cover its own tool set — `gh` and `micro` were dropped for
having no include. And it left the record
*shadowable*: a global write to a key the repo sets wins or loses depending on a
line's position in a file no one reads.

**Graft a repo onto `~/.config`.** The four objections above.

**Bare repo with an explicit `--work-tree`.** Closes the destruction surface
completely and unblinds ripgrep, but credentials stay in the work-tree,
`ansible.builtin.git` cannot express it (with `bare: true` it never checks out
and never reports drift), and every git integration in `~/.config` goes dark —
no prompt, no editor gutter, no `git log` where you are standing. Inward links
keep all of it: measured, `git rev-parse --show-toplevel` from inside
`~/.config/fish` names the repo.

**Copy-based, whether `chezmoi` or a hand-written `install.sh` plus
`capture.sh`.** Trades link integrity for freshness: two copies of the truth
that can diverge indefinitely, and every tool-written change becomes a manual
capture. `fisher install` is the most frequent config-mutating action on this
machine, and it writes the tracked `fish_plugins` along with its pile of ignored
artifacts — so under a copy-based scheme the record would go stale on the action
most likely to happen. chezmoi additionally puts its own config
and boltdb inside `~/.config`, is not safely automatable without a `status`
guard, and its own documentation answers this problem class with symlinks.

**Fold the config into `fides`.** The only option that leaves `~/.config`
cleaner than the status quo. It was rejected for forcing the tracked set from
117 files down to 19, for losing exact `fisher` pinning, and for destroying the
repo as a standalone clonable artifact.

Only the last of those still stands, and this revision is why. The design now
tracks 14 files on purpose — 7 fish, 6 git, 1 ghostty — because everything a
tool generated is ignored, so "it forces the tracked set down to 19" describes
this design too and cannot distinguish between them. Exact fisher pinning is
now carried by `fish_plugins` rather than by vendored files, which any repo
could hold. What remains is the standalone-clone argument its README exists
for: per-machine git identity, wanted by machines that would never clone a
personal provisioning repo.

**A linked `git worktree` at `~/.config`.** `git worktree add` refuses any
non-empty target — including a directory whose only entry is `.DS_Store`, and
`--force` does not override it — but the refusal is routable: add with
`--no-checkout` at an empty staging path, move the resulting `.git` *file* into
`~/.config`, `git worktree repair`, `git checkout -f`. So it was rejected on
cost, not feasibility, and the decisive cost is counterintuitive:
**`git worktree remove`, with no flags, on a clean worktree, exit 0, deletes
the entire directory including the ignored credential stores.** Reproduced
twice. The deny-by-default gitignore is what makes it possible — it renders
`git status` empty, so git considers the worktree disposable.

**A repo of outward-pointing symlinks** — `consus/fish` pointing at
`~/.config/fish`. Not merely worse; it versions nothing. git stores a
mode-120000 blob whose entire content is the target path string: the whole
`fish` tree behind one link produced 5 blobs and zero tracked configuration.
`git add fish/config.fish` is refused outright (`fatal: pathspec ... is beyond a
symbolic link`), no configuration makes git follow the link, edits to the target
are permanently invisible to `git status`, and a clone on another machine
materialises dangling links while reporting the tree clean. Note that this is the
exact opposite of the chosen design's link direction, and the two must not be
confused.

## Per-tool activation

Measured against git 2.55.0, fish 4.8.0, ghostty 1.3.1 and gh 2.96.0.

| Tool | Default path | Mechanism | Liveness signal |
| --- | --- | --- | --- |
| `git` | `~/.config/git` | directory link | `bin/doctor` `readlink` only |
| `fish` | `~/.config/fish` | directory link | `bin/doctor` `readlink` only |
| `ghostty` | App Support; stub in `~/.config/ghostty` | 1-line `config-file` include | `ghostty +validate-config` exits 1 |
| `zed` | — | **dropped** | settings-sync extensions are in flight |
| `opencode` | — | **dropped** | no binary installed anywhere |
| `gh` | — | **dropped** | 2-line payload; file link viable but not worth it |
| `micro` | — | **dropped** | payload is literally `{}` |

### git — a directory link and nothing else

No stub, no `[include]` line, no configuration of any kind. `~/.config/git`
becomes a link to `consus/git` and git reads `consus/git/config` as the
global config file, because that is what the path resolves to.

Three properties follow, all measured:

- **The relative includes keep working.** `[include] path = config-local`
  resolves against the directory of the file containing it, which through the
  link is the repo. `git config --list --show-origin` reports
  `file:~/.config/git/config-local user.email=…` — the link path, not the
  resolved path.
- **`includeIf "gitdir:~/Developer/work/"` is carried and matches correctly.**
  A work repo returns the work identity and a personal repo the personal one.
  Linking the *config directory* has no effect on gitdir resolution.
- **Tool writes become visible instead of silent.** `git config --global`,
  `gh auth setup-git` and `git-credential-manager configure` all write into the
  **tracked** `git/config`, which then shows up as a worktree modification.
  The include
  design's ordering dilemma disappears with the second file: there is no longer
  a shadowing question, because there is only one global config. A machine that
  has drifted from the record now says so in `git status`.

`--unset` also improves. `git config --global --unset` of a key in the tracked
file returns rc=0 and works; only keys living in `config-local`/`config-work`
still return rc=5, and those are the two files nothing should be unsetting
programmatically.

The machine-local identity files live **inside the repo** at
`consus/git/config-local` and `config-work`, untracked. `dotgit`'s own
`.gitignore` already lists `config-local` and `config-work` with unanchored
patterns, so it keeps working verbatim once it becomes `git/.gitignore`, and the
`.gitleaks.toml` email rule blocks either from being committed.

**The `includeIf` gap, stated correctly.** The 2026-08-20 revision recorded that
"a symlinked ancestor breaks the match silently". That is imprecise, and the
precise form matters because the failure signs work commits with the personal
key and reports nothing. Measured, three cases:

| Situation | Result |
| --- | --- |
| Repo's real path inside the pattern, *reached* through a symlinked ancestor | matches correctly — git resolves to the real path |
| Any component of the **pattern** path is a symlink | never matches, silently |
| Repo's **real** location outside the pattern, reached via a link inside it | never matches, silently |

So the invariant to protect is that `~/Developer/work` is a real directory all
the way down, and that work repos physically live inside it. Traversing a link
to get there is harmless.

### fish — a directory link, and the stub disappears

`~/.config/fish` becomes a link to `consus/fish`. Measured: **169
abbreviations and 109 functions, exact parity with the pre-migration baseline,
with no stub file and no `set -g fisher_path` line.** `$__fish_config_dir`
resolves to `~/.config/fish`, which *is* the repo, so every mechanism fish has
— `conf.d` autoloading, `functions/`, `completions/`, `fisher_path`'s default —
points at the right place with nothing configured.

This retires every consequence the include design had to accept. `conf.d` is
autoloaded natively in native order rather than sourced late by an explicit
loop. `fish_plugins` lives at `$__fish_config_dir/fish_plugins`, which is now
inside the repo, so fisher's hardcoded path at `fisher.fish` line 4 becomes an
asset rather than a limitation. Any future plugin that hardcodes
`$__fish_config_dir` also just works.

#### What is tracked: intent, not artifacts

Only hand-written files are tracked. Everything a tool generated is ignored,
including every file fisher installed. Measured on this machine:

| Origin | Entries | Tracked |
| --- | --- | --- |
| fisher, across all four plugins | 82 | no |
| tool-generated — `copilot`, `pipx` and `proto` completions, plus fish's own `fish_frozen_key_bindings.fish` and `fish_frozen_theme.fish` from a 4.x upgrade | 5 | no |
| OrbStack — `completions/{docker,orbctl,kubectl}.fish`, symlinks into `/Applications/OrbStack.app` | 3 | no |
| `fish_variables` | 1 | no |
| hand-written — `config.fish`, `fish_plugins`, `conf.d/{android,proto,rustup}.fish`, `functions/gfu.fish` | 6 | **yes** |

That is 97 entries — 94 regular files and 3 symlinks — of which 6 are the
record. The symlinks matter twice over: they are the third-party class this
design has to handle, and they are why every count here is stated in *entries*.
An enumeration written as `find fish -type f` misses them, which is how they
went unnoticed in the first pass; `bin/doctor` must therefore enumerate with
`! -type d` rather than `-type f`.

Fisher's own bookkeeping is what makes the rest of the split trustworthy: the
union of its `_fisher_*_files` universal variables named 88 files when measured,
all 88 existed, and it claimed nothing that was gone. Dropping two plugins in
Phase 0 takes that to 82.

This inverts the earlier plan, which vendored the plugin files into the repo. The
record is now `fish_plugins` — a declaration of what should be installed — and
those 82 files are its build output. Three consequences, and the third is a real
cost:

- The "fisher state is split" problem dissolves rather than being managed.
  `fisher update` reinstalling over tracked files was the whole hazard; nothing
  it writes is tracked any more, so it is simply the designed rebuild step.
- A rebuilt machine needs a **two-step bootstrap**, not just `fisher update`.
  `functions/fisher.fish` and `completions/fisher.fish` are themselves among the
  82 ignored files, so a fresh clone has `fish_plugins` and no fisher at all —
  the command that reads the record does not exist yet. Fisher's own documented
  install line comes first:

  ```fish
  curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
  fisher install jorgebucaran/fisher   # makes fisher itself permanent
  fisher update                        # materialises the rest from fish_plugins
  ```

  This needs network, and it is the only step in the whole design that executes
  code fetched at runtime. `bin/doctor`'s declared-but-not-installed check is
  what tells you it is needed, and it names these commands. On *this* machine
  nothing changes: the 82 files are already on disk and stay there.
- **Pins are per-plugin, and only two of the four can float.** The rule is a
  major-version alias where upstream publishes one, and fisher itself
  deliberately unpinned so the installer stays current:

  | plugin | pin | why |
  | --- | --- | --- |
  | `jorgebucaran/fisher` | none | the installer; kept current on purpose |
  | `jhillyerd/plugin-git` | `@v0.4` | upstream publishes only minor tags (`v0.1`…`v0.4`), so this is the coarsest available and nothing floats |
  | `halostatue/fish-macos` | `@v7` | upstream publishes a moving ladder (`v7`, `v7.3`, `v7.3.0`); `v7` tracks the latest v7.x |
  | `halostatue/fish-utils-core` | `@v3` | same ladder |

  Two of the four therefore reproduce exactly and two track a major. That is a
  deliberate loosening of "the declaration determines the build": patch and minor
  fixes for the halostatue pair arrive without action, and in exchange the same
  commit can materialise different plugin code on different days. The pair is
  unused by anything in the tracked set, so the exposure is bounded.

`fish_variables` stays ignored: it is rewritten constantly, and being ignored it
is **unrecoverable by `git restore`**, which is why it appears in the destruction
accounting below.

### ghostty — the one include

`~/.config/ghostty/config.ghostty`, written by `bin/install`:

```text
config-file = /Users/<you>/Developer/LRNZ09/consus/ghostty/config.ghostty
```

Ghostty is the exception because its winning path is outside `~/.config`
entirely. Measured, with `~/Library/Application Support/com.mitchellh.ghostty/config`
in place carrying `window-save-state = always` and `macos-titlebar-style = tabs`:

| Setup | Effective value |
| --- | --- |
| `$XDG_CONFIG_HOME/ghostty` says `never` / `native` | `always` / `tabs` — **Application Support wins** |
| Same, but as a `config-file` include | `never` / `native` — **the include wins** |

So a bare link at `~/.config/ghostty` would be **inert** while that file exists,
and it exists with four real settings in it. The include wins because included
files load last, which also means the Application Support file no longer has to
be deleted or asserted absent — a requirement worth losing, because Ghostty
writes that file itself and its own header says so, so any assert-absent check
would hard-fail on a comments-only file.

The include is also the only machine-checkable liveness signal across the three
live tools: `ghostty +validate-config` exits 1 and names the missing file when the
target is absent. A severed *link*, by contrast, exits 0 — ghostty simply falls
back and reports success. Use the bare path, not the documented `?` prefix.
`~/.config/ghostty` does not exist on this machine today, so nothing is
displaced.

### Dropped: opencode, gh and micro

**opencode.** Dropped on YAGNI. No `opencode` binary is on `PATH`, in
`~/.proto`, `~/.bun/bin` or anywhere else on this machine; `~/.config/opencode`
holds only a bun project. Tracking its config versions something that never
runs, and it was the one entry in the activation table that could not be
verified at all. It also drags in three gitignore rules for `node_modules/`,
`package.json` and `bun.lock`, and a note that a clone does not restore the pin
on `@opencode-ai/plugin` 1.1.39. Re-add it, as a directory link like the others,
when the binary is actually installed.

**gh.** Dropped on payload size, not on mechanism — the previous
disqualification no longer holds. Measured: gh writes `config.yml` in place and
a **file** link on it survived `gh config set` with the write reaching the
target, and `hosts.yml` is created next to the link in `~/.config/gh`, never in
the repo. So a single file link would work with the OAuth token staying outside
the repo. The entire payload is `git_protocol: https` plus one alias, so it
stays two lines on the restore checklist instead. (For the record, gh has no
include directive: an `include:` key in `config.yml` is accepted and stored —
`gh config get include` returns it — but never read, with no error.)

**micro.** Only whole-directory `-config-dir` and `MICRO_CONFIG_HOME`, neither
an include; `micro -options` (148 lines) has no include key. The tracked payload
would be `bindings.json` containing literally `{}` — two bytes, zero
information. `~/.config/micro` is `root:staff` mode `755`, but that is *not* the
obstacle it was under the include design: `~/.config` is user-owned mode `700`,
and directory write permission governs `unlink`, so replacing the entry with a
link needs no `sudo`. It is dropped for having nothing worth tracking.

## Repo layout

```text
consus/                          # ~/Developer/LRNZ09/consus, mode 700
├── README.md                       # everything needed to act; see below
├── bin/install                     # links, the ghostty stub, lefthook install, chmod
├── bin/doctor                      # read-only; readlink targets + ghostty validate
├── docs/superpowers/specs/…-consus-migration-design.md   # this file
├── git/                            # 5 of the 8 dotgit files, git mv'd — history kept
│   ├── config
│   ├── config-local.example
│   ├── config-work.example
│   ├── ignore                      # was ~/.gitignore — git's default path, via the link
│   ├── README.md                   # per-machine identity, next to the files
│   └── .gitignore                  # keeps config-local / config-work untracked
├── fish/                           # 6 hand-written; 91 generated entries ignored
├── ghostty/config.ghostty
├── lefthook.yml
├── .gitleaks.toml                  # already at the root — no merge needed
├── .gitignore
├── .markdownlint.jsonc              # prose wraps at 80; code blocks stay verbatim
└── .github/workflows/gitleaks.yml  # root only; GitHub reads workflows nowhere else
```

The rename buys three simplifications over building a second repo and absorbing
this one with `git subtree`: `.gitleaks.toml` and `.github/workflows/` are
**already** at the root, so there is no nested copy to merge or delete, and
`docs/` is already where it belongs. What does need doing is deleting
`.githooks/`, superseded by the root `lefthook.yml`, whose gitleaks hook must
cover at least what `.githooks/pre-commit` covers today.

### What the README must contain

The self-reproducibility claim rests on this file, so its contract is explicit:
it carries everything a person needs to **do**, and delegates every *why* to
the design document with a single link. Six things:

1. What the repo manages - git, fish, ghostty - and what it deliberately does
   not: `zed`, `opencode`, `gh` and `micro`, one line of reason each.
2. The fresh-machine quickstart in order: clone, `./bin/install`, the three-line
   fisher bootstrap, `./bin/doctor` to verify.
3. Where per-machine settings go, per tool: `git/config-local`, any new
   `fish/conf.d/*.fish`, and `?~/.config/ghostty/local.ghostty`.
4. That `~/.config/git` and `~/.config/fish` are **symlinks into this repo**, and
   the hazard that follows: `rm -rf ~/.config/fish/` with a trailing slash
   empties the repo directory and only the 6 tracked files come back.
5. Secret scanning: lefthook plus gitleaks locally, and the workflow as the
   backstop that `--no-verify` cannot bypass.
6. One link to the design document.

It does not restate measurements, rejected alternatives or phases. Those are what
the design document is for, and duplicating them is how the two begin to
disagree.

There is no `stubs/` directory. Only one stub survives, and it carries an
absolute path that differs per clone, so `bin/install` writes it rather than
copying a tracked file. Self-reproducibility is preserved: a clone reaches a
working state from its own README and its own `bin/install`, and `fides` may
call that script as a convenience, exactly as it already calls
`lefthook install` — convenient, never required.

## bin/install and bin/doctor

`bin/install` derives the repo path from its own location
(`unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd -P`) so it works from any
clone path, honours `XDG_CONFIG_HOME`, converges to a no-op on re-run,
`chmod 700`s the repo root, and exits non-zero naming the `brew` command if
lefthook is absent. The `chmod` belongs in the script or it will be forgotten:
`~/.config` is mode `700` while `~/Developer/LRNZ09` is `755`, and a fresh clone
materialises `644` files.

It processes `~/.config/git` **last**, and performs that path's backup-move and
link creation as adjacent operations with nothing in between — no prompt, no
other path. Between those two operations there is no global git config at all,
so the window must not be allowed to span an interactive question.

For each path where a link belongs it does one of five things:

1. **Already the correct link** → nothing, silently.
2. **Nothing there** → create the link.
3. **A link pointing anywhere else, including a dangling one** → move the link
   itself into the backup directory and create the correct one. No diff and no
   prompt: moving a link never touches its target, so no machine content is at
   risk, and this case is therefore allowed under `--non-interactive` so a
   relocated clone can self-heal.
4. **A real directory or file** → show `diff -rq` between that path and the repo
   directory, then offer three resolutions. The diff excludes `.git/` and
   anything the repo's `.gitignore` covers, or `~/.config/git` alone drowns the
   output in its old object store.
5. **No TTY, or `--non-interactive`, for case 4, and no resolution declared
   for that path** → refuse and print, always. `fides` calls this script, and a
   prompt inside an ansible task hangs the play. This is what keeps
   `--check --diff` truthful, with `bin/doctor` as the probe.

**`bin/install` never deletes anything.** Every displaced path is *moved* to a
backup directory and every move is reversible by moving it back. Backups go to
`~/Backups/consus-install-<timestamp>/`, overridable with `--backup-dir`, and
deliberately **not** to a `<path>.bak` sibling inside `~/.config`: that would be
clutter in a namespace every tool enumerates, and it would leave something you
have to delete recursively later. The timestamp means a second run can never
silently clobber the first run's backup.

Inside the backup directory each displaced path keeps its location relative to
the config root — `~/.config/fish` becomes `<backup>/fish` and
`~/.config/ghostty/config.ghostty` becomes `<backup>/ghostty/config.ghostty` —
so restoring is a move back to the same relative path. The rollback commands
depend on this. If the backup directory already holds an entry for a path
install is about to displace, it refuses that path and prints, changing nothing
— a backup slot is never reused or written into twice.

The three resolutions:

- **overwrite** — move the existing path into the backup directory, then link.
  The repo's content wins.
- **merge** — back up as above, then union the two trees into the repo. Files the
  repo lacks are copied in. For a file present in both but differing, **the
  machine's version lands in the working tree as an unstaged modification**:
  nothing is decided silently, `git status` becomes the review queue,
  `git restore` means "the repo was right" and `git commit` means "the machine
  was right". Ignored files are copied in too even though the diff does not
  display them — `fish_variables` is runtime state, not record, and dropping it
  would discard every `set -U` including fisher's `_fisher_*` keys.
- **refuse** — print the paths and exit non-zero, changing nothing.

### Declaring a resolution instead of typing one

Case 4 needs a decision, and an unattended run has nobody to make one. Two
flags close that gap without weakening case 5:

- `--resolve <fish|git>=<overwrite|merge|refuse>` states the decision up front.
  It never prompts, so the hazard case 5 exists to prevent — a prompt inside an
  ansible task hanging the play — is untouched, and a path with no declaration
  still refuses.
- `--resolve <path>=merge` additionally requires
  `--expect-diff <path>=<digest>`, the digest `bin/install` prints at the end of
  every diff it shows. Merge is the only action that writes machine content into
  this repo's working tree, and the digest is what ties that write to a diff
  somebody actually read.

Both are validated against a closed set at parse time and exit 2 on anything
else, so a typo cannot degrade into a silent refusal. The run is also
all-or-nothing: every path is classified and every decision settled before
anything moves, so a run that cannot finish changes nothing at all rather than
leaving a half-linked machine behind.

The digest is also what keeps these flags out of a provisioner. A satellite
entry carrying `--resolve fish=merge --expect-diff fish=<digest>` stops working
the moment the machine drifts, because the digest no longer matches — which is
precisely the state where nobody has looked at the diff. So the flags serve a
one-shot operator-driven run, and `fides` goes on calling
`bin/install --non-interactive` with no resolution at all, which still refuses.

`bin/doctor` is read-only. It compares each `readlink` against its expected
target, asserts that `~/.config/ghostty/config.ghostty` exists and contains
exactly the `config-file` line for *this* clone's derived path, and only then
runs `ghostty +validate-config`.

It also reports **unclassified entries** under `fish/`: everything present
(`! -type d`, so symlinks count), minus what is tracked, minus what fisher
claims in its `_fisher_*_files` variables, minus the known-generated set, minus
the three OrbStack symlinks, minus `fish_variables`. All five subtrahends are
needed for the difference to close: 82 + 6 + 5 + 3 + 1 = 97. Fisher stores its
paths with a literal `~/.config/fish/` prefix, so doctor must strip that prefix
and compare paths relative to the fish directory it is actually enumerating —
otherwise nothing ever matches and every file reports as unclassified.

A new hand-written function appears in that report, which is the only way it
becomes visible at all: the allow-list hides it from `git status`. The report is
advisory and never fails the run, and doctor skips the comparison entirely when
`_fisher_plugins` is unset, since on a machine where `fisher update` has not run
every plugin file would otherwise report as unclassified.

Separately, and this one **does** fail: doctor asserts that every plugin declared
in `fish/fish_plugins` appears in `_fisher_plugins`, reporting "declared but not
installed: N". Without it, `fides` has no probe for the state that this
revision's tracking change makes possible — a correct clone, correct links,
`bin/doctor` green, and not one of the 82 plugin files on disk. The remedy is
`fisher update`, which needs network, so doctor reports and the operator or the
`fides` task runs it.

The stub assertion is not redundant. Measured: `+validate-config` exits **1**
when the stub names a target that is missing, but exits **0** when the stub is
absent altogether — ghostty simply falls back to Application Support and reports
success. So ghostty self-reports a broken include and stays silent about no
include at all. Likewise the `readlink` comparison is load-bearing because for
git and fish a severed link is completely silent.

## The .gitignore

```gitignore
.DS_Store

# .remember/: 11 entries, 112 KB, follows the link into the tree.
# No trailing comments anywhere in this file — see below.
/git/.remember/

# fish: the record is what I wrote. Tools generated the other 91 entries —
# fisher owns 82, fish_plugins is the declaration behind those, five are
# tool-generated and three are OrbStack completion symlinks.
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

`config-local` and `config-work` are covered by `git/.gitignore`, which arrives
with the rename and needs no change. `/fish/completions/` needs no rule of its
own: `/fish/*` covers it and nothing re-includes it, because every file in it is
generated.

Verified as written, against a copy of the real tree: it stages exactly those
six files, leaves nothing untracked-and-unignored, and `git check-ignore`
confirms the intended rule catches each class — `/fish/functions/*` for a
fisher-installed function, `/fish/*` for a generated completion,
`/fish/conf.d/*` for a fish-generated frozen-theme file.

Two mechanical points, both measured, because getting either wrong is silent:

- **The directory re-includes must come after `/fish/*`.** That line excludes the
  `conf.d` and `functions` directories themselves, and a file cannot be
  re-included once a parent directory is excluded. Measured across three
  orderings of the same block: as written above, 7 files stage; with
  `!/fish/conf.d/` and `!/fish/functions/` moved to the very end of the block, 7
  files still stage; hoisted *above* `/fish/*`, only **2** stage —
  `config.fish` and `fish_plugins` — silently dropping all four tracked `conf.d`
  files and `functions/gfu.fish`. Their position relative to `/fish/conf.d/*`
  and `/fish/functions/*` does not matter at all, because those patterns require
  a path component after the directory and so can never match the directory
  itself.
- **No pattern may carry a trailing comment.** gitignore honours `#` only at the
  start of a line, so `/git/.remember/    # 11 entries` is a pattern whose text
  includes the comment, and it matches nothing. Measured: with the annotation
  appended, `.remember/f` is **not ignored**; with a bare pattern it is. Every
  annotation in this file therefore sits on its own line.

### This is a deny-by-default allow-list, which this design rejected once

It is worth naming that directly, because the `/*` allow-list is the construction
that made a repo at `~/.config` unacceptable. Two things make it acceptable here
and neither is a matter of taste:

- **No credential is under `fish/`.** The `~/.config` objection was specifically
  that one corrupted character stages an age key. Here the worst case of a
  malformed rule is a *missing* shell function, and the tarball plus the machine
  itself both still have it.
- **The blast radius is one directory**, not 1,138 files across seven credential
  stores.

What does carry over is the silent-omission risk, and it is confirmed rather than
hypothetical: a new hand-written function that nobody adds a negation for is
**invisible to `git status`**. Measured — a fresh `functions/newthing.fish`
produced no output at all, not even as untracked. A design whose whole argument
is that drift should be visible cannot leave that unhandled, so `bin/doctor`
detects it.

## Destruction accounting

**The migration itself deletes nothing.** No step in Phases 0 to 5 runs `rm -rf`,
or any `rm` at all. Every displaced path is moved — into the repo, or into a
timestamped directory under `~/Backups` — and every move is reversible by moving
it back. The only recursive removal anywhere is `git rm -r .githooks` in Phase 1,
which removes tracked files that stay recoverable from history. Discarding the
backup directories afterwards is optional, unscheduled and yours to do whenever
you like.

What follows is therefore a list of hazards to *avoid*, not steps to run. The
links introduce exactly one new hazard class, and it was measured rather than
assumed:

- `rm -rf ~/.config/fish/` **with a trailing slash** follows the link and empties
  the repo directory. Measured: 101 regular files → 0, with the link itself
  surviving; the 3 OrbStack symlinks go the same way.

  The recovery cost of that accident **went up** when the fish allow-list went
  in, and it is worth stating plainly. `git restore` recovers the 6 tracked
  files. The other 91 entries are not in git at all: 82 come back with `fisher
  update`, which needs network, 5 come back only when `copilot`, `pipx`, `proto`
  and fish itself next regenerate them, and 3 come back when OrbStack next
  runs. That is the price of tracking intent instead
  of artifacts, paid exactly once per accident, and the tarball covers it.
- Genuinely unrecoverable by any git operation: `fish_variables`,
  `config-local`, `config-work` and `.remember/`. The last three exist nowhere
  else at all once the Phase 3 tarball is discarded.
- `git clean -fdx` run from inside a linked directory now reaches the repo,
  because `git rev-parse --show-toplevel` resolves there. Same blast radius.
- Whole-directory replacement severs the link without touching the target.

None of these can reach a credential, because no credential store is under any
path this repo contains.

## Verified facts

### Measured 2026-08-21 (this revision)

- git needs **zero configuration** through a directory link: relative
  `include.path` resolves against the link path, and `--show-origin` reports
  `file:$XDG_CONFIG_HOME/git/config-local`.
- `git config --global --add` through the link landed in the tracked file, left
  the link intact, and showed `git/config` as modified in the worktree.
- `--unset` of a key in the tracked file returns **rc=0**; of a key in an
  included file, **rc=5**.
- `includeIf "gitdir:"` through a linked config directory: work repo → work
  identity, personal repo → personal identity. A symlinked *ancestor* used to
  reach a repo whose real path is inside the pattern **matches**. A symlink in
  the **pattern** path, or a repo whose real path is outside the pattern,
  **never matches and says nothing**.
- git preserves a **file**-level symlink on its config across a write — it
  resolves symlinks before taking the lock — so `git` is one of the few tools
  for which a file link would also have worked. Directory links are used anyway,
  for uniformity and because no other tool offers that guarantee.
- fish via a directory link: **169 abbreviations, 109 functions**, identical to
  baseline, with no stub and no `fisher_path` assignment.
  `$__fish_config_dir` = the link path.
- fish writes `fish_variables` into the linked tree (97 bytes in the sandbox).
- Ghostty: `$XDG_CONFIG_HOME/ghostty` **loses** to Application Support
  (`never` lost to `always`); a `config-file` include **beats** Application
  Support (`never`/`native` won); `+validate-config` exits **1** naming a
  missing include target, and exits **0** on a severed link. Ghostty reads both
  `config` and `config.ghostty`; App Support wins over either.
- Whole-directory replacement (`mv dir dir.bak; mkdir dir`) moves the link, not
  the target: 101 repo files intact.
- `rm -rf <link>/` with a trailing slash: 101 regular files → 0, link surviving,
  `git restore` recovering 100 — measured against the earlier scheme that
  tracked every fish file. Under the allow-list adopted in this revision the
  same accident recovers 6 by `git restore`, with 82 needing `fisher update`.
- `git rev-parse --show-toplevel` from inside a linked directory names the repo.
- gh writes `config.yml` in place; a file link on it survived `gh config set`
  with the write reaching the target, and only `config.yml` existed in the link
  directory afterwards.
- `~/.config` is `lorenzo:staff` mode `700`, so replacing the root-owned
  `~/.config/micro` entry needs no `sudo`. `~/.config/ghostty` does not exist.
- `~/.config/git` contains exactly three things that are not tracked and pushed:
  `config-local`, `config-work`, `.remember/`.
- `fish_plugins` listed six plugins with two pinned before Phase 0's
  housekeeping, and four after. `~/.config/fish` holds
  **104 entries**: 101 regular files and 3 symlinks — 97 after Phase 0 drops two
  plugins. The symlinks are OrbStack's
  `completions/{docker,orbctl,kubectl}.fish`, pointing into
  `/Applications/OrbStack.app`. A `find -type f` enumeration misses all three,
  which is why `bin/doctor` must use `! -type d`.
- Of those 101, fisher claims **88** across its six `_fisher_*_files` universal
  variables. All 88 existed and it claimed nothing gone, so its bookkeeping
  is a trustworthy basis for classification. Of the remaining 13, five are
  tool-generated (`completions/copilot.fish`, `completions/pipx.fish`,
  `completions/proto.fish`, and `conf.d/fish_frozen_key_bindings.fish` plus
  `conf.d/fish_frozen_theme.fish`, both self-identifying as "created by fish
  when upgrading to version 4.x"), one is `fish_variables`, and seven are
  hand-written.
- The fish allow-list in this document, run against a copy of the real tree,
  stages **exactly** those seven files and leaves nothing
  untracked-and-unignored. `git check-ignore` attributes each class to the
  intended rule: `/fish/functions/*` catches a fisher-installed function,
  `/fish/*` a generated completion, `/fish/conf.d/*` a fish-generated frozen
  file.
- A new hand-written `functions/newthing.fish` under that allow-list produces
  **no `git status` output at all** — not even as untracked. Silent omission is
  real, which is what `bin/doctor`'s unclassified-files report exists for.
- gitignore re-include ordering, measured across three orderings of the same
  block against a copy of the real tree: as written in this document, 7 files
  stage; with the two directory re-includes moved to the end of the block, 7
  still stage; hoisted above `/fish/*`, only **2** stage. So the constraint is
  that the re-includes must follow `/fish/*`, not that they must precede
  `/fish/conf.d/*` — those patterns require a component after the directory and
  can never match the directory itself.
- gitignore honours `#` only at the start of a line. Measured with the global
  excludes file disabled: `/git/.remember/    # 11 entries` ignores nothing,
  while a bare `/git/.remember/` ignores. A trailing comment silently disables
  its pattern.
- `git add --chmod=+x` records mode `100755` in the index and leaves the
  working-tree file at `644`. Measured: `test -x` fails afterwards, so
  `./bin/install` would exit 126. Only a real `chmod` fixes the file on disk.
- `~/.config` is 279 MB on disk. `tar czf` over it with **no exclusions**
  produces **22 MB**, against roughly 7.5 MB when `gatsby/` and `raycast/` are
  excluded. The exclusions bought 14.5 MB.
- `git mv` with multiple sources **fails** on a destination directory that does
  not exist: `fatal: destination 'git/' is not a directory`. A single-source
  `git mv config git` with no `git/` present succeeds and silently creates a
  *file* named `git`. So Phase 1 step 1 needs its `mkdir`.
- `ghostty +validate-config` exits **1** when the stub names a missing target but
  **0** when the stub is absent entirely. Ghostty reports a broken include and
  stays silent about no include, so `bin/doctor` must assert the stub itself.
- The tracked `config` sets `core.excludesfile = ~/.gitignore`. That file exists
  (123 B, mode 644), holds `**/.claude/settings.local.json` and `.remember/`,
  and lives outside every repo — `git check-ignore -v --no-index .remember/x`
  names it as the source. It is what currently keeps `.remember/` out of this
  repo, a fresh clone does not have it, and the Phase 3 tarball does not contain
  it either: that archive is rooted at `~/.config` and this file is one level up.
- `git check-ignore` refuses paths outside the repository (rc=128), so any
  verification of it must use a repo-relative path from inside the repo.

### Measured while interviewing the plan, 2026-08-21

- `functions/fisher.fish` and `completions/fisher.fish` are themselves in
  fisher's own file list, so a fresh clone has no fisher. This is why the rebuild
  needs a bootstrap and not just `fisher update`.
- Per-plugin contribution, by removing each plugin's files from a copy of the
  tree and re-counting: `jhillyerd/plugin-git` supplies **all 169**
  abbreviations and 12 functions from 19 files; `halostatue/fish-macos` 8
  commands from 48 files; `halostatue/fish-utils-core` 7 predicates from 13
  files; `gazorby/fish-abbreviation-tips` 1 function from 5 files. Neither
  halostatue plugin references the other's functions, and nothing in the tracked
  set references either.
- fish history spans 2025-05-02 to 2026-08-21 across 3,690 commands. It records
  zero invocations of any `fish-macos` or `fish-utils-core` command, and
  `gwip`/`gunwip`/`gbda` from `plugin-git`. Abbreviation use cannot be measured
  this way, since abbreviations expand before the command is stored.
- fish 4.8 provides `up-or-search` as an **embedded** function — no file in
  `share/fish/functions`, and `functions --details` reports
  `embedded:functions/up-or-search.fish`. Both `up` and `ctrl-p` are preset-bound
  to it. `2m/fish-history-merge`'s copy differed in three lines: the
  description, a missing `set -l` that leaks `$lineno` globally, and one added
  `history merge`. Removing the file leaves `functions | count` at 109 because
  the embedded version takes over.
- `abbr_tips` held `__ABBR_TIPS_KEYS` and `__ABBR_TIPS_VALUES` at 168 entries
  each, plus `ABBR_TIPS_REGEXES` and `ABBR_TIPS_PROMPT`, all universal and
  **exported**: **5,301 bytes** of environment in every child process. Its
  `abbr_tips_uninstall` event erases all of them and the three key bindings.
- `history merge` is effectively free: ten calls plus a full fish startup total
  38 ms on a 10,083-line history.
- Tag availability: `jorgebucaran/fisher` 4.4.8 (no `v` prefix);
  `jhillyerd/plugin-git` publishes minor tags only (`v0.1`…`v0.4`);
  `gazorby/fish-abbreviation-tips` publishes `v0.7.0` with no `v0` alias;
  `halostatue/fish-macos` and `fish-utils-core` publish moving ladders
  (`v7`/`v7.3`/`v7.3.0`, `v3`/`v3.3`/`v3.3.0`); `2m/fish-history-merge` has no
  tags at all and no commit since 2020-11-21.
- `credential.helper` accepts a bare `git-credential-manager`, which resolves
  through `PATH` to `/usr/local/bin/git-credential-manager` here. The absolute
  path in the tracked config is therefore unnecessary as well as unportable.
- Ghostty ignores platform-inapplicable keys silently: `gtk-single-instance`,
  `gtk-titlebar` and `linux-cgroup` on macOS produce no diagnostics and exit 0,
  so the `macos-*` keys are inert on Linux rather than errors.
- `ghostty +validate-config` **is** a general validity check, measured without a
  pipe swallowing the status: exit 1 for an unknown field, exit 1 for an invalid
  value, exit 1 for a bare `config-file` whose target is missing, exit 0 for a
  valid config and exit 0 for a `?`-prefixed optional include whose target is
  missing. So `bin/doctor` can rely on the exit code alone.
- The `?` prefix makes an include optional in both directions: missing target
  exits 0 with no diagnostic, and a present target still loads and still wins on
  precedence (`always` from an optional include beat `never` in the including
  file).
- `proto activate fish | source` is **broken in agent environments** and cannot
  be fixed from this config. proto detects an agent (Claude Code sets `AI_AGENT`
  among others) and emits NDJSON on stdout, which `source` then fails to parse —
  20 lines of errors per fish startup. `proto activate` rejects `--format`,
  and neither `env -u AI_AGENT` nor `PROTO_JSON=false` suppresses it. Recorded as
  a wart, not fixed: it is proto's behaviour, it affects only agent-driven
  shells, and the `type -q proto` guard is still worth having for portability.
  Consequence for this plan: verification commands like `fish -c 'abbr | count'`
  print the right answer on stdout with that noise on stderr, so compare stdout.
- After Phase 0's housekeeping, measured on a copy: `abbr | count` 169,
  `functions | count` 108, 97 entries in the fish directory, and the allow-list
  in this document stages exactly 6 files with nothing untracked-and-unignored.
- The Application Support ghostty config carries exactly four non-comment
  settings: `macos-titlebar-style = tabs`, `shell-integration = fish`,
  `shell-integration-features = sudo,title,ssh-terminfo,ssh-env`,
  `window-save-state = always`.

### Measured 2026-08-20 (carried forward)

- As of 2026-08-20 `dotgit` tracked 8 files across 6 commits — a snapshot, not a
  gate; it is 9 files across 8 commits at the time of this revision and grows
  every time this document is committed. Phase 2 asserts against the numbers
  Phase 0 records, never against these. The file set was: `config`, `config-local.example`,
  `config-work.example`, `README.md`, `.gitignore`, `.gitleaks.toml`,
  `.githooks/pre-commit`, `.github/workflows/gitleaks.yml`.
- `git config --global --list` does **not** expand includes. Use
  `git config --list` from inside a repo, or a false negative is easy to record.
- `rename(2)` and `unlink(2)` act on the final path component and never follow a
  symlink there, but an intermediate symlink is traversed. So a file-level link
  is destroyed by a generic atomic write and a directory-level link is not.
- `rg` requires a git repository before it applies `.gitignore` rules.
- `~/Desktop` is iCloud-synced: `com.apple.file-provider-domain-id` is set on it
  and `~/Library/Mobile Documents/com~apple~CloudDocs/Desktop` exists.
- `tmutil destinationinfo` reports no Time Machine destination, and no restic,
  borg, arq, kopia, duplicati or Backblaze is installed. **There is no local
  backup of `~/.config` at all.** The git remote is the entire backup story.
- `~/.claude` reports `settings.json` as modified — Claude Code rewrites its own
  tracked file — so the `fides` `safety` role is already unsatisfiable today and
  `-e force=true` is its normal invocation.
- Ansible is **not installed** anywhere on this machine, and neither is any
  symlink-farm tool. Every claim about module behaviour is read from source and
  labelled as documentation, never observed.
- Tooling present: git 2.55.0, fish 4.8.0, ghostty 1.3.1, gh 2.96.0,
  micro 2.0.15, rg 14.1.1, lefthook 2.1.10, gitleaks 8.30.1.
  `git-filter-repo` is **not** installed and is not needed.

## Phase 0 — rename, then push what is already here

The rename comes first so that no artifact ever carries the old name, no clone
URL needs fixing afterwards, and nothing relies on GitHub's redirect. It is
reversible with `gh repo rename dotgit`, and GitHub redirects both directions.

```sh
gh repo rename consus -R LRNZ09/dotgit
git -C ~/.config/git remote set-url origin https://github.com/LRNZ09/consus.git
```

Then commit this document and push. It travels into the clone as history rather
than as a copy.

Phase 0 is the only phase that changes this machine before anything is cloned,
and every change in it is worth making whether or not the migration proceeds:
two unused plugins removed, four unguarded config spots fixed, a rename that is
reversible with one command. Nothing here depends on the rest of the plan.

### Plugin housekeeping, first

Two plugins come out before anything is copied, because Phase 1 captures whatever
the fish directory looks like at that moment. This is a change to the machine's
configuration that the migration then records — not part of the migration
mechanism — so it belongs here, ahead of the clone.

```fish
fisher remove 2m/fish-history-merge gazorby/fish-abbreviation-tips
mv ~/.config/fish/conf.d/abbr_tips_override.fish ~/Backups/   # now dead code
```

`2m/fish-history-merge` was one file: a 2020 copy of `up-or-search`, which fish
4.8 provides as an embedded function, differing from fish's current version in
three lines — a description, a missing `set -l` that leaks `$lineno` into the
global scope, and one added `history merge`. Measured: with the file gone, fish's
embedded version takes over and `functions | count` stays at 109, so the only
thing lost is merging other live sessions' history on Up. The behaviour is
dropped rather than reimplemented.

`gazorby/fish-abbreviation-tips` was 201 lines, unmaintained since January 2023,
hooked into `fish_postexec` on every command, and mirrored every abbreviation and
alias into two universal **exported** arrays. Measured: **5,301 bytes of
environment carried into every child process**, for data nothing outside fish
reads — and that export is the mechanism behind the CESU-8 crash the
`abbr_tips_override.fish` comment documents, so its removal retires a bug class
rather than a symptom. Its `abbr_tips_uninstall` event erases every variable it
set and restores the three key bindings, so `fisher remove` reclaims everything.
`conf.d/abbr_tips_override.fish` exists only to patch that plugin, so it goes too.

### Portability edits, also first

The repo's contract is that a clone works on any machine, not just this one. Four
spots break that today, and all four are one-liners applied before Phase 1
captures anything:

| File | Change | Why |
| --- | --- | --- |
| `git/config` | `helper = git-credential-manager` | drops the absolute `/usr/local/bin/` path; measured, the bare name resolves via `PATH`, which is the portability argument the file's own `!gh` comment already makes |
| `fish/config.fish` | `$HOME/.local/bin` | removes a hardcoded `/Users/lorenzo` from a public repo — the same objection this document uses to reject outward symlinks |
| `fish/conf.d/proto.fish` | wrap in `if type -q proto` | a machine without proto currently gets a hard error at startup |
| `fish/conf.d/rustup.fish` | wrap in `test -f "$HOME/.cargo/env.fish"` | same, for Rust |
| `fish/conf.d/android.fish` | guard on `test -d` for the SDK and the JBR | both paths are macOS-only and unconditional today |

Measured after all five: `abbr | count` 169, `functions | count` 108,
`ANDROID_HOME` and `JAVA_HOME` still set, `.local/bin` still on `PATH`, proto
still active. Behaviour on this machine is unchanged.

`core.editor = code --wait` stays in the tracked config as the portable
default —
it is a `PATH` lookup, not an absolute path — and a machine without VS Code
overrides it in `config-local`, which is included last and therefore wins. The
same applies to the `difftool`/`mergetool` commands.

Ghostty needs nothing for platform differences. Measured: `gtk-single-instance`,
`gtk-titlebar` and `linux-cgroup` in a config on macOS produce no diagnostics and
exit 0, so the `macos-*` keys are inert on Linux by the same mechanism rather
than being errors.

#### Where per-machine settings go, per tool

Portability needs an escape hatch per tool, not just guards. All three exist:

- **git** — `config-local`, already there, untracked, included last so it wins.
- **fish** — free, and worth stating as a designed property rather than leaving
  as an accident: the allow-list ignores everything under `fish/` that it does
  not name, so **any new `conf.d/*.fish` file is machine-local by default**. Drop
  a `conf.d/zz-local.fish` on a machine and it is untracked with no rule change.
- **ghostty** — the repo's `ghostty/config.ghostty` ends with
  `config-file = ?~/.config/ghostty/local.ghostty`. The `?` prefix makes it
  optional: measured, a missing target exits 0 silently, and a present target
  loads and wins on precedence. This is the one place the `?` form is correct;
  the stub's include of the repo config stays **bare**, so a broken link fails
  loudly instead of silently reverting to Application Support.

Afterwards, measured: `abbr | count` is still **169** and `functions | count` is
**108**, and the fish directory is 97 entries with 6 hand-written. The two
halostatue plugins stay: they are 61 of the remaining files and 15 commands with
no recorded use in 14 months, but they are ignored files that fish autoloads
lazily, so keeping them costs essentially nothing.

Record the commit count before cloning. Phase 2 asserts against it rather than
against a number hardcoded here, which goes stale every time this document is
committed:

```sh
BASELINE_COMMITS=$(git -C ~/.config/git rev-list --count HEAD)   # 8 at time of writing
git -C ~/.config/git ls-files | wc -l                            # 9 — for the record only
```

Only the commit count is a gate. The tracked-file count is *not* one: Phase 1
deliberately adds the whole config tree, so the total is meant to grow. What
Phase 2 checks instead is that the six files expected under `git/` are there and
that `git log --follow` still reaches through the rename.

## Phase 1 — restructure in a fresh clone

Nothing happens inside `~/.config/git` in this phase. It stays a complete,
working, pushed checkout — which is what makes it the rollback.

```sh
git clone https://github.com/LRNZ09/consus.git ~/Developer/LRNZ09/consus
```

1. **`mkdir git` first**, then:

   ```sh
   git mv config config-local.example config-work.example README.md .gitignore git/
   ```

   The `mkdir` is not optional and not cosmetic: measured, `git mv` with multiple
   sources fails outright on a destination that does not exist
   (`fatal: destination 'git/' is not a directory`), and the obvious per-file
   workaround is worse — a single-source `git mv config git` with no `git/`
   present silently creates a *file* named `git`. Since git tracks no
   directories, the bare `mkdir` needs nothing else.

   Leave `.gitleaks.toml` and `.github/workflows/gitleaks.yml` at the root;
   `docs/` is already there.

   Then **edit the moved `git/README.md`**, do not just move it. Its Setup
   section tells the reader to run `git config core.hooksPath .githooks`, and
   this same step deletes `.githooks/` in favour of the root `lefthook.yml`;
   shipping it unedited leaves an instruction that no longer applies. Its
   per-machine identity section is what survives, and it stays next to the
   `config-local` and `config-work` files it describes.

   Remove the old hook directory with
   `git rm -r .githooks` — tracked files, recoverable from history. Commit.
2. **Copy** `~/.gitignore` in as `git/ignore` — `cp`, not `mv` — and delete the
   `excludesfile` line from `git/config`. The tracked config currently points
   `core.excludesfile` at `~/.gitignore`, a file that lives outside every repo
   and that nothing backs up; the Phase 3 tarball does not even reach it, being
   rooted at `~/.config`. Through the link, `$XDG_CONFIG_HOME/git/ignore` is
   git's own documented default, so tracking it there needs no configuration at
   all — the same zero-configuration argument this design already makes for
   `config` itself. Commit.

   `cp` matters. Until Phase 3 the live global config is still
   `~/.config/git/config`, which still points at `~/.gitignore`; moving that file
   now would silently stop `.remember/` from being ignored anywhere, in exactly
   the window where a stray `git add -A` could stage it. The original is
   displaced in Phase 3 with everything else, and nothing outside the repo is
   touched before then.
3. Write the root `README.md`, root `.gitignore` and `lefthook.yml`. Commit.
   The root `.gitignore` must exist **before** `fish/` is added, or
   `fish_variables` walks straight into the index.

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

4. Copy the configs in, one commit per tool so the history stays atomic:

   | Source | Destination |
   | --- | --- |
   | `~/.config/fish/` | `fish/` |
   | Application Support ghostty config | `ghostty/config.ghostty` |

   Copy the fish directory **whole**, all 97 entries as they stand after Phase 0.
   The allow-list stages only the 6 hand-written ones, and the other 91 have
   to be present in the working
   tree regardless: after activation this directory *is* `~/.config/fish`, so
   fisher's files must physically live here for fish to work at all. Ignored and
   absent are different things. `cp -R` keeps the three OrbStack entries as
   symlinks into `/Applications/OrbStack.app`, which is correct — they are
   machine-specific, ignored, and a clone should not carry them.

   Ghostty keeps only the four real settings out of a file that is otherwise the
   shipped template's comments.

   ```text
   macos-titlebar-style = tabs
   shell-integration = fish
   shell-integration-features = sudo,title,ssh-terminfo,ssh-env
   window-save-state = always
   ```

5. Pin `fish/fish_plugins` per the table under "What is tracked": add `@v0.4` to
   `jhillyerd/plugin-git`, leave `halostatue/fish-macos@v7` and
   `halostatue/fish-utils-core@v3` as they are, and leave `jorgebucaran/fisher`
   unpinned. No lookup is needed at execution time — the tags were resolved
   while writing this document. Commit.
6. Write `bin/install` and `bin/doctor`, and make them executable **on disk as
   well as in the index**:

   ```sh
   chmod +x bin/install bin/doctor && git add bin/install bin/doctor
   ```

   `git add --chmod=+x` alone is not enough, and the failure is exactly the one
   this step exists to prevent. Measured: it records mode `100755` in the index
   while leaving the working-tree file at `644`, so `./bin/install` in the very
   next step dies with exit 126. A plain `chmod` followed by a plain `git add`
   records 100755 from disk and leaves both correct.
7. `lefthook install`, then a deliberate throwaway commit containing a fake
   secret to confirm the hook blocks it. Reset it afterwards.

## Phase 2 — rehearsal and verification gate

### Rehearse bin/install against a drifted machine

**This is the gate the whole plan hangs on, and it comes first in implementation.**
Both scripts are specified here in prose only, and prose in this document has a
measured failure rate: three claims written from reasoning rather than
measurement turned out false in review — the gitignore re-include ordering, the
effect of a trailing comment on a pattern, and what `git add --chmod=+x` does to
the file on disk. The scripts are the largest remaining body of unmeasured prose,
so writing them and passing this rehearsal is task one, and no other phase starts
until it does.

Required, not optional, and it happens on this machine — but against a redirected
`XDG_CONFIG_HOME`, so no real path is touched. The merge path is the one piece of
this design that no measurement covers, and its conflict rule only matters when
there is a conflict, so it has to be exercised against drift that is real rather
than imagined:

```sh
R=~/Backups/consus-rehearsal-$(date +%Y%m%dT%H%M%S); mkdir -p "$R/xdg"
cp -R ~/.config/fish "$R/xdg/fish"
cp -R ~/.config/git  "$R/xdg/git"          # includes .git — the diff must exclude it

# three kinds of drift that actually happen:
printf '\n# drifted by hand\n' >> "$R/xdg/fish/config.fish"              # tracked file, modified
printf 'function drifted\nend\n' > "$R/xdg/fish/functions/drifted.fish"  # new file the allow-list hides
sed -i '' 's|fish-macos@v7|fish-macos|' "$R/xdg/fish/fish_plugins"       # pin dropped

# a second, untouched drifted copy, for the non-interactive assertion:
mkdir -p "$R/xdg2"; cp -R "$R/xdg/fish" "$R/xdg2/fish"; cp -R "$R/xdg/git" "$R/xdg2/git"

XDG_CONFIG_HOME="$R/xdg" ./bin/install --backup-dir "$R/backup"
```

Choose the resolutions Phase 3 would choose, which are not the same for both
paths: **merge** at `$R/xdg/fish`, **overwrite** at `$R/xdg/git`. Merging the git
path would copy the old checkout's root-level files — and its nested `.git` —
into the repo's `git/`, which is precisely why Phase 3 does not do it.

Then assert, in order:

1. The diff at the fish path named `config.fish` and `fish_plugins` and listed no
   ignored file; the diff at the git path listed the four paths that moved to the
   repo root and did **not** list `.git/`.
2. `git status` shows exactly `fish/config.fish` and `fish/fish_plugins`
   modified, carrying the machine's content, and **nothing** under `git/`.
3. `functions/drifted.fish` is present in the working tree and invisible to
   `git status`, and `XDG_CONFIG_HOME="$R/xdg" ./bin/doctor` names it — and only
   it — as unclassified. This is the allow-list's silent-omission risk and its
   detector, tested together.
4. `"$R/backup"` holds the pre-install `fish` and `git` trees at their relative
   paths, and the originals under `"$R/xdg"` are now links.
5. A second run reports the links already correct and changes nothing.
6. `XDG_CONFIG_HOME="$R/xdg2" ./bin/install --non-interactive --backup-dir "$R/backup2"`
   refuses and changes nothing: `$R/xdg2/fish` is still a real directory
   afterwards, and `$R/backup2` was never created. It needs its own backup
   directory so the occupied-slot refusal cannot be mistaken for the
   non-interactive refusal.

Then put the repo back, without deleting anything:

```sh
git restore fish/config.fish fish/fish_plugins
mv fish/functions/drifted.fish "$R/backup"/
```

The gate below will not pass until this is done, since it requires a clean tree.

### The gate

Nothing is pushed until all of these pass. They are written as assertions rather
than observations, because two of them pass by *exiting non-zero* and the block
is otherwise unpasteable under `set -e`:

```sh
test -z "$(git status --porcelain)"                                  # clean tree
! git ls-files | grep -qE 'hosts\.yml|adc\.json|keys\.txt|rclone\.conf|apps\.json|config-local$|config-work$|fish_variables|\.DS_Store|prompts/'
                                                                     # the one that matters
gitleaks git --no-banner --redact -v --config .gitleaks.toml .       # clean over full history
test "$(git rev-list --count HEAD)" -ge "$BASELINE_COMMITS"          # no history lost
test "$(git ls-files git/ | wc -l | tr -d ' ')" -eq 6                # 5 moved + git/ignore
test "$(git log --follow --oneline -- git/config | wc -l)" -gt "$(git log --oneline -- git/config | wc -l)"
                                                                     # rename didn't orphan history
test -x bin/install && test -x bin/doctor                            # modes committed
sh -n bin/install && sh -n bin/doctor                                # both parse
rc=0; ./bin/doctor || rc=$?; test "$rc" -eq 1                        # fails the link check
git push -u origin main
```

`$BASELINE_COMMITS` is the number recorded in Phase 0. Asserting against it
rather than against a literal is what keeps this gate meaningful after this
document is committed again — a hardcoded "6 commits" was already wrong by the
time it was written.

The `--follow` line is self-relative on purpose: measured on a scratch repo, a
plain `git log -- git/config` after the move reports **1** commit while
`--follow` reports **4**, and the move registers as `rename config => git/config
(100%)`. Asserting that `--follow` sees strictly more than the plain form proves
the rename was detected without hardcoding either count. `./bin/doctor` must fail
its link check specifically — exit 1, not 126 from a missing executable bit.

`push -u` rather than `push`: it sets the upstream, without which
`git log @{u}..` exits 128 and the `fides` `safety` role cannot check this
satellite at all. Confirm the gitleaks workflow passes on GitHub before going
further.

## Phase 3 — activate

### The backup

Not `~/Desktop` and not `~/Documents` — both are iCloud-synced, and this archive
contains every credential under `~/.config` in the clear.

Nothing is excluded — not cache, and not the directories of tools this repo does
not track:

```sh
mkdir -p ~/Backups
tar czf ~/Backups/config-backup-$(date +%F).tar.gz -C ~ .config
tar tzf ~/Backups/config-backup-$(date +%F).tar.gz >/dev/null && echo "archive ok"
```

An earlier revision excluded `gatsby/` and `raycast/` as regenerable cache.
Measured, that was not a trade worth making: `~/.config` is 279 MB on disk and
the **complete** archive is 22 MB, against roughly 7.5 MB for the pruned one.
Cache compresses extremely well, so the exclusions bought 14.5 MB and cost
completeness — and completeness is the entire point here. An untracked tool's
directory (`zed/`, `raycast/`, `micro/`, `opencode/`, `gh/`) has no other copy
anywhere, so leaving it out of the one archive that exists is exactly the wrong
risk to take for 14 MB.

Verify it before going further. For everything under `~/.config` that this repo
does not touch — which now includes all 32 credentials and every dropped tool —
this is the only copy that exists anywhere.

The migration backup that `bin/install` writes is a different thing and carries
no credentials at all: `config-local`, `config-work` and `.remember/` are moved
into the repo before install runs, so what lands in `~/Backups/consus-migration-*`
is the old checkout's tracked-and-pushed content plus its `.git`. Only the
tarball needs treating as sensitive.

### Install

Nothing in this phase is deleted. Three machine-local items move to their final
home first, while `~/.config/git` is still live, and then one `bin/install` run
covers all three remaining paths:

```sh
BK=~/Backups/consus-migration-$(date +%Y%m%dT%H%M%S)   # capture it; rollback needs it
mkdir -p "$BK"
mv ~/.config/git/config-local ~/.config/git/config-work ~/Developer/LRNZ09/consus/git/
mv ~/.config/git/.remember ~/Developer/LRNZ09/consus/git/
mv ~/.gitignore "$BK"/gitignore-home        # now redundant: tracked as git/ignore
cd ~/Developer/LRNZ09/consus
./bin/install --backup-dir "$BK"
echo "$BK"   # write it down — every rollback path starts here
```

A full timestamp, not `date +%F`: the day-granular form would put two runs on one
day into the same directory, which is exactly what the no-clobber guarantee
above forbids. Since install refuses an occupied slot, a re-run needs a fresh
`BK`.

At `~/.config/git`, choose **overwrite**: everything still there is committed and
pushed, so the old checkout — `.git` included — is simply moved into the backup
directory, where it stays as the rollback until you choose to discard it. Choose
overwrite rather than merge here, because the four paths that moved to the repo
root (`.gitleaks.toml`, `.github/`, `docs/`, and the old `README.md`) are absent
from `git/` by design, and merge would faithfully copy them back in as untracked
cruft.

`~/.config/fish` is a real directory today and goes through the diff-and-merge
path. `~/.config/ghostty` does not exist, so the stub is simply written.

The trees are near-identical, since the repo's copies were taken from them, with
**one guaranteed conflict**: `fish/fish_plugins`. Phase 1 step 5 added the
`.4` pin to `jhillyerd/plugin-git`; the machine's copy does not have it. The
merge rule puts the machine's
version in the working tree as an unstaged modification, so the pinning appears
to be lost. It is not — resolve it the way the merge rule intends:

```sh
git restore fish/fish_plugins    # the repo was right
```

Then work the rest of the review queue the same way — `git restore` or
`git commit` for each remaining modified path — and push. Phase 4 gates on a
clean tree and an empty `git log ..`, so neither is meaningful until this
queue is empty.

Note also that merge copies ignored files in, and ignored files leave no trace in
`git status` and have no `git restore` path. In practice they are identical
anyway — the repo's copies came from these same directories — but if a repo-side
ignored file matters, back it up before merging.

One window to know about: from the first `mv` until the link exists, git's
`[include] path = config-local` target is gone, so identity and signing key are
silently absent — a missing include is ignored without error. Keep the commands
adjacent and make no commits in between. `bin/install` needs no global config
itself; `lefthook install` works off the repo's local config.

Deleting `~/Library/Application Support/com.mitchellh.ghostty/config` is
**optional and not recommended** — the include already overrides it, and Ghostty
rewrites that file itself.

## Phase 4 — verify

Run this only once Phase 3's review queue is empty and pushed, or the first two
checks fail by design:

```sh
./bin/doctor                                           # exits 0
git -C ~/Developer/LRNZ09/consus status --porcelain # empty
git -C ~/Developer/LRNZ09/consus log @{u}..         # exits 0, no output
git config --list --show-origin | grep -E 'user\.|include'   # NOT --global --list
git config --show-origin --get user.signingkey         # resolves inside the repo
git -C ~/Developer/work/<any> config --get user.email  # the work identity
# signing, end to end - resolving a key is not the same as signing with it:
( cd (mktemp -d) && git init -q && git commit -q --allow-empty -S -m t \
    && git log --show-signature -1 | grep -q 'Good signature' && echo 'personal signing ok' )
# and again inside ~/Developer/work, where includeIf must supply the work key
fish -c 'abbr | count'                                 # 169
fish -c 'functions | count'                            # 108
ghostty +validate-config                               # exits 0
ghostty +show-config | grep -E 'titlebar|shell-integration|window-save-state'
ls -ld ~/.config/git ~/.config/fish                    # two symlinks into the repo
grep -qF "$(pwd -P)/ghostty/config.ghostty" ~/.config/ghostty/config.ghostty
                                                       # stub names THIS clone
git check-ignore -v --no-index .remember/x             # names git/ignore in the repo
(cd ~/.config/fish && git rev-parse --show-toplevel)   # names the repo — link is live
cd ~ && git -C .config status                          # fatal: not a repo
```

The last line is a feature: `~/.config` itself is still not a repo, so nothing
that walks up from an unlinked tool's config directory finds one.

## Phase 5 — after

- No archive step. The repo was renamed, so there is no second repo to retire.
- Correct the `reference-git-signing-setup` memory, which states that
  `~/.config/git/` is its own repository. Under this design it is a symlink into
  `consus`.
- Add to the restore checklist: `gh config set git_protocol https` and the `co`
  alias; the three-line fisher bootstrap under "What is tracked" — `curl | source`,
  `fisher install jorgebucaran/fisher`, `fisher update` — since fisher itself is
  not tracked; `sudo chown` for `~/.config/micro` if micro is ever configured for
  real; and the `includeIf` invariant — `~/Developer/work` must be a real
  directory all the way down, with work repos physically inside it.
- The migration backup under `~/Backups/` is redundant once Phase 4 passes and
  the push is confirmed, but nothing in this plan deletes it. Discard it when
  you want to, however you prefer to discard things.
- Change this document's **Status** line to `executed <date>` and leave the rest
  of it alone. The phases stop being instructions and become the record of what
  was actually done to this machine; the measured-facts section is why nobody
  re-derives whether ghostty outranks a symlink or what `git add --chmod=+x`
  does. The README is the operational document, so there is no ambiguity about
  where to look.
- Add a `LICENSE`. `vesta` has one and this repo does not, which is ordinary
  housekeeping for a public repo rather than a decision.
- The `fides` prerequisite is satisfied.

## Rollback

Before Phase 3 there is nothing to roll back that matters: `~/.config` is
untouched, the new clone can be deleted, and `gh repo rename dotgit` undoes the
rename.

After Phase 3, four paths changed — `~/.config/git`, `~/.config/fish`, the
ghostty stub and `~/.gitignore` — and rollback needs no deletion either: the
migration backup holds the originals, so every step is a move. **The links must
be moved aside before anything is restored over them, or a restore writes
straight through them into the repo working tree.** Moving a link moves the link
itself and never touches its target, measured.

```sh
B=~/Backups/consus-rollback-$(date +%Y%m%dT%H%M%S); mkdir -p "$B"
mv ~/.config/git ~/.config/fish "$B"/
mv ~/.config/ghostty/config.ghostty "$B"/

mv "$BK"/git "$BK"/fish ~/.config/                     # $BK from Phase 3
mv "$BK"/gitignore-home ~/.gitignore                   # core.excludesfile target
mv ~/Developer/LRNZ09/consus/git/config-local ~/Developer/LRNZ09/consus/git/config-work ~/.config/git/
mv ~/Developer/LRNZ09/consus/git/.remember ~/.config/git/
git -C ~/.config/git branch --unset-upstream            # see below
```

`~/.gitignore` has to come back explicitly, and the tarball **cannot** supply it:
that archive is rooted at `~/.config` and this file sits one level up. The
restored `git/config` still points `core.excludesfile` at it, so skipping this
line leaves that setting dangling and stops `.remember/` being ignored
anywhere —
the exposure Phase 1 step 2 exists to avoid. If `$BK` has already been discarded,
recreate the file by copying `git/ignore` out of the repo.

That last line matters. The restored `~/.config/git` is a live checkout whose
remote was repointed in Phase 0 and whose branch tracks a `main` that now
contains the restructure — so it reports itself behind, and a `git pull` there
would redo the migration underneath you. Unsetting the upstream (or removing the
remote outright) stops that. Making it a normal tracking clone again means
reverting the restructure commits on origin first.

If `fides` has been given a `consus` satellite entry by then, disable it
before rolling back, or its `./bin/install --non-interactive` will recreate the
links on the next run.

If the migration backup has already been discarded, the tarball is the fallback
for the same three paths:

```sh
tar xzf ~/Backups/config-backup-<date>.tar.gz -C ~ .config/git .config/fish
```

The published repo can stay; with the links gone, nothing on this machine reads
it — provided no checkout still tracks the restructured branch and nothing calls
`bin/install`.

## What this repo guarantees a provisioner

`fides` is the intended consumer, but nothing here is specific to it. The
contract is four things, and they are all independently justified — none exists
only to serve another repo:

- **`bin/doctor` is a read-only probe.** It exits 0 when the machine matches the
  record and non-zero when it does not, touching nothing either way. That makes
  it usable as the probe half of a probe/apply pattern, which is what keeps
  `--check --diff` truthful in front of a shell-out.
- **`bin/install` is idempotent, and refuses without a TTY unless the decision
  was declared.** A second run is a no-op; `--non-interactive` refuses and
  prints rather than prompting, because a prompt inside an automation step
  hangs it. A declared `--resolve` never prompts either.
- **The clone has an upstream.** Phase 2 pushes with `push -u`, without which
  `git log @{u}..` exits 128 and no caller can tell whether the satellite is
  ahead.
- **The satellite is a plain clone at a real path.** No graft, no `git init` over
  an existing directory, no bare repo: `git clone` to
  `~/Developer/LRNZ09/consus`, then two symlinks and one stub created by
  `bin/install`.

That last point is where `fides`' current spec diverges most, and the divergence
is deeper than a list of edits. Its architecture describes satellites "cloned to
their real paths with no symlink layer", a `consus → ~/.config` graft, and
"adding a newly-configured tool is a gitignore line in `consus`". This design
replaced all three: the satellite lives outside `~/.config`, the symlink layer is
the mechanism rather than something avoided, and adding a tool is a directory plus
an allow-list negation plus a link. Those sections need **rewriting against the
contract above, not patching** — eight bullet edits applied to an architecture
section that describes the superseded shape would leave that document
contradicting itself.

Two things in that spec need attention regardless of this design, and are noted
here only so they are not lost: its `safety` role is already unsatisfiable today,
because `~/.claude` reports `settings.json` as modified whenever Claude Code
rewrites its own tracked file; and its exclusion table calls `acli/` and
`libvirt/` "regenerable state, no settings worth carrying" when both hold
credentials, which invites someone to allow-list them later.

## Deliberately out of scope

- `~/.claude` and `~/.proto` keep their own repos at their real paths.
- `~/.agents` stays with the `dotagents` CLI.
- `zed/` is excluded. Settings-sync extensions for it are in flight, the same
  way VS Code syncs itself, so versioning its config here would compete with the
  mechanism that is about to own it. `~/.config/zed` stays a real directory,
  untracked and unmanaged — and, since the Phase 3 tarball no longer excludes
  anything, still backed up.
- `raycast/` and VS Code are excluded — both sync themselves.
- `~/.hammerspoon` is excluded: `init.lua` is empty.
- `opencode`, `gh` and `micro` are excluded — see "Dropped".
- Credentials are never tracked, and now cannot be: none of them is under any
  path this repo contains. The named set is `gh/hosts.yml`, `sops/`, `gcloud/`,
  `rclone/`, `github-copilot/`, `acli/` and `libvirt/secrets/`, and the list is
  illustrative rather than exhaustive.

## Open items

- The rebuild bootstrap is **documented but untested end to end**, because
  testing it means rebuilding a machine. The gap it closes was real: fisher is
  itself one of the ignored plugin files, so the earlier "just run `fisher update`"
  instruction could not have worked. The sequence is now written out under
  "What is tracked", it needs network, and `bin/doctor` detects the state that
  calls for it. Nothing on this machine is at risk either way.
- Two of the four remaining plugins are pinned to a **moving** major alias
  (`halostatue/fish-macos`, `halostatue/fish-utils-core`), so the same
  commit can materialise different plugin code on different days. This is a
  deliberate loosening, recorded rather than resolved: the pair is referenced by
  nothing in the tracked set and unused in 14 months, so the exposure is bounded.
  Exact pins (`.3.0`, `.3.0`) are a one-line change if that stops being
  acceptable.

`bin/install`'s merge path is no longer an open item — Phase 2 exercises it
against deliberate drift before anything is pushed.
