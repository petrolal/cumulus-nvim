#!/usr/bin/env bash
# TetraVim Neovim: Full Bootstrap
# Installs all runtime dependencies required for a clean :checkhealth run.
# Run once after a fresh clone / new machine setup.
#
# Usage: bash bootstrap.sh

set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
	DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
REPO_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

pass() { echo "  ✔ $*"; }
warn() { echo "  ⚠ $*"; }
fail() { echo "  ✖ $*"; }
section() {
	echo ""
	echo "── $* ──────────────────────────────────────────────"
}

echo "=================================================="
echo "   TetraVim Neovim: Full Bootstrap               "
echo "=================================================="

# ============================================================================
# 0. Neovim — hard requirement
# ============================================================================
section "Neovim"
if ! command -v nvim >/dev/null 2>&1; then
	fail "Neovim not found. Install >= 0.11 first."
	echo "    macOS:  brew install neovim"
	echo "    Ubuntu: sudo apt install neovim"
	echo "    Arch:   sudo pacman -S neovim"
	exit 1
fi
# init.lua hard-fails below 0.11 (vim.lsp.config/enable, vim.diagnostic.jump,
# winborder); catch it here with an actionable message instead.
if ! nvim --headless -u NONE -c 'lua os.exit(vim.fn.has("nvim-0.11") == 1 and 0 or 1)' -c 'qa!' >/dev/null 2>&1; then
	fail "Neovim $(nvim --version | head -n 1 | awk '{print $2}') is too old -- TetraVim requires >= 0.11."
	exit 1
fi
pass "Neovim: $(nvim --version | head -n 1)"

# ============================================================================
# 1. Cache cleanup — clear Neovim runtime and Tree-sitter caches
# ============================================================================
section "Cache cleanup"
NVIM_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/nvim"
TS_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/tree-sitter"
rm -rf "$NVIM_CACHE" "$TS_CACHE"
pass "Caches cleared ($NVIM_CACHE, $TS_CACHE)"

# ============================================================================
# 2. Link config & sync plugins (idempotent)
# ============================================================================
section "Config & Plugins"

NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
if [ -e "$NVIM_CONFIG" ] && [ ! -L "$NVIM_CONFIG" ]; then
	BACKUP="$NVIM_CONFIG.backup.$(date +%s)"
	warn "Backing up existing nvim config -> $BACKUP"
	mv "$NVIM_CONFIG" "$BACKUP"
fi
if [ -L "$NVIM_CONFIG" ]; then
	rm "$NVIM_CONFIG"
fi
mkdir -p "$(dirname "$NVIM_CONFIG")"
ln -sf "$REPO_DIR" "$NVIM_CONFIG"
pass "Config linked: $NVIM_CONFIG -> $REPO_DIR"

if nvim --headless -u "$NVIM_CONFIG/init.lua" -c "lua require('tetravim.core.setup').run()" -c "qa!" 2>/dev/null; then
	pass "TetraVim native setup complete (plugins synced, Mason tools, LSP jars, Tree-sitter parsers)"
else
	warn "TetraVim setup had warnings -- run :TetraVimSetup inside nvim to inspect"
fi

# ============================================================================
# 2. Node.js provider & npm tools
#    - neovim npm package  -> vim.provider Node.js
#    - prettier            -> conform.nvim formatter (web/yaml/json/md)
# ============================================================================
section "Node.js tools (npm)"

if ! command -v npm >/dev/null 2>&1; then
	warn "npm not found -- skipping Node.js provider and npm tools"
	warn "Install Node.js >= 18 to enable: neovim, prettier"
else
	npm_global_install() {
		local pkg="$1"
		if npm list -g "$pkg" --depth=0 2>/dev/null | grep -q "$pkg"; then
			pass "$pkg already installed"
		else
			echo "  -> npm install -g $pkg"
			npm install -g "$pkg"
			pass "$pkg installed"
		fi
	}

	npm_global_install neovim            # Node.js provider for Neovim
	npm_global_install prettier          # conform formatter: js/ts/yaml/json/md/css/html
	npm_global_install sonarqube-scanner # `sonar-scanner` CLI: <leader>xsp whole-codebase Sonar scan (connected mode)
	npm_global_install tree-sitter-cli   # `tree-sitter` CLI: nvim-treesitter "main" branch compiles every parser via `tree-sitter build`
	npm_global_install @mermaid-js/mermaid-cli  # `mmdc` CLI: Snacks.image renders Mermaid diagrams in docs/markdown
