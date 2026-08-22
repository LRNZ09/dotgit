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
