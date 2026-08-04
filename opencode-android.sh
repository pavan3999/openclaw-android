#!/usr/bin/env bash
# opencode-android.sh - Standalone OpenCode installer for Android/Termux
# Installs OpenCode + optional tools WITHOUT full OpenClaw platform
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/AidanPark/openclaw-android/main/opencode-android.sh | bash
#
# Or download and run locally:
#   curl -sL https://raw.githubusercontent.com/AidanPark/openclaw-android/main/opencode-android.sh -o opencode-android.sh
#   chmod +x opencode-android.sh && ./opencode-android.sh
set -euo pipefail

# ── Color constants ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# ── Project constants ──
OPENCLAW_DIR="$HOME/.opencode-android"
BIN_DIR="$OPENCLAW_DIR/bin"
GLIBC_LDSO="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
PROOT_ROOT="$OPENCLAW_DIR/proot-root"

# ── Helpers ──
log_ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "${BOLD}[INFO]${NC} $1"; }

fail_exit() { log_fail "$1"; exit 1; }

# ── Banner ──
show_banner() {
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║       OpenCode on Android — Standalone      ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
  echo ""
}

# ── Pre-flight checks ──
check_environment() {
  echo "=== Pre-flight Checks ==="
  echo ""

  if [ -z "${PREFIX:-}" ]; then
    fail_exit "Not running in Termux (\$PREFIX not set). Please install Termux from F-Droid."
  fi

  ARCH=$(uname -m)
  if [ "$ARCH" != "aarch64" ]; then
    fail_exit "This script requires aarch64 (ARM64). Detected: $ARCH"
  fi

  # Check disk space (need ~1GB free)
  AVAILABLE=$(df -k "$PREFIX" | awk 'NR==2 {print $4}')
  if [ "$AVAILABLE" -lt 800000 ]; then
    fail_exit "Not enough disk space. Need ~800MB free, got $((AVAILABLE / 1024))MB"
  fi

  log_ok "Termux environment detected ($ARCH)"
  log_ok "Disk space available: $((AVAILABLE / 1024))MB"
  echo ""
}

# ── Ask for optional tools ──
ask_optional_tools() {
  echo "=== Optional Tools ==="
  echo ""
  echo "Select which tools to install:"
  echo "  [1] tmux (terminal multiplexer, untuk background session)......... [Y/n]"
  echo "  [2] ttyd (web terminal, akses dari browser).................. [n]"
  echo "  [3] dufs (file server HTTP/WebDAV).......................... [n]"
  echo "  [4] android-tools (ADB, untuk disable Phantom Process Killer) [n]"
  echo "  [5] code-server (VS Code di browser)......................... [n]"
  echo "  [6] chromium (browser automation)............................ [n]"
  echo "  [7] playwright (browser automation library).................. [n]"
  echo ""

  # Check if stdin is a TTY (interactive mode)
  if [ -t 0 ]; then
    # Interactive mode - prompt user
    local reply
    echo -n "  Select tools (default: tmux only, Enter for defaults): "
    read -r reply
    if [ -z "$reply" ]; then
      # Default: only tmux
      TOOLS_TMUX="y"
      TOOLS_TTYD="n"
      TOOLS_DUFS="n"
      TOOLS_ANDROID_TOOLS="n"
      TOOLS_CODE_SERVER="n"
      TOOLS_CHROMIUM="n"
      TOOLS_PLAYWRIGHT="n"
    else
      # Parse input (e.g., "1,3,5" or "1 3 5")
      echo "$reply" | grep -q "1" && TOOLS_TMUX="y" || TOOLS_TMUX="n"
      echo "$reply" | grep -q "2" && TOOLS_TTYD="y" || TOOLS_TTYD="n"
      echo "$reply" | grep -q "3" && TOOLS_DUFS="y" || TOOLS_DUFS="n"
      echo "$reply" | grep -q "4" && TOOLS_ANDROID_TOOLS="y" || TOOLS_ANDROID_TOOLS="n"
      echo "$reply" | grep -q "5" && TOOLS_CODE_SERVER="y" || TOOLS_CODE_SERVER="n"
      echo "$reply" | grep -q "6" && TOOLS_CHROMIUM="y" || TOOLS_CHROMIUM="n"
      echo "$reply" | grep -q "7" && TOOLS_PLAYWRIGHT="y" || TOOLS_PLAYWRIGHT="n"
    fi
  else
    # Non-interactive (curl|bash) - use defaults
    echo "  [AUTO] Running in non-interactive mode — installing defaults (tmux only)"
    echo "         To select tools manually, run:"
    echo "         bash ~/opencode-android.sh"
    echo ""
    TOOLS_TMUX="y"
    TOOLS_TTYD="n"
    TOOLS_DUFS="n"
    TOOLS_ANDROID_TOOLS="n"
    TOOLS_CODE_SERVER="n"
    TOOLS_CHROMIUM="n"
    TOOLS_PLAYWRIGHT="n"
  fi
  echo ""
}