fi

# ============================================================================
# 3. Go tools
#    - yamlfmt -> conform.nvim YAML formatter
# ============================================================================
section "Go tools"

if ! command -v go >/dev/null 2>&1; then
	warn "go not found -- skipping yamlfmt"
	warn "Install Go >= 1.21 to enable yamlfmt"
else
	GOPATH_BIN="$(go env GOPATH)/bin"
	if command -v yamlfmt >/dev/null 2>&1 || [ -x "$GOPATH_BIN/yamlfmt" ]; then
		pass "yamlfmt already installed"
	else
		echo "  -> go install github.com/google/yamlfmt/cmd/yamlfmt@latest"
		go install github.com/google/yamlfmt/cmd/yamlfmt@latest
		pass "yamlfmt installed"
		if ! echo "$PATH" | grep -q "$GOPATH_BIN"; then
			warn "Add $GOPATH_BIN to your PATH (e.g. in ~/.bashrc or ~/.zshrc)"
		fi
	fi
fi

# ============================================================================
# 4. Python provider
#    - pynvim -> vim.provider Python
# ============================================================================
section "Python provider (pynvim)"

PY3="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
if [ -z "$PY3" ]; then
	warn "python3 not found -- skipping pynvim"
else
	if "$PY3" -c "import neovim" 2>/dev/null || "$PY3" -c "import pynvim" 2>/dev/null; then
		pass "pynvim already importable"
	else
		# On Arch Linux (PEP 668) pip --user alone is blocked.
		# Use --break-system-packages which is safe for user-level packages,
		# or fall back to the system package manager hint.
		if "$PY3" -m pip install --user --break-system-packages pynvim 2>/dev/null; then
			pass "pynvim installed (--break-system-packages)"
		else
			warn "Could not install pynvim automatically."
			warn "Run manually:  sudo pacman -S python-pynvim"
			warn "  or:          pip install --user --break-system-packages pynvim"
		fi
	fi
fi

# ============================================================================
# 5. Tree-sitter parsers
#    - regex -> required by noice.nvim cmdline highlighting + snacks.picker
# ============================================================================
section "Tree-sitter parsers"

# nvim-treesitter lazy-loads, so :TSInstall is unavailable headlessly.
# Use the Lua install API with explicit load and a 30-second timeout.
#
# The pinned "main" branch (lazy-lock.json) compiles every parser by shelling
# out to the `tree-sitter` CLI (`tree-sitter build`); without it on $PATH the
# install fails for every parser with `ENOENT ... 'tree-sitter'`. It's
# installed above via `npm install -g tree-sitter-cli` (and Mason ships a
# Ensure tree-sitter CLI is findable on PATH (check Mason bin directory as fallback)
MASON_BIN="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/mason/bin"
if [ -d "$MASON_BIN" ] && ! echo "$PATH" | grep -q "$MASON_BIN"; then
	export PATH="$MASON_BIN:$PATH"
fi

# Clean any stale tree-sitter locks from interrupted builds
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/tree-sitter/lock" 2>/dev/null || true

if ! command -v tree-sitter >/dev/null 2>&1; then
	warn "'tree-sitter' CLI not on \$PATH -- parser compilation will fail."
	warn "Install it with:  npm install -g tree-sitter-cli   (or :MasonInstall tree-sitter-cli)"
fi

nvim --headless -u "$NVIM_CONFIG/init.lua" \
	-c "Lazy! load nvim-treesitter" \
	-c "lua require('nvim-treesitter').install({ 'regex' }):wait(30000)" \
	-c "qa!" 2>/dev/null || true

