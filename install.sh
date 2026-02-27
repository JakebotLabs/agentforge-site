#!/bin/bash
# AgentForge Installer — One-Command End-to-End Setup
# Usage: curl -fsSL https://agentsforge.dev/install.sh | bash
#
# Options (env vars):
#   AGENTFORGE_HOME     Install path (default: ~/.agentforge)
#   AGENTFORGE_QUIET    Set to 1 to suppress output
#   INSTALL_OPENCLAW    Set to 1 to force OpenClaw install in CI mode
#
# Flags:
#   --mailbox         Also clone agent-mailbox for multi-agent coordination
#   --upgrade         Force upgrade existing installation
#   --help            Show this help

set -euo pipefail

AGENTFORGE_HOME="${AGENTFORGE_HOME:-$HOME/.agentforge}"
REPO_URL="https://github.com/JakebotLabs/agentforge.git"
MAILBOX_URL="https://github.com/JakebotLabs/agent-mailbox.git"
MAILBOX_PATH="$HOME/.openclaw/mailbox"
MIN_PYTHON_MINOR=10   # Python 3.10+ required

# Parse flags
INSTALL_MAILBOX=false
FORCE_UPGRADE=false
for arg in "$@"; do
    case "$arg" in
        --mailbox)   INSTALL_MAILBOX=true ;;
        --upgrade)   FORCE_UPGRADE=true ;;
        --help|-h)
            echo "AgentForge Installer"
            echo ""
            echo "Usage: curl -fsSL https://agentsforge.dev/install.sh | bash [-s -- OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --mailbox   Also install agent-mailbox for multi-agent coordination"
            echo "  --upgrade   Force upgrade existing installation"
            echo "  --help      Show this help"
            echo ""
            echo "Environment variables:"
            echo "  AGENTFORGE_HOME      Install path (default: ~/.agentforge)"
            echo "  INSTALL_OPENCLAW     Set to 1 to install OpenClaw in CI mode"
            exit 0
            ;;
    esac
done

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "  ${GREEN}✅${RESET} $1"; }
warn() { echo -e "  ${YELLOW}⚠️ ${RESET} $1"; }
fail() { echo -e "  ${RED}❌${RESET} $*"; exit 1; }
info() { echo -e "  ${BLUE}→${RESET}  $1"; }

echo ""
echo -e "${BOLD}⚒️  AgentForge Installer${RESET}"
echo "════════════════════════════════════════"
echo ""