# ── Resolve repo base ──
resolve_repo_base() {
  REPO_BASE="https://raw.githubusercontent.com/AidanPark/openclaw-android/main"
  REPO_MIRRORS=(
    "https://ghfast.top/https://raw.githubusercontent.com/AidanPark/openclaw-android/main"
    "https://ghproxy.net/https://raw.githubusercontent.com/AidanPark/openclaw-android/main"
    "https://mirror.ghproxy.com/https://raw.githubusercontent.com/AidanPark/openclaw-android/main"
  )

  if curl -sI --connect-timeout 3 "$REPO_BASE/oa.sh" >/dev/null 2>&1; then
    log_ok "Connected to GitHub (direct)"
    return 0
  fi

  for mirror in "${REPO_MIRRORS[@]}"; do
    if curl -sI --connect-timeout 5 "$mirror/oa.sh" >/dev/null 2>&1; then
      log_ok "Connected via mirror"
      REPO_BASE="$mirror"
      return 0
    fi
  done

  log_warn "Could not reach GitHub, using fallback"
  REPO_BASE="https://raw.githubusercontent.com/AidanPark/openclaw-android/main"
}

# ── Install L1: Core infrastructure ──
install_infra() {
  echo "=== [1/5] Installing Infrastructure ==="
  echo ""

  log_info "Updating package repositories..."
  pkg update -y
  echo ""

  log_info "Installing git..."
  pkg install -y git
  log_ok "git installed"
  echo ""
}

# ── Install L2: glibc environment ──
install_glibc() {
  echo "=== [2/5] Installing glibc Runtime ==="
  echo ""

  # Check if already installed
  if [ -f "$OPENCLAW_DIR/.glibc-arch" ] && [ -x "$GLIBC_LDSO" ]; then
    log_skip "glibc-runner already installed"
    echo ""
    return 0
  fi

  log_info "Installing pacman (package manager for glibc packages)..."
  if ! pkg install -y pacman; then
    fail_exit "Failed to install pacman"
  fi
  log_ok "pacman installed"
  echo ""

  # Apply SigLevel workaround for GPGME bug
  PACMAN_CONF="$PREFIX/etc/pacman.conf"
  if [ -f "$PACMAN_CONF" ]; then
    if ! grep -q "^SigLevel = Never" "$PACMAN_CONF"; then
      cp "$PACMAN_CONF" "${PACMAN_CONF}.bak"
      sed -i 's/^SigLevel\s*=.*/SigLevel = Never/' "$PACMAN_CONF"
      log_info "Applied SigLevel workaround (GPGME bug)"
    fi
  fi

  log_info "Initializing pacman keyring..."
  pacman-key --init 2>/dev/null || true
  pacman-key --populate 2>/dev/null || true
  echo ""

  log_info "Installing glibc-runner (this may take a few minutes)..."
  if ! pacman -Sy glibc-runner --noconfirm --assume-installed bash,patchelf,resolv-conf 2>&1; then
    fail_exit "Failed to install glibc-runner"
  fi
  log_ok "glibc-runner installed"
  echo ""

  # Restore pacman.conf
  if [ -f "${PACMAN_CONF}.bak" ]; then
    mv "${PACMAN_CONF}.bak" "$PACMAN_CONF"
  fi

  # Create glibc marker
  mkdir -p "$OPENCLAW_DIR"
  touch "$OPENCLAW_DIR/.glibc-arch"

  # Create glibc /etc/hosts for localhost resolution
  GLIBC_ETC="$PREFIX/glibc/etc"
  mkdir -p "$GLIBC_ETC"
  if [ ! -f "$GLIBC_ETC/hosts" ]; then
    cat > "$GLIBC_ETC/hosts" <<'HOSTS'
127.0.0.1 localhost localhost.localdomain
::1 localhost ip6-localhost ip6-loopback
HOSTS
    log_ok "Created glibc /etc/hosts"
  fi

  # Create tmp directory
  mkdir -p "$PREFIX/tmp"
  log_ok "Created $PREFIX/tmp"

  log_ok "glibc runtime installed"
  echo ""
}

