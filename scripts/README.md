# TetraVim Scripts

## Quick Reference

### For End Users
```bash
bash bootstrap.sh
```
- Syncs all Lazy.nvim plugins headlessly
- Prepares your Neovim environment

### For Contributors & Local Development
```bash
bash scripts/dev-init.sh
```
- Symlinks `~/.config/nvim` → repository
- Syncs plugins with Lazy.nvim
- Fast setup for editing configuration in-place

---

## Validation & Test Suites

Most component assertions have been migrated into plenary busted specs under
`lua/tetravim/tests/` (one `*_spec.lua` per concern). The remaining
`scripts/validate*.sh` cover only the steps that need a real external binary
or a plugin the busted subprocess cannot load (`cmp`, `dap`, `conform`,
`kulala`, …).

- **Plenary Busted specs (the bulk of the coverage):**
  ```bash
  nvim --headless -u init.lua -c "Lazy! load plenary.nvim" -c "PlenaryBustedDirectory lua/tetravim/tests/"
  ```
- **Full distribution smoke test:**
  ```bash
  bash scripts/validate.sh
  ```
- **Remaining shell verification suites:**
  - `bash scripts/validate-3-4.sh`: gRPC/Protobuf — real `grpcurl` / `buf` / `protols` steps
  - `bash scripts/validate-db.sh`: DB explorer — `cmp`-source registration on sql buffers
  - `bash scripts/validate-http.sh`: HTTP client — real `jq` filter steps
  - `bash scripts/validate-4-1.sh`: Git 3-way conflict resolution (runtime-only)
  - `bash scripts/validate-completion.sh`: nvim-cmp + LuaSnip IntelliSense wiring (runtime-only)
  - `bash scripts/validate-dap-jvm.sh`: JVM DAP debugger & breakpoint controls (runtime-only)

