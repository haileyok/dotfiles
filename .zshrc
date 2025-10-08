# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export PATH=$PATH:/home/hailey/go/bin

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="Soliah"

plugins=(
    git
    archlinux
)

export RPS1=''

source $ZSH/oh-my-zsh.sh
source /usr/share/zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Check archlinux plugin commands here
# https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/archlinux

# Display Pokemon-colorscripts
# Project page: https://gitlab.com/phoneybadger/pokemon-colorscripts#on-other-distros-and-macos
pokemon-colorscripts --no-title -s -r

# fastfetch. Will be disabled if above colorscript was chosen to install
#fastfetch -c $HOME/.config/fastfetch/config-compact.jsonc

# Set-up icons for files/folders in terminal
alias ls='eza -a --icons'
alias ll='eza -al --icons'
alias lt='eza -a --tree --level=1 --icons'

# Set-up FZF key bindings (CTRL R for fuzzy history finder)
source <(fzf --zsh)

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

alias tswitch='sudo tailscale switch'
alias ts='sudo tailscale'o

alias ghwc='watch -n 3 gh pr checks'
alias ghc='gh pr checks'
alias ghco='gh pr checkout'
alias codes='ykman oath accounts code'
alias doaws='eval $(~/bsky/bsky-infra/scripts/aws-setup-env default)'

alias n=nvim

alias ylq='yarn lint --quiet'

alias sag='eval `ssh-agent -s` && ssh-add'

alias pubip='curl ipv4.icanhazip.com'

alias lsl='ls -l'

source /usr/share/nvm/init-nvm.sh
source /etc/profile.d/google-cloud-cli.sh

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
__conda_setup="$('/usr/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/usr/etc/profile.d/conda.sh" ]; then
        . "/usr/etc/profile.d/conda.sh"
    else
        export PATH="/usr/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<
