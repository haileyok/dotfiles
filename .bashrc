# If zsh is available via nix, hand off to it on SSH login
# zsh will then source .zshrc which auto-starts zellij
if [ -n "$SSH_CONNECTION" ] && [ -z "$ZSH_VERSION" ]; then
    if [ -x "$HOME/.nix-profile/bin/zsh" ]; then
        exec "$HOME/.nix-profile/bin/zsh" -l
    fi
fi
