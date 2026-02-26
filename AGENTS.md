# AGENTS.md

## Cursor Cloud specific instructions

This is a **Roblox/Luau game** ("BrainRot Clicker") managed with **Rojo** (filesystem-to-Roblox sync) and **Aftman** (toolchain manager).

### Key tools

| Tool | Version | Purpose |
|------|---------|---------|
| Aftman | 0.3.0 | Toolchain manager; installs Rojo. Binary at `~/.aftman/bin/aftman` |
| Rojo | 7.7.0-rc.1 | Syncs `src/` to Roblox Studio, builds `.rbxlx` place files |
| selene | 0.30.0 | Luau linter (installed at `/usr/local/bin/selene`) |
| StyLua | 2.3.1 | Luau formatter (installed at `/usr/local/bin/stylua`) |

### Common commands

- **Build**: `rojo build -o BrainRotClicker.rbxlx` — produces the Roblox place file
- **Sourcemap**: `rojo sourcemap -o sourcemap.json` — generates IDE sourcemap
- **Serve** (dev sync): `rojo serve` — starts live sync server for Roblox Studio (requires Studio on Windows/macOS to connect)
- **Lint**: `selene src/` — runs Luau linter (requires `selene.toml` and `roblox.yml` in workspace root)
- **Format check**: `stylua --check src/` — checks Luau formatting
- **Python test**: `python3 test_sectors.py` — validates item-to-sector categorization

### Important notes

- `~/.aftman/bin` must be on `PATH` for `rojo` to work. The update script handles this.
- First-time Aftman setup requires trusting tools: `aftman trust rojo-rbx/rojo && aftman install`. Subsequent runs of `aftman install` work without re-trusting.
- `selene` needs `selene.toml` (with `std = "roblox"`) and `roblox.yml` (generated via `selene generate-roblox-std`) in the workspace root to correctly parse Luau type annotations.
- The project has 2 pre-existing selene errors (`if_same_then_else`) and ~897 warnings (mostly `multiple_statements` style). These are not regressions.
- Full end-to-end game testing requires **Roblox Studio** (Windows/macOS desktop app) — not possible in a Linux cloud VM. `rojo build` and `selene` are the primary validation steps available here.
- `.rbxlx` and `sourcemap.json` are gitignored and should not be committed.