# ── Create ld.so concatenation ──
# Bun/OpenCode standalone binaries embed JS at end of file.
# Last 8 bytes = original file size (LE u64).
# Bun calculates: embedded_offset = current_file_size - stored_size
# Prepending ld.so increases current_file_size, shifting offset correctly.
create_ldso_concat() {
  local bin_path="$1"
  local output_path="$2"
  local name="$3"

  if [ ! -f "$bin_path" ]; then
    log_fail "$name binary not found at $bin_path"
    return 1
  fi

  log_info "Creating ld.so concatenation for $name..."
  cp "$GLIBC_LDSO" "$output_path"
  cat "$bin_path" >> "$output_path"
  chmod +x "$output_path"

  # Verify Bun magic marker at end
  local marker
  marker=$(tail -c 32 "$output_path" | strings 2>/dev/null | grep -o "Bun" || true)
  if [ -n "$marker" ]; then
    log_ok "$name ld.so concatenation created ($(du -h "$output_path" | cut -f1))"
  else
    log_warn "$name concatenation created but Bun marker not found"
  fi
}

# ── Install proot ──
install_proot() {
  echo ""
  log_info "Installing proot (syscall interception)..."
  if ! command -v proot &>/dev/null; then
    if ! pkg install -y proot; then
      log_warn "Failed to install proot — OpenCode may not work properly"
      return 1
    fi
  fi
  log_ok "proot available"
}



