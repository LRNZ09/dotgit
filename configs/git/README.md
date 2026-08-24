# git

My global Git configuration. Through `~/.config/git` — a symlink into this
repo's `configs/git`, created by [`../../bin/install`](../../bin/install) — Git
reads `config` here as its global config file and `ignore` as its global
excludes file. Neither needs an `[include]` line or a `core.excludesfile`
setting: both are Git's own default paths, and the link is what makes them
resolve here.

Because this *is* the global config, anything that writes to it — `git config
--global`, `gh auth setup-git`, `git-credential-manager configure` — shows up
as a worktree modification of `configs/git/config`. A machine that has drifted
from the record says so in `git status`.

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
symlink: see the [repo README](../../README.md).