# ── 1. Auto-install prerequisites ────────────────────────────
install_prerequisites() {
    if command -v apt-get &>/dev/null; then
        info "Checking prerequisites (Ubuntu/Debian)..."
        sudo apt-get update -qq 2>/dev/null

        # git
        if ! command -v git &>/dev/null; then
            info "Installing git..."
            sudo apt-get install -y -qq git
        fi

        # Python 3.10+ check; install 3.12 via deadsnakes if needed
        PYTHON_CMD=""
        for cmd in python3.12 python3.11 python3.10 python3; do
            if command -v "$cmd" &>/dev/null; then
                _minor=$("$cmd" -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo "0")
                _major=$("$cmd" -c "import sys; print(sys.version_info.major)" 2>/dev/null || echo "0")
                if [[ "$_major" -eq 3 && "$_minor" -ge "$MIN_PYTHON_MINOR" ]]; then
                    PYTHON_CMD="$cmd"
                    break
                fi
            fi
        done

        if [[ -z "$PYTHON_CMD" ]]; then
            info "Installing Python 3.12 (via deadsnakes PPA)..."
            sudo apt-get install -y -qq software-properties-common
            sudo add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null
            sudo apt-get update -qq 2>/dev/null
            sudo apt-get install -y -qq python3.12 python3.12-venv python3.12-distutils 2>/dev/null || \
                sudo apt-get install -y -qq python3.12 python3.12-venv
            # Make python3 resolve to 3.12
            sudo update-alternatives --install /usr/local/bin/python3 python3 "$(which python3.12)" 1 2>/dev/null || true
            PYTHON_CMD="python3.12"
        fi

        # venv module
        if ! "$PYTHON_CMD" -c "import venv" &>/dev/null; then
            info "Installing python venv..."
            VER=$("$PYTHON_CMD" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
            sudo apt-get install -y -qq "python${VER}-venv" 2>/dev/null || \
                sudo apt-get install -y -qq python3-venv
        fi

        # pip
        if ! "$PYTHON_CMD" -m pip --version &>/dev/null 2>&1; then
            info "Installing pip..."
            sudo apt-get install -y -qq python3-pip
        fi

        # Node.js 20.x (via NodeSource if npm missing)
        if ! command -v npm &>/dev/null; then
            info "Installing Node.js 20.x..."
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null 2>&1
            sudo apt-get install -y -qq nodejs
        fi

        ok "Prerequisites ready"

    elif command -v brew &>/dev/null; then
        # macOS — guide user but continue
        warn "macOS detected. Checking for required tools..."

        # Set PYTHON_CMD for macOS
        PYTHON_CMD=""
        for cmd in python3.12 python3.11 python3.10 python3; do
            if command -v "$cmd" &>/dev/null; then
                _minor=$("$cmd" -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo "0")
                _major=$("$cmd" -c "import sys; print(sys.version_info.major)" 2>/dev/null || echo "0")
                if [[ "$_major" -eq 3 && "$_minor" -ge "$MIN_PYTHON_MINOR" ]]; then
                    PYTHON_CMD="$cmd"
                    break
                fi
            fi
        done

        local missing=()
        command -v git &>/dev/null || missing+=("git")
        [[ -z "$PYTHON_CMD" ]] && missing+=("python@3.12")
        command -v npm &>/dev/null || missing+=("node")

        if [[ ${#missing[@]} -gt 0 ]]; then
            echo ""
            warn "Missing required tools. Please install with Homebrew:"
            warn "  brew install ${missing[*]}"
            echo ""
            fail "Please install missing prerequisites and re-run the installer."
        fi

        ok "Prerequisites ready (macOS)"

    else
        echo ""
        fail "Unsupported OS. Please install manually:\n  git, python3.12+, python3.12-venv, node 20+\n\nSee: https://agentsforge.dev/install"
    fi
}

echo "🔍 Checking and installing prerequisites..."
install_prerequisites

# Resolve PYTHON_CMD if not set (macOS path / already-present system)
if [[ -z "${PYTHON_CMD:-}" ]]; then
    for cmd in python3.12 python3.11 python3.10 python3; do
        if command -v "$cmd" &>/dev/null; then
            _minor=$("$cmd" -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo "0")
            _major=$("$cmd" -c "import sys; print(sys.version_info.major)" 2>/dev/null || echo "0")
            if [[ "$_major" -eq 3 && "$_minor" -ge "$MIN_PYTHON_MINOR" ]]; then
                PYTHON_CMD="$cmd"
                break
            fi
        fi
    done
fi

[[ -z "${PYTHON_CMD:-}" ]] && fail "Could not find Python 3.${MIN_PYTHON_MINOR}+. Run the installer again after installing Python."

PYTHON_VERSION=$("$PYTHON_CMD" --version 2>&1)
ok "Python: $PYTHON_VERSION"
ok "git: $(git --version)"
ok "npm: v$(npm --version 2>/dev/null || echo 'unknown')"

# ── 2. Handle existing installation ───────────────────────────
if [[ -d "$AGENTFORGE_HOME/repo/.git" ]]; then
    echo ""
    if [[ "$FORCE_UPGRADE" == "true" ]]; then
        info "Upgrading existing installation (--upgrade flag)..."
    else
        echo -e "${YELLOW}Existing installation detected at $AGENTFORGE_HOME${RESET}"
        echo ""
        echo "  [1] Upgrade — pull latest changes and update"
        echo "  [2] Fresh   — remove and reinstall from scratch"
        echo "  [3] Cancel  — exit without changes"
        echo ""

        if [[ -t 0 ]]; then
            read -rp "  Choice [1]: " choice
        else
            choice="1"
            info "Non-interactive mode — defaulting to Upgrade"
        fi
        choice="${choice:-1}"

        case "$choice" in
            1) info "Upgrading existing installation..." ;;
            2) warn "Removing existing installation..."; rm -rf "$AGENTFORGE_HOME" ;;
            3) echo "Cancelled."; exit 0 ;;
            *) fail "Invalid choice. Run again and select 1, 2, or 3." ;;
        esac
    fi
fi

