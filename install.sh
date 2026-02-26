#!/bin/bash
# AgentForge Installer
# Usage: curl -fsSL https://agentsforge.dev/install.sh | bash

set -e

AGENTFORGE_HOME="${AGENTFORGE_HOME:-$HOME/.agentforge}"
REPO_URL="https://github.com/Jakebot-ops/agentforge.git"

echo ""
echo "⚒️  AgentForge Installer"
echo "========================"
echo ""

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    else
        PKG_MANAGER="unknown"
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    PKG_MANAGER="brew"
else
    echo "❌ Unsupported OS: $OSTYPE"
    exit 1
fi

echo "📍 Detected: $OS ($PKG_MANAGER)"
echo "📁 Install path: $AGENTFORGE_HOME"
echo ""

# Install system dependencies
echo "📦 Installing system dependencies..."
if [[ "$PKG_MANAGER" == "apt" ]]; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3 python3-pip python3-venv git > /dev/null
elif [[ "$PKG_MANAGER" == "dnf" ]] || [[ "$PKG_MANAGER" == "yum" ]]; then
    sudo $PKG_MANAGER install -y python3 python3-pip git > /dev/null
elif [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install python git 2>/dev/null || true
fi
echo "  ✅ System dependencies installed"

# Create install directory
mkdir -p "$AGENTFORGE_HOME"
cd "$AGENTFORGE_HOME"

# Clone or update repo
if [[ -d "$AGENTFORGE_HOME/repo" ]]; then
    echo "📥 Updating AgentForge..."
    cd "$AGENTFORGE_HOME/repo"
    git pull -q
else
    echo "📥 Cloning AgentForge..."
    git clone -q "$REPO_URL" "$AGENTFORGE_HOME/repo"
    cd "$AGENTFORGE_HOME/repo"
fi
echo "  ✅ Repository ready"

# Create/update virtual environment
echo "🐍 Setting up Python environment..."
if [[ ! -d "$AGENTFORGE_HOME/venv" ]]; then
    python3 -m venv "$AGENTFORGE_HOME/venv"
fi
source "$AGENTFORGE_HOME/venv/bin/activate"
pip install -q --upgrade pip
pip install -q -e "$AGENTFORGE_HOME/repo"
echo "  ✅ Python environment ready"

# Create shell wrapper
echo "🔗 Creating shell command..."
SHELL_RC="$HOME/.bashrc"
[[ -f "$HOME/.zshrc" ]] && SHELL_RC="$HOME/.zshrc"

ALIAS_LINE="alias agentforge='$AGENTFORGE_HOME/venv/bin/agentforge'"
if ! grep -q "alias agentforge=" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# AgentForge" >> "$SHELL_RC"
    echo "$ALIAS_LINE" >> "$SHELL_RC"
fi
echo "  ✅ Shell command configured"

# Run init if first install
if [[ ! -f "$AGENTFORGE_HOME/agentforge.yml" ]]; then
    echo ""
    echo "🚀 Running initial setup..."
    "$AGENTFORGE_HOME/venv/bin/agentforge" init --platform standalone
fi

echo ""
echo "═══════════════════════════════════════════"
echo "✅ AgentForge installed successfully!"
echo ""
echo "To start using AgentForge, either:"
echo "  1. Restart your terminal, or"
echo "  2. Run: source $SHELL_RC"
echo ""
echo "Then try:"
echo "  agentforge --help"
echo "  agentforge doctor"
echo "  agentforge status"
echo ""
echo "Docs: https://agentsforge.dev"
echo "═══════════════════════════════════════════"
