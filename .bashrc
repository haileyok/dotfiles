# If zsh is available via nix, hand off to it on interactive SSH login.
# zsh will then source .zshrc which auto-starts zellij.
# Only for interactive shells: bash also reads this file for non-interactive
# SSH sessions (ssh host 'cmd', scp, sftp, rsync), and exec'ing zsh there
# drops the command, so the session exits 0 with no output.
if [ -n "$SSH_CONNECTION" ] && [ -z "$ZSH_VERSION" ] && [[ $- == *i* ]]; then
    if [ -x "$HOME/.nix-profile/bin/zsh" ]; then
        exec "$HOME/.nix-profile/bin/zsh" -l
    fi
fi
. "/home/pelican/.deno/env"
