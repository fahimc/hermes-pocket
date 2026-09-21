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

## Resume point

Validate the PowerShell setup script, create the GitHub repository, push the launcher source, and publish a small bootstrap release zip. The first run intentionally downloads runtimes and dependencies instead of redistributing a multi-gigabyte fully hydrated environment.