# Verify it's now loadable
if nvim --headless -u "$NVIM_CONFIG/init.lua" \
	-c "lua\nlocal ok = pcall(vim.treesitter.get_string_parser, '', 'regex')\nio.stdout:write(tostring(ok) .. '\n')\n" \
	-c "qa!" 2>/dev/null | grep -q "^true"; then
	pass "regex Tree-sitter parser ready"
else
	warn "regex parser not ready -- check 'tree-sitter' is on \$PATH, then run ':TSInstall regex' inside nvim"
fi

# ============================================================================
# 6. PDF & LaTeX preview tools (snacks.nvim)
#    - gs (ghostscript)    -> PDF rendering
#    - tectonic / pdflatex -> LaTeX compilation
# ============================================================================
section "PDF & LaTeX preview tools (snacks.nvim)"

install_system_pkgs() {
	local mgr="$1"
	shift
	case "$mgr" in
	pacman)
		echo "  -> sudo pacman -S --noconfirm --needed $*"
		sudo pacman -S --noconfirm --needed "$@"
		;;
	yay)
		echo " -> yay -S --noconfirm --needed $*"
		yay -S --noconfirm --needed "$@"
		;;
	apt)
		echo "  -> sudo apt-get update && sudo apt-get install -y $*"
		sudo apt-get update && sudo apt-get install -y "$@"
		;;
	dnf)
		echo "  -> sudo dnf install -y $*"
		sudo dnf install -y "$@"
		;;
	brew)
		echo "  -> brew install $*"
		brew install "$@"
		;;
	esac
}

# 1. Ghostscript check
if command -v gs >/dev/null 2>&1; then
	pass "ghostscript (gs) ready"
else
	warn "'gs' missing. Attempting installation..."
	if command -v pacman >/dev/null; then
		install_system_pkgs pacman ghostscript
	elif command -v apt-get >/dev/null; then
		install_system_pkgs apt ghostscript
	elif command -v dnf >/dev/null; then
		install_system_pkgs dnf ghostscript
	elif command -v brew >/dev/null; then
		install_system_pkgs brew ghostscript
	else
		warn "Cannot auto-install ghostscript. Install manually to enable PDF rendering."
	fi
fi

# 2. LaTeX engine check (tectonic preferred, fallback pdflatex)
if command -v tectonic >/dev/null 2>&1; then
	pass "tectonic ready"
elif command -v pdflatex >/dev/null 2>&1; then
	pass "pdflatex ready"
else
	warn "Neither 'tectonic' nor 'pdflatex' found. Attempting to install tectonic..."
	if command -v pacman >/dev/null; then
		install_system_pkgs pacman tectonic
	elif command -v brew >/dev/null; then
		install_system_pkgs brew tectonic
	elif command -v cargo >/dev/null; then
		echo "  -> cargo install tectonic"
		cargo install tectonic
	else
		warn "Could not auto-install tectonic/pdflatex."
		warn "Run manually:"
		warn "  Arch:   sudo pacman -S tectonic"
		warn "  Ubuntu: sudo apt install tectonic (or texlive-latex-base)"
		warn "  macOS:  brew install tectonic"
	fi
fi

# ============================================================================
# 7. gRPC tools
# ============================================================================
section "gRPC tools"
if command -v grpcurl >/dev/null 2>&1; then
	pass "grpcurl already installed"
else
	warn "'grpcurl' missing. Attempting installation..."
	if command -v apt-get >/dev/null; then
		install_system_pkgs apt grpcurl
	elif command -v dnf >/dev/null; then
		install_system_pkgs dnf grpcurl
	elif command -v brew >/dev/null; then
		install_system_pkgs brew grpcurl
	elif command -v yay >/dev/null; then
		install_system_pkgs yay grpcurl
	else
		warn "Cannot auto-install grpcurl. Install manually."
	fi
fi

# ============================================================================
# 8. Security & vulnerability scanners
# ============================================================================
section "Security scanners"
if command -v osv-scanner >/dev/null 2>&1; then
	pass "osv-scanner already installed"
