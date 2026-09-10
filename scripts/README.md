# TetraVim Scripts

## Quick Reference

### For End Users

```bash
bash bootstrap.sh
```

- Syncs all Lazy.nvim plugins headlessly
- Prepares your Neovim environment

---

## Validation & Test Suites

All component validations and smoke tests have been migrated into native Plenary busted specs under
`lua/tetravim/tests/` (one `*_spec.lua` per concern). All former `scripts/validate-*.sh` scripts have
been decommissioned.

- **Plenary Busted specs (full suite):**
  ```bash
  nvim --headless -u init.lua -c "Lazy! load plenary.nvim" -c "PlenaryBustedDirectory lua/tetravim/tests/" -c "qa"
  ```
- **Test suite orchestrator:**
  ```bash
  bash scripts/validate.sh
  ```
- **Single spec file:**
  ```bash
  nvim --headless -u init.lua -c "Lazy! load plenary.nvim" -c "PlenaryBustedFile lua/tetravim/tests/smoke_spec.lua" -c "qa"
  ```
