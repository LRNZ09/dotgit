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

Work/per-directory identity lives in an untracked `config-work` (git-ignored),
loaded via the `[includeIf]` rule in `config`. Copy `config-work.example` to
`config-work` and fill in your details.
