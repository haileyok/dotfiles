# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Ensure nix profile is in PATH (needed on --no-daemon installs)
export PATH="$HOME/.nix-profile/bin:$PATH"

export EDITOR=nvim
export PATH=$PATH:/home/hailey/go/bin
export PATH=$HOME/dotfiles/bin:$PATH

# Fix locale warnings from nix binaries (nix glibc lacks locale data)
export LOCALE_ARCHIVE=~/.nix-profile/lib/locale/locale-archive

# Enable native Wayland for Electron apps (Slack, Discord, Spotify)
export NIXOS_OZONE_WL=1

# Cursor theme for XWayland apps + terminal-launched programs
# (sway itself picks this up via `seat seat0 xcursor_theme` in sway/config;
# this covers apps that read the env vars directly instead)
export XCURSOR_THEME=Bibata-Modern-Classic
export XCURSOR_SIZE=24

# Set SHELL to nix zsh so zellij uses it for panes
export SHELL="$HOME/.nix-profile/bin/zsh"

# Auto-start zellij on SSH login
if [ -n "$SSH_CONNECTION" ] && [ -z "$ZELLIJ" ]; then
    exec "$HOME/.nix-profile/bin/zellij" attach -c main
fi

eval "$(starship init zsh)"

plugins=(
    git
)

# Set-up FZF key bindings (CTRL R for fuzzy history finder)
source <(fzf --zsh)

source ~/.nix-profile/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh
source ~/.nix-profile/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.nix-profile/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

bindkey '^f' autosuggest-accept

# Check archlinux plugin commands here
# https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/archlinux

# Display Pokemon-colorscripts
# Project page: https://gitlab.com/phoneybadger/pokemon-colorscripts#on-other-distros-and-macos
pokemon-colorscripts --no-title -s -r

# fastfetch. Will be disabled if above colorscript was chosen to install
#fastfetch -c $HOME/.config/fastfetch/config-compact.jsonc

# Set-up icons for files/folders in terminal
#alias ls='eza -a --icons'
#alias ll='eza -al --icons'
#alias lt='eza -a --tree --level=1 --icons'

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory

alias gco='git checkout'
alias gcrt='git checkout -b'
alias gc='git commit -m'
alias gca='git commit -am'
alias gcurr='git rev-parse HEAD'
alias gcurrcp='git rev-parse HEAD | wl-copy'
alias gpr='gh pr create'
alias gs='git status'
alias gd='git pull'
alias diff='git diff'
alias ga='git add'
alias gp='git pull'

alias tswitch='sudo tailscale switch'
alias ts='sudo tailscale'

alias ghwc='watch -n 3 gh pr checks'
alias ghc='gh pr checks'
alias ghco='gh pr checkout'
alias codes='ykman oath accounts code'
alias doaws='eval $(~/bsky/bsky-infra/scripts/aws-setup-env default)'

alias n=nvim

# Power profile shortcuts (laptops only, requires power-profiles-daemon)
alias pps='power-profiles.sh status'
alias ppp='power-profiles.sh performance'
alias ppb='power-profiles.sh balanced'
alias ppsv='power-profiles.sh power-saver'

alias ylq='yarn lint --quiet'

alias sag='eval `ssh-agent -s` && ssh-add'

alias pubip='curl ipv4.icanhazip.com'

alias lsl='ls -l'

alias geoip='uv run --project /home/hailey/bsky/ipres /home/hailey/bsky/ipres/main.py'

alias cat='bat'

# source /usr/share/nvm/init-nvm.sh
# source /etc/profile.d/google-cloud-cli.sh

LC_ADDRESS=en_US.UTF-8
LC_NAME=en_US.UTF-8
LC_MONETARY=en_US.UTF-8
LC_PAPER=en_US.UTF-8
LC_IDENTIFICATION=en_US.UTF-8
LC_TELEPHONE=en_US.UTF-8
LC_MEASUREMENT=en_US.UTF-8
LC_TIME=en_US.UTF-8
LC_NUMERIC=en_US.UTF-8
export LC_ALL=en_US.UTF-8

export YUBIKEY_ACCOUNT=aws

export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/tools

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
# __conda_setup="$('/usr/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
# if [ $? -eq 0 ]; then
#     eval "$__conda_setup"
# else
#     if [ -f "/usr/etc/profile.d/conda.sh" ]; then
#         . "/usr/etc/profile.d/conda.sh"
#     else
#         export PATH="/usr/bin:$PATH"
#     fi
# fi
# unset __conda_setup
# <<< conda initialize <<<