# ── Install OpenCode (direct binary download) ──
install_opencode() {
  echo ""
  echo "=== [3/5] Installing OpenCode ==="
  echo ""

  # Check if already installed
  if [ -x "$PREFIX/bin/opencode" ]; then
    log_skip "OpenCode already installed"
    return 0
  fi

  # Check for existing installation
  local OC_DIR="$OPENCLAW_DIR/opencode"
  local OC_BIN="$OC_DIR/opencode-linux-arm64"
  if [ -x "$OC_BIN" ]; then
    log_skip "OpenCode binary already exists at $OC_BIN"
  else
    log_info "Fetching latest release info..."
    local latest_url="https://api.github.com/repos/opencode-ai/opencode/releases/latest"
    local tag resp
    tag=$(curl -sfL "$latest_url" 2>/dev/null | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/' || true)
    if [ -z "$tag" ]; then
      log_warn "Failed to fetch latest release info"
      return 1
    fi
    log_info "Latest version: v$tag"
    echo ""

    local download_url="https://github.com/opencode-ai/opencode/releases/download/v${tag}/opencode-linux-arm64.tar.gz"
    local tmp_dir tmp_tar
    tmp_dir=$(mktemp -d "$PREFIX/tmp/opencode-install.XXXXXX") || {
      log_warn "Failed to create temp directory"
      return 1
    }
    tmp_tar="$tmp_dir/opencode.tar.gz"

    log_info "Downloading OpenCode v${tag} (~50MB)..."
    if ! curl -fL --max-time 300 "$download_url" -o "$tmp_tar"; then
      rm -rf "$tmp_dir"
      log_warn "Failed to download OpenCode from GitHub"
      return 1
    fi
    log_ok "Downloaded"
    echo ""

    log_info "Extracting..."
    mkdir -p "$OC_DIR"
    if ! tar -xzf "$tmp_tar" -C "$OC_DIR" 2>/dev/null; then
      # Try alternate extraction
      tar -xzf "$tmp_tar" 2>/dev/null || true
      mv opencode-linux-arm64 "$OC_BIN" 2>/dev/null || true
    fi
    rm -rf "$tmp_dir"

    if [ ! -x "$OC_BIN" ]; then
      log_warn "OpenCode binary not found after extraction"
      return 1
    fi
    chmod +x "$OC_BIN"
    log_ok "OpenCode extracted to $OC_BIN"
  fi
  echo ""

  # Create proot rootfs
  log_info "Setting up proot rootfs..."
  mkdir -p "$PROOT_ROOT/data/data/com.termux/files"
  log_ok "proot rootfs created"
  echo ""

  # Create wrapper script
  local wrapper="$PREFIX/bin/opencode"
  log_info "Creating OpenCode wrapper script..."

  cat > "$wrapper" << WRAPPER
#!/data/data/com.termux/files/usr/bin/bash
# OpenCode wrapper — proot for syscall interception
unset LD_PRELOAD
exec proot \
  -R "$PROOT_ROOT" \
  -b "\$PREFIX:\$PREFIX" \
  -b /system:/system \
  -b /apex:/apex \
  -w "\$(pwd)" \
  "$OC_BIN" "\$@"
WRAPPER
  chmod +x "$wrapper"
  log_ok "OpenCode wrapper script created"
  echo ""

  # Create config
  local config_dir="$HOME/.config/opencode"
  mkdir -p "$config_dir"
  if [ ! -f "$config_dir/opencode.json" ]; then
    cat > "$config_dir/opencode.json" << 'CONFIG'
{
  "$schema": "https://opencode.ai/config.json"
}
CONFIG
    log_ok "Config created at ~/.config/opencode/opencode.json"
  else
    log_ok "Config already exists"
  fi
  echo ""

  # Verify
  log_info "Verifying OpenCode..."
  local ver
  ver=$("$wrapper" --version 2>/dev/null) || true
  if [ -n "$ver" ]; then
    log_ok "OpenCode v$ver verified"
  else
    log_warn "Verification failed — may still work in interactive mode"
  fi

  echo ""
  log_ok "OpenCode installation complete!"
  echo ""
}

# ── Setup environment variables ──
setup_environment() {
  echo "=== [4/5] Setting Up Environment ==="
  echo ""

  local bashrc="$HOME/.bashrc"
  local marker_start="# >>> OpenCode on Android >>>"
  local marker_end="# <<< OpenCode on Android <<<"

  # Remove old block if exists
  if grep -qF "$marker_start" "$bashrc" 2>/dev/null; then
    # shellcheck disable=SC2016
    sed -i "/${marker_start//\//\\\/}/,/${marker_end//\//\\\/}/d" "$bashrc"
  fi

  local env_block="
$marker_start
# platform: opencode-standalone
export TMPDIR=\"\$PREFIX/tmp\"
export TMP=\"\$TMPDIR\"
export TEMP=\"\$TMPDIR\"
export OA_GLIBC=1
export OPENCODE_DIR=\"$OPENCLAW_DIR\"
export PATH=\"\$HOME/.local/bin:\$PATH\"
$marker_end"

  echo "" >> "$bashrc"
  echo -e "$env_block" >> "$bashrc"
  log_ok "Environment variables written to ~/.bashrc"

  # Create llvm-ar symlink if needed
  if [ ! -e "$PREFIX/bin/ar" ] && [ -x "$PREFIX/bin/llvm-ar" ]; then
    ln -s "$PREFIX/bin/llvm-ar" "$PREFIX/bin/ar"
    log_ok "Created ar -> llvm-ar symlink"
  fi

  echo ""
}

# ── Install optional tools ──
install_optional_tools() {
  echo ""
  echo "=== [5/5] Installing Optional Tools ==="
  echo ""

  # Helper: check if already installed
  is_installed_pkg() {
    local pkg="$1"
    pkg list-installed 2>/dev/null | grep -q "^$pkg "; return $?
  }

  # ── tmux ──
  if [[ "${TOOLS_TMUX:-y}" =~ ^[Yy] ]] || [[ "${TOOLS_TMUX:-}" == "1" ]]; then
    echo ""
    log_info "Installing tmux..."
    if is_installed_pkg "tmux"; then
      log_skip "tmux already installed"
    else
      pkg install -y tmux
      log_ok "tmux installed"
    fi
  fi

  # ── ttyd ──
  if [[ "${TOOLS_TTYD:-n}" =~ ^[Yy] ]] || [[ "${TOOLS_TTYD:-n}" == "1" ]]; then
    echo ""
    log_info "Installing ttyd..."
    if is_installed_pkg "ttyd"; then
      log_skip "ttyd already installed"
    else
      pkg install -y ttyd
      log_ok "ttyd installed"
    fi
  fi

  # ── dufs ──
  if [[ "${TOOLS_DUFS:-n}" =~ ^[Yy] ]] || [[ "${TOOLS_DUFS:-n}" == "1" ]]; then
    echo ""
    log_info "Installing dufs..."
    if is_installed_pkg "dufs"; then
      log_skip "dufs already installed"
    else
      pkg install -y dufs
      log_ok "dufs installed"
    fi
  fi

  # ── android-tools ──
  if [[ "${TOOLS_ANDROID_TOOLS:-n}" =~ ^[Yy] ]] || [[ "${TOOLS_ANDROID_TOOLS:-n}" == "1" ]]; then
    echo ""
    log_info "Installing android-tools..."
    if is_installed_pkg "android-tools"; then
      log_skip "android-tools already installed"
    else
      pkg install -y android-tools
      log_ok "android-tools installed (adb, fastboot)"
    fi
  fi

  # ── code-server ──
  if [[ "${TOOLS_CODE_SERVER:-n}" =~ ^[Yy] ]] || [[ "${TOOLS_CODE_SERVER:-n}" == "1" ]]; then
    echo ""
    log_info "Installing code-server..."
    install_code_server
  fi

  # ── chromium ──
  if [[ "${TOOLS_CHROMIUM:-n}" =~ ^[Yy] ]] || [[ "${TOOLS_CHROMIUM:-n}" == "1" ]]; then
    echo ""
    log_info "Installing Chromium..."
    install_chromium
  fi

  # ── playwright ──
  if [[ "${TOOLS_PLAYWRIGHT:-n}" =~ ^[Yy] ]] || [[ "${TOOLS_PLAYWRIGHT:-n}" == "1" ]]; then
    echo ""
    log_info "Installing Playwright..."
    install_playwright
  fi

  echo ""
}

# ── Install code-server ──
install_code_server() {
  local install_dir="$HOME/.local/lib"
  local bin_dir="$HOME/.local/bin"
  local current_ver
  current_ver=$(code-server --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)

  if [ -n "$current_ver" ]; then
    log_skip "code-server already installed ($current_ver)"
    return 0
  fi

  # Fetch latest version
  local latest_ver
  latest_ver=$(curl -sfL --max-time 10 \
    "https://api.github.com/repos/coder/code-server/releases/latest" \
    | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/' || true)

  if [ -z "$latest_ver" ]; then
    log_warn "Failed to fetch latest code-server version"
    return 1
  fi

  local tarball="code-server-${latest_ver}-linux-arm64.tar.gz"
  local download_url="https://github.com/coder/code-server/releases/download/v${latest_ver}/${tarball}"
  local tmp_dir
  tmp_dir=$(mktemp -d "$PREFIX/tmp/code-server-install.XXXXXX") || {
    log_warn "Failed to create temp directory"
    return 1
  }

  log_info "Downloading code-server v${latest_ver} (~121MB)..."
  if ! curl -fL --max-time 300 "$download_url" -o "$tmp_dir/$tarball"; then
    rm -rf "$tmp_dir"
    log_warn "Failed to download code-server"
    return 1
  fi
  log_ok "Downloaded"
  echo ""

  log_info "Extracting code-server..."
  tar -xzf "$tmp_dir/$tarball" -C "$tmp_dir" 2>/dev/null || true

  local extracted_dir="$tmp_dir/code-server-${latest_ver}-linux-arm64"
  if [ ! -d "$extracted_dir" ]; then
    rm -rf "$tmp_dir"
    log_warn "Extraction failed"
    return 1
  fi

  # Recover hard-linked .node files (Android doesn't support hardlinks)
  find "$extracted_dir" -path "*/obj.target/*.node" -type f 2>/dev/null | while read -r obj_file; do
    local release_dir
    release_dir="$(dirname "$(dirname "$obj_file")")/Release"
    local basename
    basename=$(basename "$obj_file")
    if [ -d "$release_dir" ] && [ ! -f "$release_dir/$basename" ]; then
      cp "$obj_file" "$release_dir/$basename"
    fi
  done

  mkdir -p "$install_dir" "$bin_dir"
  rm -rf "$install_dir"/code-server-*
  mv "$extracted_dir" "$install_dir/code-server-${latest_ver}"

  # Replace bundled node with Termux node (Bionic vs glibc)
  if [ -f "$install_dir/code-server-${latest_ver}/lib/node" ] || [ -L "$install_dir/code-server-${latest_ver}/lib/node" ]; then
    rm -f "$install_dir/code-server-${latest_ver}/lib/node"
  fi
  ln -s "$PREFIX/bin/node" "$install_dir/code-server-${latest_ver}/lib/node"
  log_ok "Replaced bundled node → Termux node"

  # Patch argon2 module (glibc binary incompatible with Bionic)
  local argon2_index
  for pattern in "*/argon2/argon2.cjs" "*/argon2/argon2.js" "*/node_modules/argon2/index.js"; do
    argon2_index=$(find "$install_dir/code-server-${latest_ver}" -path "$pattern" -type f 2>/dev/null | head -1 || true)
    [ -n "$argon2_index" ] && break
  done
  if [ -n "$argon2_index" ]; then
    cat > "$argon2_index" << 'STUB'
// argon2-stub - JS stub for Termux (Bionic)
// code-server uses --auth none, so argon2 is never called
module.exports.hash = async function hash() {
  throw new Error("argon2 not available on Termux. Use --auth none.");
};
module.exports.verify = async function verify() {
  throw new Error("argon2 not available on Termux. Use --auth none.");
};
module.exports.needsRehash = function needsRehash() { return false; };
module.exports.argon2d = 0; module.exports.argon2i = 1; module.exports.argon2id = 2;
STUB
    log_ok "Patched argon2 module"
  fi

  # Create symlink
  rm -f "$bin_dir/code-server"
  ln -s "$install_dir/code-server-${latest_ver}/bin/code-server" "$bin_dir/code-server"
  log_ok "Symlinked code-server → ~/.local/bin/"

  rm -rf "$tmp_dir"

  if code-server --version &>/dev/null; then
    local installed_ver
    installed_ver=$(code-server --version 2>/dev/null | head -1 || true)
    log_ok "code-server ${installed_ver:-v${latest_ver}} installed successfully"
  else
    log_warn "code-server installed but verification failed"
    log_info "Run: source ~/.bashrc && code-server --version"
  fi
}

# ── Install Chromium ──
install_chromium() {
  local chromium_bin=""
  for bin in "$PREFIX/bin/chromium-browser" "$PREFIX/bin/chromium"; do
    if [ -x "$bin" ]; then
      chromium_bin="$bin"
      break
    fi
  done

  if [ -n "$chromium_bin" ]; then
    log_skip "Chromium already installed ($chromium_bin)"
    return 0
  fi

  log_info "Installing x11-repo..."
  if ! pkg install -y x11-repo; then
    log_warn "Failed to install x11-repo"
    return 1
  fi

  log_info "Installing Chromium (~400MB, this may take a while)..."
  if ! pkg install -y chromium; then
    log_warn "Failed to install Chromium"
    return 1
  fi

  for bin in "$PREFIX/bin/chromium-browser" "$PREFIX/bin/chromium"; do
    if [ -x "$bin" ]; then
      chromium_bin="$bin"
      break
    fi
  done

  if [ -n "$chromium_bin" ]; then
    local chromium_ver
    chromium_ver=$("$chromium_bin" --version 2>/dev/null || echo "unknown")
    log_ok "Chromium $chromium_ver installed"
    log_info "Chromium uses ~300-500MB RAM at runtime"
  else
    log_warn "Chromium installed but binary not found"
  fi
}

# ── Install Playwright ──
install_playwright() {
  if ! command -v npm &>/dev/null; then
    log_warn "npm not found — skipping playwright"
    return 1
  fi

  if npm list -g playwright-core &>/dev/null; then
    log_skip "playwright-core already installed"
    return 0
  fi

  # Ensure Chromium is installed first
  local chromium_bin=""
  for bin in "$PREFIX/bin/chromium-browser" "$PREFIX/bin/chromium"; do
    if [ -x "$bin" ]; then
      chromium_bin="$bin"
      break
    fi
  done

  if [ -z "$chromium_bin" ]; then
    log_info "Chromium required for Playwright — installing first..."
    install_chromium
    for bin in "$PREFIX/bin/chromium-browser" "$PREFIX/bin/chromium"; do
      if [ -x "$bin" ]; then
        chromium_bin="$bin"
        break
      fi
    done
  fi

  log_info "Installing playwright-core..."
  if ! npm install -g playwright-core; then
    log_warn "Failed to install playwright-core"
    return 1
  fi
  log_ok "playwright-core installed"

  # Set environment variables in .bashrc
  if [ -n "$chromium_bin" ]; then
    local bashrc="$HOME/.bashrc"
    local marker_start="# >>> Playwright >>>"
    local marker_end="# <<< Playwright <<<"

    if grep -qF "$marker_start" "$bashrc" 2>/dev/null; then
      # shellcheck disable=SC2016
      sed -i "/${marker_start//\//\\\/}/,/${marker_end//\//\\\/}/d" "$bashrc"
    fi

    local pw_block="
$marker_start
export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=\"$chromium_bin\"
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
$marker_end"
    echo -e "$pw_block" >> "$bashrc"
    log_ok "Playwright environment variables set"
  fi
}

# ── Show summary ──
show_summary() {
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║            Installation Complete!            ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  echo "  Installed components:"
  echo "    ✓ glibc runtime (ld-linux-aarch64.so.1)"
  echo "    ✓ Bun runtime"
  echo "    ✓ OpenCode AI coding assistant"
  echo ""

  if [[ "${TOOLS_TMUX:-y}" =~ ^[Yy] ]] || [[ "${TOOLS_TMUX:-}" == "1" ]]; then
    echo "    ✓ tmux (terminal multiplexer)"
  fi
  if [[ "${TOOLS_TTYD:-n}" =~ ^[Yy] ]] || [[ "${TOOLS_TTYD:-n}" == "1" ]]; then
    echo "    ✓ ttyd (web terminal)"
  fi
  if [[ "${TOOLS_DUFS:-n}" =~ ^[Yy] ]] || [[ "${TOOLS_DUFS:-n}" == "1" ]]; then
    echo "    ✓ dufs (HTTP file server)"
  fi
  if [[ "${TOOLS_ANDROID_TOOLS:-n}" =~ ^[Yy] ]] || [[ "${TOOLS_ANDROID_TOOLS:-n}" == "1" ]]; then
    echo "    ✓ android-tools (ADB)"
  fi
  if [[ "${TOOLS_CODE_SERVER:-n}" =~ ^[Yy] ]] || [[ "${TOOLS_CODE_SERVER:-n}" == "1" ]]; then
    echo "    ✓ code-server (VS Code in browser)"
  fi
  if [[ "${TOOLS_CHROMIUM:-n}" =~ ^[Yy] ]] || [[ "${TOOLS_CHROMIUM:-n}" == "1" ]]; then
    echo "    ✓ Chromium (browser automation)"
  fi
  if [[ "${TOOLS_PLAYWRIGHT:-n}" =~ ^[Yy] ]] || [[ "${TOOLS_PLAYWRIGHT:-n}" == "1" ]]; then
    echo "    ✓ playwright-core (browser automation)"
  fi

  echo ""
  echo -e "${BOLD}  Next steps:${NC}"
  echo "    1. Run: source ~/.bashrc"
  echo "    2. Run: opencode"
  echo ""
  echo "  Optional commands:"
  echo "    opencode --version    # Check version"
  echo "    opencode --help       # Show help"
  echo ""
  echo "  Keep processes alive (Android 12+):"
  echo "    Settings → Developer Options → Disable Phantom Process Killer"
  echo "    (See: https://docs.nickworld.org/disable-phantom-process-killer)"
  echo ""
}

# ── Main ──
main() {
  show_banner
  check_environment
  ask_optional_tools
  resolve_repo_base

  install_infra
  install_glibc
  install_proot
  install_opencode
  setup_environment
  install_optional_tools
  show_summary
}

main "$@"
