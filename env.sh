#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect distribution
detect_distro() {
    if command -v pacman >/dev/null 2>&1; then
        echo "Arch"
    elif command -v apt >/dev/null 2>&1; then
        echo "Ubuntu"
    else
        error "Unsupported distribution. Only Arch Linux and Ubuntu are supported."
        exit 1
    fi
}

# Install packages based on distro
install_packages() {
    local distro="$1"
    local packages="curl wget git unzip"

    log "Installing base packages for $distro..."

    case "$distro" in
        "Arch")
            sudo pacman -Sy --noconfirm $packages
            ;;
        "Ubuntu")
            sudo apt update
            sudo apt install -y $packages
            ;;
    esac
}

# Install Starship
install_starship() {
    log "Installing Starship..."

    if command -v starship >/dev/null 2>&1; then
        warn "Starship already installed, skipping..."
        return 0
    fi

    curl -sS https://starship.rs/install.sh | sh -s -- -y

    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.cargo/bin:"* ]]; then
        echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    fi
}

# Setup Starship config
setup_starship_config() {
    log "Setting up Starship configuration..."

    mkdir -p ~/.config

    # Create a basic starship config - you can customize this
    cat > ~/.config/starship.toml << 'EOF'
# Starship configuration
add_newline = false

format = '''
╭─── $username@$hostname$directory$git_commit$git_state$git_metrics$git_status
╰─$character '''

right_format = '$nodejs$git_branch$git_commit$git_state$git_metrics$git_status'

[username]
format = '[$user]($style) '
style_user = 'green bold'
style_root = 'red bold'
show_always = true

[hostname]
ssh_only = false
format = ' [$hostname]($style) '
style = 'blue bold'

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"

[nodejs]
format = '[ $version](bold green) '

[git_branch]
format = '[$symbol$branch(:$remote_branch)]($style)'
EOF
}

# Install Docker
install_docker() {
    log "Installing Docker..."

    if command -v docker >/dev/null 2>&1; then
        warn "Docker already installed, skipping..."
        return 0
    fi

    local distro="$1"

    case "$distro" in
        "Arch")
            sudo pacman -Sy --noconfirm docker docker-compose
            ;;
        "Ubuntu")
            sudo apt update
            sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt update
            sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
    esac

    # Enable and start Docker service
    sudo systemctl enable docker
    sudo systemctl start docker

    # Add current user to docker group
    sudo usermod -aG docker "$USER"
    
    log "Docker installed. You may need to log out and back in for group changes to take effect."
}

# Install NVM
install_nvm() {
    log "Installing NVM..."

    if [[ -d "$HOME/.nvm" ]] || command -v nvm >/dev/null 2>&1; then
        warn "NVM already installed, skipping..."
        return 0
    fi

    # Get latest NVM version from GitHub API
    log "Fetching latest NVM version..."
    LATEST_NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "$LATEST_NVM_VERSION" ]]; then
        error "Failed to fetch latest NVM version, falling back to v0.39.0"
        LATEST_NVM_VERSION="v0.39.0"
    fi
    
    log "Installing NVM $LATEST_NVM_VERSION..."

    # Download and install NVM
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/$LATEST_NVM_VERSION/install.sh" | bash

    # ADD NVM LINES TO BASHRC AFTER INSTALLATION
    log "Adding NVM configuration to bashrc..."
    cat >> ~/.config/bash/bashrc << 'EOF'

