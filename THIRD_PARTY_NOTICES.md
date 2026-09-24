# Third-party notices

## Hermes Agent

Hermes Pocket downloads the Hermes Agent source from
[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) at a
pinned commit during setup. Hermes Agent is MIT licensed. The source and its
license remain in the user's portable folder under `src/hermes-agent/`.

## Portable runtimes

The setup script downloads these independent upstream distributions into
`.cache/runtimes/windows-x64/`:

- CPython from python-build-standalone
- Node.js LTS
- uv
- ripgrep
- MinGit
- Playwright Chromium, when available
- Ollama standalone Windows x64 runtime, when enabled in `hermes-pocket.json`

Each project retains its own license and notices in the downloaded files.

## Reference project

The folder-oriented isolation design was informed by the public
[Hermes-USB-Portable](https://github.com/techjarves/hermes-usb-portable)
project. No source files from that repository are redistributed here.
