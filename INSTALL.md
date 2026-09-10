# TetraVim Neovim Installation Guide

## Quick Start (One Shot Install)

### 1. Clone the Repository
```bash
git clone https://github.com/petrolal/tetravim.nvim.git ~/.config/nvim
```

### 2. Run Setup
```bash
cd ~/.config/nvim
bash bootstrap.sh
```

This single command will:
- ✔ Ensure basic dependencies are present (git, neovim, ripgrep, java)
- ✔ Sync all plugins via Lazy.nvim
- ✔ Verify health and setup

### 3. Done!
```bash
nvim
```

Plain `nvim` command now launches TetraVim. That's it!

---

## What Gets Installed

### System Dependencies
- **git** - Version control
- **neovim** - Editor (>= 0.11 required; `init.lua` hard-fails on older)
- **java** - Required by LSP tools (JDTLS, Metals, etc.)
- **ripgrep** - For fast file searching (Telescope)
- **fd** - For fast file finding

### TetraVim Components
- **~/.config/nvim** - Symlinked to repository
- **Lazy plugins** - All plugins from `lua/tetravim/plugins/` (nvim-jdtls, nvim-dap, etc.)

---

## Troubleshooting

### "Neovim: nvim not found"
Install Neovim:
```bash
# macOS
brew install neovim

# Ubuntu/Debian
sudo apt install neovim

# Arch
sudo pacman -S neovim

# Fedora
sudo dnf install neovim
```

### Plugin sync failed
Run inside Neovim:
```vim
:Lazy sync
```

---

## Uninstall

To remove TetraVim:

```bash
# Remove configuration folder
rm -rf ~/.config/nvim

# Restore backup if you had previous config
mv ~/.config/nvim.backup.* ~/.config/nvim
```

---

## Getting Help

Online:
- GitHub Issues: https://github.com/petrolal/tetravim.nvim/issues
- Documentation: https://github.com/petrolal/tetravim.nvim
