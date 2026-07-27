# If zsh is available, hand off to it on SSH login
# zsh will then source .zshrc which auto-starts zellij
if [ -n "$SSH_CONNECTION" ] && [ -z "$ZSH_VERSION" ]; then
    if command -v zsh >/dev/null 2>&1; then
        exec zsh -l
    fi
fi
