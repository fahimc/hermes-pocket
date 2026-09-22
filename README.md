# Hermes Pocket

Hermes Pocket is a USB-friendly launcher for [Hermes Agent](https://github.com/NousResearch/hermes-agent). It keeps the agent source, runtimes, configuration, sessions, memories, and installed skills inside one folder so the folder can be copied to an external SSD or USB drive.

This project is a clean launcher and runtime bootstrap inspired by the public
[Hermes-USB-Portable](https://github.com/techjarves/hermes-usb-portable) layout. It does not copy that repository's source. The Hermes Agent source is downloaded from Nous Research at setup time under its MIT license.

## Quick start on Windows

1. Download the latest release zip and extract it to a writable folder or USB drive.
2. Double-click `launch.bat`.
3. On first run, allow setup to download the local runtimes and Hermes dependencies.
4. Put one or more `.gguf` files in `model\` or `models\`. With one file, it is selected automatically; with multiple files, the launcher shows a menu.
5. Hermes Pocket starts the local llama.cpp server, updates `data\config.yaml`, and then launches Hermes against that model.

The first setup downloads roughly 600 MB–1 GB depending on dependency and browser caches. Later launches use only the portable folder.

## Local llama.cpp / Llama Pocket

Hermes Agent cannot consume a `.gguf` file as a model endpoint by itself. Hermes Pocket therefore downloads the official CPU `llama-server.exe` once, scans the portable model folders, starts a server for the selected model on a free localhost port, and writes the custom OpenAI-compatible provider into `data\config.yaml` before starting Hermes. When Hermes exits, the launcher stops only the server process it started.

Environment overrides:

- `HERMES_MODELS_DIR`: scan a different model directory instead of the portable `model\` and `models\` folders.
- `HERMES_MODEL`: select a specific filename without showing the menu.
- `hermes-pocket.json`: root config file. Set `model_directory` and `context_size` here; the default is `model` and 65536 tokens. Hermes currently requires at least 64000 tokens for the main agent model.
- `HERMES_CONTEXT_SIZE`: temporary environment override when no `context_size` is set in the root config.

This also works with a running Llama Pocket/llama.cpp server if you configure Hermes manually, but the default launch path is now fully local and model-folder driven.

## Portable layout

```text
hermes-pocket/
├── launch.bat             # Windows launcher
├── model/                 # place GGUF files here (not committed)
├── models/                # alternate model folder (not committed)
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