# ── 3. Detect or install platform ────────────────────────────
detect_or_install_platform() {
    PLATFORM="standalone"

    if command -v openclaw &>/dev/null && [[ -f "$HOME/.openclaw/openclaw.json" ]]; then
        PLATFORM="openclaw"
        ok "OpenClaw detected ($(openclaw --version 2>/dev/null | head -1))"
        return
    fi

    echo ""
    echo -e "${BOLD}No AI agent platform detected.${RESET}"
    echo "OpenClaw is the recommended platform — free, open-source, works out of the box."
    echo ""

    # CI mode — skip unless explicitly requested
    if [[ "${CI:-}" == "true" && "${INSTALL_OPENCLAW:-}" != "1" ]]; then
        warn "CI mode — skipping OpenClaw install. Set INSTALL_OPENCLAW=1 to override."
        return
    fi

    local install_oc
    if [[ -t 0 ]]; then
        read -rp "  Install OpenClaw? [Y/n]: " install_oc
        install_oc="${install_oc:-Y}"
    else
        install_oc="Y"
        info "Non-interactive mode — auto-installing OpenClaw"
    fi

    if [[ "${install_oc,,}" =~ ^y ]]; then
        info "Installing OpenClaw..."

        # Ensure npm global installs don't require root.
        # If the current prefix is a system path, switch to a user-local one.
        NPM_PREFIX_CURRENT=$(npm config get prefix 2>/dev/null || echo "")
        if [[ "$NPM_PREFIX_CURRENT" == /usr* || "$NPM_PREFIX_CURRENT" == /opt* ]]; then
            NPM_GLOBAL_DIR="$HOME/.npm-global"
            info "Configuring user-local npm prefix (~/.npm-global) to avoid permission errors..."
            mkdir -p "$NPM_GLOBAL_DIR"
            npm config set prefix "$NPM_GLOBAL_DIR"
            export PATH="$NPM_GLOBAL_DIR/bin:$PATH"
            # Persist to shell RC so openclaw is on PATH after install
            for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
                if [[ -f "$RC" ]] && ! grep -q "npm-global" "$RC" 2>/dev/null; then
                    echo '' >> "$RC"
                    echo '# npm global (AgentForge)' >> "$RC"
                    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$RC"
                fi
            done
        fi

        npm install -g openclaw
        ok "OpenClaw $(openclaw --version 2>/dev/null | head -1) installed"
        PLATFORM="openclaw"

        # Skip model config in CI (no human present)
        if [[ "${CI:-}" == "true" ]]; then
            warn "CI mode — skipping model configuration."
            warn "Run manually after install: openclaw configure --section model"
        else
            echo ""
            echo -e "${BOLD}🔑 Configure your AI model${RESET}"
            echo "You'll need an API key from one of these providers:"
            echo "  • Anthropic (Claude) — anthropic.com — recommended"
            echo "  • OpenAI             — platform.openai.com"
            echo "  • xAI (Grok)         — x.ai/api"
            echo "  • Groq               — groq.com (free tier available)"
            echo ""
            openclaw configure --section model
        fi
    else
        warn "Skipping platform install. Add one later: agentforge init --platform openclaw"
        # Check for LangChain fallback
        if "$PYTHON_CMD" -c "import langchain" &>/dev/null 2>&1; then
            PLATFORM="langchain"
            ok "LangChain detected — using langchain platform"
        fi
    fi
}

echo ""
echo "🔍 Detecting platform..."
detect_or_install_platform

# ── 4. Install AgentForge ─────────────────────────────────────
echo ""
echo "📥 Installing AgentForge..."
mkdir -p "$AGENTFORGE_HOME"

# Clone or update
if [[ -d "$AGENTFORGE_HOME/repo/.git" ]]; then
    info "Updating existing repository..."
    git -C "$AGENTFORGE_HOME/repo" fetch -q origin
    git -C "$AGENTFORGE_HOME/repo" reset -q --hard origin/main
else
    info "Cloning repository..."
    if ! git clone -q "$REPO_URL" "$AGENTFORGE_HOME/repo" 2>&1; then
        fail "Failed to clone repository. Check your internet connection and try again."
    fi
    git -C "$AGENTFORGE_HOME/repo" fetch -q origin
    git -C "$AGENTFORGE_HOME/repo" reset -q --hard origin/main
fi
ok "Repository ready ($(git -C "$AGENTFORGE_HOME/repo" rev-parse --short HEAD))"

# Python venv
info "Setting up Python environment..."
if [[ ! -d "$AGENTFORGE_HOME/venv" ]]; then
    "$PYTHON_CMD" -m venv "$AGENTFORGE_HOME/venv"
fi

"$AGENTFORGE_HOME/venv/bin/pip" install -q --upgrade pip
"$AGENTFORGE_HOME/venv/bin/pip" install -q "$AGENTFORGE_HOME/repo"
ok "Python environment ready"

# ── 5. Add to PATH (not alias) ────────────────────────────────
info "Installing agentforge command..."
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

cat > "$LOCAL_BIN/agentforge" << WRAPPER
#!/bin/bash
exec "$AGENTFORGE_HOME/venv/bin/agentforge" "\$@"
WRAPPER
chmod +x "$LOCAL_BIN/agentforge"