else
	warn "'osv-scanner' missing. Attempting installation..."
	if command -v brew >/dev/null; then
		install_system_pkgs brew osv-scanner
	elif command -v yay >/dev/null; then
		install_system_pkgs yay osv-scanner
	elif command -v go >/dev/null; then
		if go install github.com/google/osv-scanner/cmd/osv-scanner@latest; then
			pass "osv-scanner installed via 'go install'"
		else
			warn "'go install osv-scanner' failed. Install manually."
		fi
	else
		warn "Cannot auto-install osv-scanner. Download from https://github.com/google/osv-scanner/releases"
	fi
fi

# ============================================================================
# 9. Core CLI tools
#    - rg (ripgrep) -> project-wide search: safe-rename reference scan, Spring
#                      Boot discovery, snacks.picker (:checkhealth marks it
#                      REQUIRED)
#    - jq           -> <leader>ahj HTTP response filtering
#    - curl         -> kulala.nvim request backend + Spring Initializr download
#    - unzip        -> Spring Initializr project unpack
# ============================================================================
section "Core CLI tools"

pkg_mgr=""
for m in pacman apt-get dnf brew; do
	if command -v "$m" >/dev/null 2>&1; then
		pkg_mgr="${m/apt-get/apt}"
		break
	fi
done

for tool in rg jq curl unzip; do
	if command -v "$tool" >/dev/null 2>&1; then
		pass "$tool ready"
		continue
	fi
	pkg="$tool"
	[ "$tool" = "rg" ] && pkg="ripgrep"
	if [ -n "$pkg_mgr" ]; then
		warn "'$tool' missing. Attempting installation..."
		install_system_pkgs "$pkg_mgr" "$pkg" || warn "Could not install $pkg -- install it manually"
	else
		warn "'$tool' missing and no known package manager -- install '$pkg' manually"
	fi
done

# ============================================================================
# 10. Scala lint & format tools (scalafmt / scalastyle)
#     Not in the Mason registry -- installed via Coursier when available.
#     Metals still provides semantic diagnostics without these; they add the
#     <leader>xlF project formatting and optional style linting.
# ============================================================================
section "Scala lint & format tools (scalafmt / scalastyle)"

if command -v cs >/dev/null 2>&1 || command -v coursier >/dev/null 2>&1; then
	CS="$(command -v cs 2>/dev/null || command -v coursier)"
	for app in scalafmt scalastyle; do
		if command -v "$app" >/dev/null 2>&1; then
			pass "$app already installed"
		else
			echo "  -> $CS install $app"
			if "$CS" install "$app" >/dev/null 2>&1; then
				pass "$app installed via coursier"
			else
				warn "coursier could not install $app -- install it manually if you need Scala $app"
			fi
		fi
	done
else
	warn "coursier (cs) not found -- skipping scalafmt/scalastyle. Install Coursier, then: cs install scalafmt scalastyle"
fi

# ============================================================================
# 11. async-profiler (JVM sampling profiler)
#     util/profiling.lua shells out to `asprof` / `profiler.sh`; without it the
#     <leader>jps (start) / <leader>jpx (stop) / <leader>jpv (view) keymaps
#     error with "async-profiler binary not found in $PATH".
# ============================================================================
section "async-profiler (JVM profiler)"

AP_VERSION="3.0"
ap_present() {
	command -v asprof >/dev/null 2>&1 ||
		command -v async-profiler >/dev/null 2>&1 ||
		command -v profiler.sh >/dev/null 2>&1
}

if ap_present; then
	pass "async-profiler already installed ($(command -v asprof 2>/dev/null || command -v profiler.sh 2>/dev/null || command -v async-profiler))"
elif command -v yay >/dev/null 2>&1; then
	echo "  -> yay -S --noconfirm --needed async-profiler"
	yay -S --noconfirm --needed async-profiler || warn "yay could not install async-profiler"
elif command -v brew >/dev/null 2>&1; then
	install_system_pkgs brew async-profiler || warn "brew could not install async-profiler"
fi

