# Hermes Pocket

Hermes Pocket is a USB-friendly launcher for [Hermes Agent](https://github.com/NousResearch/hermes-agent). It keeps the agent source, runtimes, configuration, sessions, memories, and installed skills inside one folder so the folder can be copied to an external SSD or USB drive.

This project is a clean launcher and runtime bootstrap inspired by the public
[Hermes-USB-Portable](https://github.com/techjarves/hermes-usb-portable) layout. It does not copy that repository's source. The Hermes Agent source is downloaded from Nous Research at setup time under its MIT license.

## Quick start on Windows

1. Download the latest release zip and extract it to a writable folder or USB drive.
2. Double-click `launch.bat`.
3. On first run, allow setup to download the local runtimes and Hermes dependencies.
4. Run `hermes setup` or `hermes model` when prompted to configure a provider.

The first setup downloads roughly 600 MB–1 GB depending on dependency and browser caches. Later launches use only the portable folder.

## Local llama.cpp / Llama Pocket

Hermes Agent supports any OpenAI-compatible endpoint. To use a running local llama-server, run `hermes model`, choose **Custom endpoint**, and enter the server's `/v1` URL. Hermes can then use the local model for its agent loop, while its terminal, browser, memory, and skill tools run inside this portable folder. See the upstream provider documentation for the current configuration format.

## Portable layout

```text
hermes-pocket/
├── launch.bat             # Windows launcher
├── scripts/               # first-run setup and reset helpers
├── data/                  # private Hermes home; keep this backed up
├── src/                   # downloaded Hermes source (ignored by Git)
└── .cache/                # downloaded runtimes and package caches (ignored)
```

The launcher sets `HERMES_HOME`, `APPDATA`, `LOCALAPPDATA`, `UV_CACHE_DIR`, and `PLAYWRIGHT_BROWSERS_PATH` to folders under the portable root. It also disables Python user-site packages to avoid accidental host-environment imports.

## Security

`data/.env` can contain API keys, `data/auth.json` can contain login tokens, and sessions may contain private conversations. Treat the portable folder as sensitive data. Use BitLocker, VeraCrypt, or an encrypted external SSD if the drive leaves your control. The launcher downloads executable runtimes and the Hermes source from HTTPS URLs pinned in `scripts/setup-windows.ps1`; inspect that script before running it if you need a higher-assurance supply chain.

## License

The launcher scripts and project documentation are MIT licensed. Hermes Agent is a separate MIT-licensed dependency from Nous Research; its license is downloaded into the runtime/source area during setup and is also referenced in `THIRD_PARTY_NOTICES.md`.
