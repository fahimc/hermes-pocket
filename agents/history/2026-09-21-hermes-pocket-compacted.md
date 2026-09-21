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
- Created and pushed the public GitHub repository.

## Verification

- Both PowerShell scripts pass the PowerShell parser with no syntax errors.
- Bootstrap archive created successfully; no user credentials or hydrated runtime files are included.

## Release

- GitHub repository: https://github.com/fahimc/hermes-pocket
- Release: https://github.com/fahimc/hermes-pocket/releases/tag/v0.1.0
- Asset: `HermesPocket-win-x64.zip` (bootstrap folder, first-run setup required)

## Known limitations

- Only the Windows x64 bootstrap path was validated in this environment.
- First-run setup needs internet access and downloads hundreds of megabytes of runtimes and packages.
- The release is a folder/launcher, not a single native executable, because Hermes depends on Python, Node, browser tooling, and its own source tree.

## Resume point

For the next iteration, run first-time setup on a clean folder with a test provider, add a cross-platform Unix launcher if needed, and optionally add a helper that writes a Hermes custom endpoint config for a running Llama Pocket server.
