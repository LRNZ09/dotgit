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