# Ensure ~/.local/bin is in PATH (add to shell rc if missing)
for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    [[ -f "$RC" ]] || continue
    if ! grep -q 'HOME/.local/bin' "$RC" 2>/dev/null; then
        echo '' >> "$RC"
        echo '# AgentForge / local binaries' >> "$RC"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
    fi
done

ok "Command installed: $LOCAL_BIN/agentforge"

# Make it available in current shell without restart
export PATH="$LOCAL_BIN:$PATH"

# ── 6. Verify installation ────────────────────────────────────
echo ""
echo "🔍 Verifying installation..."

if ! "$LOCAL_BIN/agentforge" --version &>/dev/null; then
    fail "agentforge command failed to run. Installation may be corrupted.\n\nTry: rm -rf $AGENTFORGE_HOME && re-run installer"
fi

INSTALLED_VERSION=$("$LOCAL_BIN/agentforge" --version 2>&1 || echo "unknown")
ok "agentforge $INSTALLED_VERSION"

# ── 7. Initialize ─────────────────────────────────────────────
echo ""
"$LOCAL_BIN/agentforge" init --platform "$PLATFORM" --no-install
ok "Workspace bootstrap complete — bot is aware of its stack"
info "Next: edit ~/.agentforge/workspace/SOUL.md to define your mission"

# ── 8. Start services ─────────────────────────────────────────
echo ""
echo "🚀 Starting AgentForge services..."
if "$LOCAL_BIN/agentforge" start 2>/dev/null; then
    ok "Services started"
else
    warn "Could not auto-start services. Run manually: agentforge start"
fi

# ── 9. Verify bot is running ──────────────────────────────────
echo ""
echo "🔍 Verifying services..."
STATUS_OUTPUT=$("$LOCAL_BIN/agentforge" status 2>&1 || echo "status check failed")
if echo "$STATUS_OUTPUT" | grep -qiE "running|active|ok"; then
    ok "AgentForge is running"
    BOT_RUNNING=true
else
    warn "Services may not be fully running. Check with: agentforge status"
    BOT_RUNNING=false
fi

# ── 10. Install Agent Mailbox (optional) ──────────────────────
if [[ "$INSTALL_MAILBOX" == "true" ]]; then
    echo ""
    echo "📬 Installing Agent Mailbox..."

    mkdir -p "$(dirname "$MAILBOX_PATH")"

    if [[ -d "$MAILBOX_PATH/.git" ]]; then
        info "Updating existing mailbox..."
        git -C "$MAILBOX_PATH" pull -q origin main || warn "Failed to update mailbox (continuing anyway)"
    else
        info "Cloning agent-mailbox..."
        if git clone -q "$MAILBOX_URL" "$MAILBOX_PATH" 2>&1; then
            ok "Agent Mailbox installed at $MAILBOX_PATH"
        else
            warn "Failed to clone agent-mailbox (may be private repo)"
            warn "Get access at: github.com/JakebotLabs/agent-mailbox"
        fi
    fi
fi

# ── 11. Run diagnostics ───────────────────────────────────────
echo ""
echo "🩺 Running diagnostics..."
"$LOCAL_BIN/agentforge" doctor

# ── 12. Done ──────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"

if [[ "$BOT_RUNNING" == "true" ]]; then
    echo -e "${GREEN}${BOLD}✅ AgentForge is installed and running!${RESET}"
else
    echo -e "${YELLOW}${BOLD}⚒️  AgentForge installed — services need manual start${RESET}"
fi

echo ""
echo "Platform: $PLATFORM"
echo "Location: $AGENTFORGE_HOME"
echo "Version:  $INSTALLED_VERSION"
echo ""
echo -e "${BOLD}Get started:${RESET}"
echo "  agentforge status    # see what's running"
echo "  agentforge start     # launch all services"
echo "  agentforge doctor    # diagnose issues"
echo ""

if [[ "$PLATFORM" == "openclaw" ]]; then
    echo -e "${BOLD}Your OpenClaw bot:${RESET}"
    echo "  openclaw chat        # test your bot interactively"
    echo "  openclaw status      # check bot status"
    echo ""
fi

if [[ "$INSTALL_MAILBOX" == "true" && -d "$MAILBOX_PATH" ]]; then
    echo -e "${BOLD}Agent Mailbox:${RESET}"
    echo "  cd $MAILBOX_PATH"
    echo "  python mailbox.py --agent <your-id> onboard"
    echo ""
fi

echo -e "${YELLOW}Note:${RESET} Open a new terminal (or run: export PATH=\"\$HOME/.local/bin:\$PATH\")"
echo "      if 'agentforge' command isn't found yet."
echo ""
echo "Docs: https://agentsforge.dev"
echo "════════════════════════════════════════"
echo ""
