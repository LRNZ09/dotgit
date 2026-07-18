# dotgit

My global Git configuration (`~/.config/git`).

## Setup

Point Git at this directory, then enable the secret-scanning hook (Git does not
run cloned hooks automatically):

```sh
git config core.hooksPath .githooks
```

The hook needs [gitleaks](https://github.com/gitleaks/gitleaks): `brew install gitleaks`.

## Secret scanning

- **Pre-commit hook** (`.githooks/pre-commit`) runs gitleaks on staged changes and
  blocks commits containing secrets or non-noreply email addresses. Override in a
  pinch with `git commit --no-verify`.
- **CI** (`.github/workflows/gitleaks.yml`) re-scans on every push/PR as a backstop
  that `--no-verify` can't bypass.
- Rules live in `.gitleaks.toml`.

## Per-machine identity

Signing keys and identities differ per machine, so they live in untracked files
(git-ignored) loaded via `include` rules in `config`. Git silently skips a
missing include, so each machine only sets what it needs.

- **Signing key** — copy `config-local.example` to `config-local` and set your
  key. Loaded unconditionally, so it applies everywhere by default.
- **Work/per-directory identity** — copy `config-work.example` to `config-work`
  and fill in your details. Loaded via the `[includeIf "gitdir:…"]` rule, which
  is applied after `config-local` and so overrides it inside work directories.