# NVM for Node.js version management
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF

    # Source NVM immediately for this session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"

    log "NVM installed. Installing latest LTS Node.js..."
    
    # Install latest LTS Node.js
    if command -v nvm >/dev/null 2>&1; then
        set +u
        nvm install --lts
        nvm use --lts
        nvm alias default lts/*
        set -u
    fi
}

# Install z.sh
install_z() {
    log "Installing z.sh..."

    mkdir -p ~/.scripts/z
    curl -fsSL https://raw.githubusercontent.com/rupa/z/master/z.sh > ~/.scripts/z/z.sh
    chmod +x ~/.scripts/z/z.sh
}

# Setup bash configuration with XDG structure
setup_bash_config() {
    log "Setting up bash configuration with XDG structure..."

    # Create XDG directories
    mkdir -p ~/.config/bash

    # Backup existing configs
    for file in ~/.bashrc ~/.bash_profile ~/.profile; do
        if [[ -f "$file" ]]; then
            cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
        fi
    done

    # Create ~/.bashrc that sources from ~/.config/bash (like .zshenv)
    cat > ~/.bashrc << 'EOF'
# XDG Base Directory compliance
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# Environment variables
export HISTFILE="$XDG_CONFIG_HOME/bash/history"
export HISTSIZE=1000
export SAVEHIST=1000
export EDITOR="nano"
export VISUAL="nano"

# Source bash configuration from XDG config directory
if [[ -f "$XDG_CONFIG_HOME/bash/bashrc" ]]; then
    source "$XDG_CONFIG_HOME/bash/bashrc"
fi
EOF

    # Create the main bash config file WITHOUT NVM LINES
    cat > ~/.config/bash/bashrc << 'EOF'
# Main bash configuration
# This file is sourced by ~/.bashrc

# Additional history settings
export HISTCONTROL=ignoreboth:erasedups

# Bash options
shopt -s histappend
shopt -s checkwinsize
shopt -s globstar 2>/dev/null || true
shopt -s failglob 2>/dev/null || true
shopt -s autocd
shopt -s cdspell
shopt -s dirspell

# Create history file if it doesn't exist
mkdir -p "$(dirname "$HISTFILE")"
touch "$HISTFILE"

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# Source additional config files
[[ -f "$XDG_CONFIG_HOME/bash/aliases" ]] && source "$XDG_CONFIG_HOME/bash/aliases"
[[ -f "$XDG_CONFIG_HOME/bash/functions" ]] && source "$XDG_CONFIG_HOME/bash/functions"
[[ -f "$XDG_CONFIG_HOME/bash/prompt" ]] && source "$XDG_CONFIG_HOME/bash/prompt"

# z.sh for smart directory jumping
if [[ -f ~/.scripts/z/z.sh ]]; then
    source ~/.scripts/z/z.sh
fi
EOF

    # Create aliases file
    cat > ~/.config/bash/aliases << 'EOF'
# Bash aliases

# ls aliases
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias ls='ls -h --color=auto --group-directories-first'

# grep with color
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Useful shortcuts
alias h='history'
alias j='jobs -l'
alias which='type -a'
alias du='du -kh'
alias df='df -kTh'

# Git shortcuts (if git is available)
if command -v git >/dev/null 2>&1; then
    alias gs='git status'
    alias ga='git add'
    alias gc='git commit'
    alias gp='git push'
    alias gl='git pull'
    alias gd='git diff'
    alias gb='git branch'
    alias gco='git checkout'
fi
EOF

    # Create functions file
    cat > ~/.config/bash/functions << 'EOF'
# Bash functions

# Create directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Extract various archive formats
extract() {
    if [[ -f "$1" ]]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar x "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Find files by name
ff() {
    find . -type f -name "*$1*" 2>/dev/null
}

# Find directories by name
fd() {
    find . -type d -name "*$1*" 2>/dev/null
}

# Quick grep in current directory
qgrep() {
    grep -r --include="*.txt" --include="*.md" --include="*.py" --include="*.sh" --include="*.js" --include="*.html" --include="*.css" "$1" .
}
EOF

    # Create prompt configuration
    cat > ~/.config/bash/prompt << 'EOF'
# Bash prompt configuration

# Color-aware prompt using custom color scheme
if [[ "$TERM" == "linux" ]]; then
    # TTY console - restore custom color palette first
    printf '\e]P01c2023\e]P1c7ae95\e]P295c7ae\e]P3aec795\e]P4ae95c7\e]P5c795ae\e]P695aec7\e]P7c7ccd1\e]P8747c84\e]P9c7ae95\e]PAaec795\e]PBae95c7\e]PCc795ae\e]PD95aec7\e]PEf3f4f5\e]PFf3f4f5'
    
    if [[ $EUID -eq 0 ]]; then
        # Root prompt - use red (color1: warm red-brown)
        PS1='\[\033[01;31m\]╭─[\[\033[01;33m\]\u\[\033[01;31m\]@\[\033[01;33m\]\h\[\033[01;31m\]:\[\033[01;36m\]\w\[\033[01;31m\]]\n╰─\[\033[01;31m\]>\[\033[00m\] '
    else
        # User prompt - use green/cyan (colors 2&6: soft green/blue)  
        PS1='\[\033[01;36m\]╭─[\[\033[01;32m\]\u\[\033[01;36m\]@\[\033[01;32m\]\h\[\033[01;36m\]:\[\033[01;33m\]\w\[\033[01;36m\]]\n╰─\[\033[01;32m\]>\[\033[00m\] '
    fi
else
    # Terminal emulator - use Starship if available
    if command -v starship >/dev/null 2>&1; then
        eval "$(starship init bash)"
    else
        # Fallback prompt for terminal emulators
        if [[ $EUID -eq 0 ]]; then
            PS1='\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\# '
        else
            PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
        fi
    fi
fi
EOF

    log "Created XDG-compliant bash configuration structure:"
    log "  ~/.bashrc (bootstrap file)"
    log "  ~/.config/bash/bashrc (main config)"
    log "  ~/.config/bash/aliases"
    log "  ~/.config/bash/functions"
    log "  ~/.config/bash/prompt"
    log "  ~/.config/bash/history (will be created on first use)"
}

# Setup root configuration
setup_root_config() {
    log "Setting up root configuration..."

    # Copy starship config to root
    sudo mkdir -p /root/.config
    sudo cp ~/.config/starship.toml /root/.config/

    # Copy z.sh to root
    sudo mkdir -p /root/.scripts/z
    if [[ -f ~/.scripts/z/z.sh ]]; then
        sudo cp ~/.scripts/z/z.sh /root/.scripts/z/
    else
        warn "z.sh not found in ~/.scripts/z/, skipping copy to root"
    fi

    # Copy bash config structure to root
    sudo mkdir -p /root/.config/bash
    sudo cp ~/.config/bash/* /root/.config/bash/

    # Create root's ~/.bashrc
    sudo tee /root/.bashrc >/dev/null << 'EOF'
# XDG Base Directory compliance
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# Environment variables
export HISTFILE="$XDG_CONFIG_HOME/bash/history"
export HISTSIZE=1000
export SAVEHIST=1000
export EDITOR="nano"
export VISUAL="nano"

# Source bash configuration from XDG config directory
if [[ -f "$XDG_CONFIG_HOME/bash/bashrc" ]]; then
    source "$XDG_CONFIG_HOME/bash/bashrc"
fi
EOF

    # Add root-specific safety aliases to root's aliases file
    sudo tee -a /root/.config/bash/aliases >/dev/null << 'EOF'

# Root-specific safety aliases
alias chown='chown --preserve-root'
alias chmod='chmod --preserve-root'
alias chgrp='chgrp --preserve-root'
EOF
}

setup_tty_colors() {
    log "Setting up custom TTY color scheme..."
    
    # Extract RGB values from hex colors
    # Original scheme:
    # Background: #1c2023 (28, 32, 35)
    # Foreground: #c7ccd1 (199, 204, 209)
    # Colors 0-15 from your Xresources
    
    # Configure console colors via kernel parameters
    sudo tee /etc/default/grub.d/99-console-colors.cfg >/dev/null << 'EOF'
# Custom color scheme for TTY console
# Based on XResources configuration
# Format: vt.default_red=c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15
# Colors: black, red, green, yellow, blue, magenta, cyan, white, bright_black, bright_red, bright_green, bright_yellow, bright_blue, bright_magenta, bright_cyan, bright_white

GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT vt.default_red=28,199,149,174,174,199,149,199,116,199,149,174,174,199,149,243"
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT vt.default_grn=32,174,199,199,149,149,174,204,124,174,199,199,149,149,174,244"
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT vt.default_blu=35,149,174,149,199,174,199,209,132,149,174,149,199,174,199,245"
EOF

    # Update GRUB configuration
    sudo update-grub
    
    log "Console colors will be applied after reboot"
}

setup_tty_font() {
    log "Configuring console font..."
    sudo tee /etc/default/console-setup >/dev/null << 'EOF'
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="Lat15"
FONTFACE="Terminus"
FONTSIZE="8x16"
EOF
    # Apply the font settings immediately
    sudo setupcon
}

# Main execution
main() {
    echo -e "${BLUE}=== Environment Setup Script ===${NC}"
    echo

    # Detect distribution
    DISTRO=$(detect_distro)
    log "Detected distribution: $DISTRO"

    # Install base packages
    install_packages "$DISTRO"

    # Install Starship
    install_starship
    setup_starship_config

    # Install z.sh
    install_z

    # Setup bash configuration FIRST (without NVM)
    setup_bash_config

    # Setup TTY colors and font for base TTY
    setup_tty_colors
    setup_tty_font

    # Optional: Install Docker
    read -p "Install Docker? [y/N]: " install_docker_choice
    if [[ "$install_docker_choice" =~ ^[Yy]$ ]]; then
        install_docker "$DISTRO"
    fi

    # Optional: Install NVM (this will append NVM lines to bashrc)
    read -p "Install NVM (Node Version Manager)? [y/N]: " install_nvm_choice
    if [[ "$install_nvm_choice" =~ ^[Yy]$ ]]; then
        install_nvm
    fi

    # Setup root configuration
    read -p "Setup root configuration as well? [y/N]: " setup_root
    if [[ "$setup_root" =~ ^[Yy]$ ]]; then
        setup_root_config
    fi

    echo
    log "Environment setup complete!"
    echo -e "${GREEN}Next steps:${NC}"
    echo "1. Reload your shell: source ~/.bashrc"
    echo "2. Start using 'z' to jump to frequently used directories"
    echo "3. Your bash config is now organized in ~/.config/bash/"
    echo
    echo -e "${BLUE}Configuration structure:${NC}"
    echo "  ~/.bashrc (bootstrap)"
    echo "  ~/.config/bash/bashrc (main config)"
    echo "  ~/.config/bash/aliases"
    echo "  ~/.config/bash/functions"
    echo "  ~/.config/bash/prompt"
    echo "  ~/.config/bash/history"
    echo
    echo -e "${BLUE}Enjoy your new environment!${NC}"
}

# Run main function
main "$@"