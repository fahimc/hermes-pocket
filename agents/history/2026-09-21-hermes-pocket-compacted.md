# Hermes Pocket — initial design

## Purpose

Create a USB-friendly launcher for Hermes Agent that keeps its runtime, source, configuration, sessions, memory, and skills inside one portable folder.

## Decisions

- Repository directory: `I:/Projects/hermes-pocket`.
- Planned repository: `fahimc/hermes-pocket`.
- Windows x64 is the first tested target; `launch.bat` is the primary entry point.
- Hermes source is downloaded from Nous Research at pinned commit `743ee72596e7a9f23bc7cd5c570a6ebd958043e4`.
- Portable runtimes are downloaded into `.cache/runtimes/windows-x64`; user data is under `data/`.
- The linked `techjarves/Hermes-USB-Portable` project is reference material only; its source is not copied.

## Completed work

- Added `launch.bat` with local `HERMES_HOME`, isolated Python/Node/uv/Git paths, and USB-safe cache locations.
- Added a pinned Windows setup script for Python 3.11, Node 22, uv, ripgrep, MinGit, Hermes source, dependencies, and optional Chromium.
- Added reset support, example environment configuration, notices, and security guidance.
- Added automatic GGUF discovery from the portable `model/` or `models/` folder, interactive selection when multiple files exist, and a root `hermes-pocket.json` config.
- Added a pinned CPU llama.cpp server bootstrap and launcher lifecycle scripts that write Hermes' custom `/v1` endpoint before launch and stop only the tracked server afterward.
- Created and pushed the public GitHub repository.

## Verification

- Both PowerShell scripts pass the PowerShell parser with no syntax errors.
- Bootstrap archive created successfully; no user credentials or hydrated runtime files are included.
- With `model/Spark-X2.5-4B-Q4_K_M.gguf`, model discovery, llama-server startup, config generation, and tracked-process cleanup all passed.
- `hermes-pocket.json` default `context_size: 65536` is written into Hermes config; the earlier 8192-token setting was rejected by Hermes' 64000-token minimum.

## Release

- GitHub repository: https://github.com/fahimc/hermes-pocket
- Release: https://github.com/fahimc/hermes-pocket/releases/tag/v0.1.0
- Asset: `HermesPocket-win-x64.zip` (bootstrap folder, first-run setup required)
- Follow-up release: `v0.2.0` adds model-folder discovery, local llama.cpp startup, and root context configuration.

## Known limitations

- Only the Windows x64 bootstrap path was validated in this environment.
- First-run setup needs internet access and downloads hundreds of megabytes of runtimes and packages.
- The release is a folder/launcher, not a single native executable, because Hermes depends on Python, Node, browser tooling, and its own source tree.
- A full agent response at 65536 context was not completed in this environment because CPU inference on the 4B model exceeded the interactive test window; server readiness and config wiring passed.

## Resume point

For the next iteration, optimize CPU defaults or add a GPU backend option, run a full 64k-context Hermes chat on suitable hardware, and add a cross-platform Unix launcher if needed.