if ! ap_present; then
	# No distro package -- fetch the upstream release tarball into
	# ~/.local/share and symlink the launcher onto ~/.local/bin.
	case "$(uname -s)" in
	Linux) ap_os="linux" ;;
	Darwin) ap_os="macos" ;;
	*) ap_os="" ;;
	esac
	case "$(uname -m)" in
	x86_64 | amd64) ap_arch="x64" ;;
	aarch64 | arm64) ap_arch="arm64" ;;
	*) ap_arch="" ;;
	esac

	if [ -n "$ap_os" ] && [ -n "$ap_arch" ] && command -v curl >/dev/null 2>&1; then
		if [ "$ap_os" = "macos" ]; then
			ap_tarball="async-profiler-${AP_VERSION}-macos.tar.gz"
		else
			ap_tarball="async-profiler-${AP_VERSION}-${ap_os}-${ap_arch}.tar.gz"
		fi
		ap_url="https://github.com/async-profiler/async-profiler/releases/download/v${AP_VERSION}/${ap_tarball}"
		ap_dest="${XDG_DATA_HOME:-$HOME/.local/share}/tetravim/async-profiler"
		ap_bin_dir="$HOME/.local/bin"
		echo "  -> downloading $ap_url"
		mkdir -p "$ap_dest" "$ap_bin_dir"
		if curl -fsSL "$ap_url" | tar -xz -C "$ap_dest" --strip-components=1; then
			ln -sf "$ap_dest/bin/asprof" "$ap_bin_dir/asprof"
			if [ -x "$ap_dest/bin/asprof" ]; then
				pass "async-profiler $AP_VERSION installed -> $ap_bin_dir/asprof"
			else
				warn "async-profiler tarball extracted but bin/asprof is missing"
			fi
			if ! echo "$PATH" | grep -q "$ap_bin_dir"; then
				warn "Add $ap_bin_dir to your PATH (e.g. in ~/.bashrc or ~/.zshrc)"
			fi
		else
			warn "async-profiler download/extract failed -- install it manually from"
			warn "  https://github.com/async-profiler/async-profiler/releases"
		fi
	else
		warn "Cannot auto-install async-profiler (unsupported platform or curl missing)."
		warn "Download from https://github.com/async-profiler/async-profiler/releases and put 'asprof' on \$PATH"
	fi
fi

# async-profiler needs relaxed perf_event access to sample a running JVM.
if [ "$(uname -s)" = "Linux" ] && [ -r /proc/sys/kernel/perf_event_paranoid ]; then
	ap_paranoid="$(cat /proc/sys/kernel/perf_event_paranoid)"
	case "$ap_paranoid" in
	-1 | 0 | 1) pass "kernel.perf_event_paranoid=$ap_paranoid (async-profiler can sample the JVM)" ;;
	*)
		warn "kernel.perf_event_paranoid=$ap_paranoid -- async-profiler needs <= 1. Run:"
		warn "  sudo sysctl kernel.perf_event_paranoid=1 kernel.kptr_restrict=0"
		warn "  (persist via a file in /etc/sysctl.d/)"
		;;
	esac
fi

# ============================================================================
# Done
# ============================================================================

echo ""
echo "=================================================="
echo "  Bootstrap complete! Run: nvim +checkhealth      "
echo "=================================================="

echo ""
echo "Expected remaining warnings (not blocking JVM development):"
echo "  conform  : prettier/yamlfmt -- resolved by this script"
echo "  provider : neovim npm / pynvim -- resolved by this script"
echo "  noice    : vim.notify / stylize_markdown -- Snacks.notifier handles both"
echo "  snacks   : bigfile/input/quickfile/scope/scroll/statuscolumn/words disabled by design"
echo "  mason    : Ruby/PHP/Julia/Perl -- not used by this JVM distribution"
echo "  devops   : sam / cfn-guard / glab -- optional; install manually if needed"
echo "  security : osv-scanner -- optional CVE scanning; install manually if needed"
echo "  snacks   : gs / tectonic / pdflatex -- optional PDF/LaTeX rendering"
echo "  profiler : async-profiler -- needs kernel.perf_event_paranoid<=1 to sample a JVM"
echo "  scala    : scalafmt / scalastyle -- only if coursier (cs) is installed"
