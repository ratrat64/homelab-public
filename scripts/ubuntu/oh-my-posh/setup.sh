#!/bin/bash
# =============================================================================
# oh-my-posh setup script — Ubuntu
# Usage:
#   ./setup.sh          — set up oh-my-posh (prompts for sudo if needed)
#   ./setup.sh --verbose — show full apt output
# =============================================================================

set -e

VERBOSE=false
if [[ "$1" == "--verbose" || "$1" == "-v" ]]; then
    VERBOSE=true
fi

# --- Colors ------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()   { echo -e "${GREEN}[DONE]${NC}  $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }

# Run apt-get, escalating to sudo when not root
APT() {
    if [[ $EUID -ne 0 ]]; then
        sudo apt-get "$@"
    else
        apt-get "$@"
    fi
}

# =============================================================================
# STEP 1 — Apt update & required packages
# =============================================================================
log "Updating package index..."
if $VERBOSE; then
    APT update
else
    APT update -qq
fi
ok "Package index updated"

REQUIRED_DEPS=(curl unzip coreutils)
MISSING=()
for pkg in "${REQUIRED_DEPS[@]}"; do
    if ! dpkg -s "$pkg" > /dev/null 2>&1; then
        MISSING+=("$pkg")
    fi
done

# realpath and dirname are provided by coreutils — check the binaries too
for bin in realpath dirname; do
    if ! command -v "$bin" > /dev/null 2>&1; then
        if ! dpkg -s coreutils > /dev/null 2>&1; then
            MISSING+=("coreutils")
        fi
        break
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    log "Installing required packages: ${MISSING[*]}"
    if $VERBOSE; then
        APT install -y "${MISSING[@]}"
    else
        APT install -y "${MISSING[@]}" > /dev/null
    fi
    ok "Required packages installed"
else
    ok "All required packages already present"
fi

# =============================================================================
# STEP 2 — Install oh-my-posh
# =============================================================================
if command -v oh-my-posh > /dev/null 2>&1; then
    ok "oh-my-posh already installed ($(oh-my-posh --version)), skipping install"
else
    log "Running oh-my-posh install script..."
    curl -s https://ohmyposh.dev/install.sh | bash -s
    ok "oh-my-posh installed"
fi

# =============================================================================
# STEP 3 — Add oh-my-posh init to bashrc
# =============================================================================
BASHRC="$HOME/.bashrc"
OMP_LINE="eval \"\$(oh-my-posh init bash --config 'https://raw.githubusercontent.com/ratrat64/homelab-public/refs/heads/main/scripts/ubuntu/oh-my-posh/configs/clean-detailed-custom.yaml')\""

if [[ "$SHELL" != *bash ]]; then
    warn "Default shell is not bash ($SHELL). Adding bash config anyway; switch to bash to use oh-my-posh."
fi

LOCAL_BIN='export PATH="$HOME/.local/bin:$PATH"'

# Add PATH export if missing (must come before the eval line below)
if ! grep -qF 'HOME/.local/bin' "$BASHRC" 2>/dev/null; then
    {
        echo ""
        echo "# add user's private bin to PATH for non-login shells"
        echo "$LOCAL_BIN"
    } >> "$BASHRC"
    ok "\$HOME/.local/bin added to PATH in $BASHRC"
else
    ok "\$HOME/.local/bin already on PATH in $BASHRC"
fi

# Add oh-my-posh init if missing
if grep -q 'oh-my-posh init bash' "$BASHRC" 2>/dev/null; then
    ok "oh-my-posh already configured in $BASHRC, skipping"
else
    {
        echo ""
        echo "# oh my posh"
        echo "$OMP_LINE"
    } >> "$BASHRC"
    ok "oh-my-posh init added to $BASHRC"
fi

