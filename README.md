# consus

The configuration this machine's tools actually read. It lives under `configs/`,
one directory per tool, and each tool finds it at its own default path, which is
a symlink into this repo:

```text
~/.config/git   →  <this clone>/configs/git
~/.config/fish  →  <this clone>/configs/fish
```

Ghostty is the exception. Its winning config path on macOS is
`~/Library/Application Support/com.mitchellh.ghostty/config`, which no symlink
under `~/.config` can outrank, so it gets a one-line `config-file` include at
`~/.config/ghostty/config.ghostty`, naming `configs/ghostty/config.ghostty`
here — written by `bin/install`.

## What is here

- **configs/git** — the global config, its two per-machine examples, and
  `ignore`, which is git's own default global excludes path.
- **configs/fish** — the hand-written configuration only: `config.fish`,
  `fish_plugins`, three files under `conf.d/` and one function. Everything
  fisher or a tool generated is ignored on purpose — `fish_plugins` is the
  record, and those 82 plugin files are its build output.
- **configs/ghostty** — four settings, plus an optional per-machine include.

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

Each path is named by the tool that owns it — `fish`, `git` — on the command
line, under `~/.config` and in the backup directory alike. Only the repo side
carries the `configs/` prefix.

## Per-machine settings

- **git** — `configs/git/config-local`, untracked and included last, so it wins.
  Copy it from `configs/git/config-local.example`. Work identity goes in
  `configs/git/config-work`, which loads only inside `~/Developer/work/`; for
  that to match, that directory must be real all the way down and work repos
  must physically live inside it.
- **fish** — any new `conf.d/*.fish` file is machine-local by default: the
  allow-list in `.gitignore` ignores everything under `configs/fish/` it does
  not name. `bin/doctor` reports such a file, which is the only way it becomes
  visible.
- **ghostty** — `~/.config/ghostty/local.ghostty`. The repo's config ends with
  an optional include of it, so a machine without one loads nothing and says
  nothing.

## The hazard of a linked directory

`~/.config/git` and `~/.config/fish` are symlinks **into this repo**, so
anything that writes through them writes here. In particular,
`rm -rf ~/.config/fish/` — with the trailing slash — follows the link and
empties this repo's `configs/fish/` directory. `git restore` brings back the six
tracked files; the other 91 need `fisher update` (which needs network), a tool
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