# Fix ordering: if the PATH export ended up after the eval line (e.g. from a
# previous version of this script), move it just before the eval line so the
# eval can actually find oh-my-posh.
if grep -q 'oh-my-posh init bash' "$BASHRC" 2>/dev/null; then
    EVAL_LINE=$(grep -n 'oh-my-posh init bash' "$BASHRC" | head -1 | cut -d: -f1)
    BIN_LINE=$(grep -nF 'HOME/.local/bin' "$BASHRC" | head -1 | cut -d: -f1)
    if [[ -n "$EVAL_LINE" && -n "$BIN_LINE" && "$BIN_LINE" -gt "$EVAL_LINE" ]]; then
        log "PATH export is after the eval line; reordering..."
        awk -v ins="$LOCAL_BIN" '
            /oh-my-posh init bash/ && !done { print ins; done=1 }
            { if ($0 == ins && !skipped) { skipped=1; next } print }
        ' "$BASHRC" > "$BASHRC.tmp" && mv "$BASHRC.tmp" "$BASHRC"
        ok "PATH export moved before oh-my-posh init"
    fi
fi

# =============================================================================
# STEP 4 — Desktop: install Recursive Nerd Font & set terminal default
# =============================================================================
FONT_URL='https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.0/Recursive.zip'
FONT_FAMILY='RecMonoCasual Nerd Font'
FONT_WEIGHT='Bold'
FONT_SIZE=10
FONT_SPEC="$FONT_FAMILY $FONT_WEIGHT $FONT_SIZE"
FONT_PATTERN='RecMonoCasualNerdFont-*.ttf'
FONT_DIR="$HOME/.local/share/fonts"

is_desktop() {
    [[ "$(systemctl get-default 2>/dev/null)" == "graphical.target" ]] && return 0
    compgen -G "/usr/share/xsessions/*.desktop" > /dev/null && return 0
    dpkg -s ubuntu-desktop > /dev/null 2>&1 && return 0
    return 1
}

if is_desktop; then
    ok "Desktop system detected"
    # ---- Install font if missing ---------------------------------------------
    if fc-list | grep -qi "$FONT_FAMILY"; then
        ok "Font '$FONT_FAMILY' already installed"
    else
        log "Downloading Recursive Nerd Font..."
        TMPDIR_FONT=$(mktemp -d)
        curl -Ls -o "$TMPDIR_FONT/recursive.zip" "$FONT_URL"
        log "Extracting font to $FONT_DIR..."
        mkdir -p "$FONT_DIR"
        unzip -oq "$TMPDIR_FONT/recursive.zip" "$FONT_PATTERN" -d "$FONT_DIR"
        rm -rf "$TMPDIR_FONT"
        fc-cache -f > /dev/null 2>&1
        if fc-list | grep -qi "$FONT_FAMILY"; then
            ok "Font '$FONT_FAMILY' installed"
        else
            warn "Font installation could not be verified; you may need to log out/in"
        fi
    fi

    # ---- Set as terminal default font (detect the installed one) ----
    if command -v ptyxis > /dev/null 2>&1 || dpkg -s ptyxis > /dev/null 2>&1; then
        log "Configuring Ptyxis to use '$FONT_FAMILY'..."
        if gsettings set org.gnome.Ptyxis use-system-font false &&
           gsettings set org.gnome.Ptyxis font-name "$FONT_SPEC"; then
            ok "Ptyxis default font set to '$FONT_SPEC'"
        else
            warn "Could not set Ptyxis font (no D-Bus session?). Log into the desktop first and re-run."
        fi
    elif command -v gnome-terminal > /dev/null 2>&1 || command -v gnome-terminal.real > /dev/null 2>&1; then
        PROFILE=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
        if [[ -n "$PROFILE" ]]; then
            log "Configuring GNOME Terminal to use '$FONT_FAMILY'..."
            PROFILE_PATH="/org/gnome/terminal/legacy/profiles:/:$PROFILE/"
            if gsettings set "org.gnome.Terminal.Legacy.Profile:$PROFILE_PATH" use-system-font false &&
               gsettings set "org.gnome.Terminal.Legacy.Profile:$PROFILE_PATH" font "$FONT_SPEC"; then
                ok "GNOME Terminal default font set to '$FONT_SPEC'"
            else
                warn "Could not set GNOME Terminal font (no D-Bus session?). Log into the desktop first and re-run."
            fi
        else
            warn "GNOME Terminal found but no default profile configured — skipping terminal font config."
        fi
    else
        warn "No Ptyxis or GNOME Terminal found — skipping terminal font config."
    fi
else
    warn "Server/system without a graphical desktop detected — skipping font install and terminal config"
fi

echo ""
ok "Setup complete! Run 'source ~/.bashrc' or restart your terminal to activate oh-my-posh."