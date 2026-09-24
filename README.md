# Hermes Pocket

Hermes Pocket is a USB-friendly launcher for [Hermes Agent](https://github.com/NousResearch/hermes-agent). It keeps the agent source, runtimes, configuration, sessions, memories, and installed skills inside one folder so the folder can be copied to an external SSD or USB drive.

This project is a clean launcher and runtime bootstrap inspired by the public
[Hermes-USB-Portable](https://github.com/techjarves/hermes-usb-portable) layout. It does not copy that repository's source. The Hermes Agent source is downloaded from Nous Research at setup time under its MIT license.

## Quick start on Windows

1. Download the latest release zip and extract it to a writable folder or USB drive.
2. Double-click `launch.bat`.
3. On first run, allow setup to download the local runtimes and Hermes dependencies.
4. Put one or more `.gguf` files in `model\` or `models\`, or install Ollama models with `ollama-model.cmd pull <model-name>`.
5. Hermes Pocket shows one combined picker containing local GGUF files and registered portable Ollama models, starts the selected backend, updates `data\config.yaml`, and launches Hermes against that model.

The first setup downloads roughly 1–1.6 GB when the CUDA bundle is enabled (less in CPU-only mode), depending on dependency and browser caches. Later launches use only the portable folder.

## Local llama.cpp / Llama Pocket

Hermes Agent cannot consume a `.gguf` file as a model endpoint by itself. Hermes Pocket therefore downloads the official `llama-server.exe` bundle once, scans the portable model folders, and exposes each selected GGUF through a local OpenAI-compatible endpoint. It also downloads a standalone Ollama runtime, stores its models in `ollamamodel\`, and includes Ollama's registered `/api/tags` models in the same picker. The selected endpoint is written into `data\config.yaml` before Hermes starts; when Hermes exits, the launcher stops only the model server process it started. On a CUDA-capable NVIDIA machine, the default config downloads and uses the CUDA 13.3 x64 llama.cpp bundle, and Ollama uses its GPU runtime automatically. Set `use_gpu` to `false` to force CPU mode for both backends.

Environment overrides:

- `HERMES_MODELS_DIR`: scan a different model directory instead of the portable `model\` and `models\` folders.
- `HERMES_MODEL`: select a specific GGUF filename or Ollama model name without showing the menu. Prefix an Ollama name with `ollama:` when needed.
- `hermes-pocket.json`: root config file. Set `model_directory`, `model_port`, `context_size`, and `max_output_tokens` here; the defaults are `model`, `11435`, 65536 context tokens, and 16384 output tokens. Context is the total prompt-plus-output window. The launcher sends `max_output_tokens` as an actual per-request `max_tokens` limit for local Ollama and GGUF models; Hermes itself ignores `model.max_tokens`. The limit includes thinking tokens, so a reasoning-heavy model can still reach it and need a continuation.
- GPU settings are `use_gpu`, `gpu_backend`, `gpu_layers`, `flash_attention`, `parallel`, and `gpu_fallback_to_cpu`. Set `use_gpu` to `false` to force CPU mode for llama.cpp and Ollama. `parallel: 1` is intentional for a 64k context because each additional slot increases KV-cache memory.
- `ollama.enabled`, `ollama.executable_path`, `ollama.models_directory`, `ollama.port`, and `ollama.disable_thinking` control the portable Ollama runtime. Thinking stays on by default; set `ollama.disable_thinking` to `true` only when you want it off. The managed provider sends the configured `num_ctx` and output cap to Ollama's current port. The default model store is `ollamamodel\`; loose files placed there are not Ollama models until imported or pulled through Ollama.
- Double-click `ollama-model.cmd` for an interactive manager, or use `ollama-model.cmd list` to list registered portable Ollama models. Use `ollama-model.cmd pull qwen3:8b` to download one, or pass another Ollama command such as `run` or `create`.
- `HERMES_CONTEXT_SIZE`: temporary environment override when no `context_size` is set in the root config.

This also works with a running Llama Pocket/llama.cpp server if you configure Hermes manually, but the default launch path is now fully local and model-folder driven.

## Portable layout

```text
hermes-pocket/
├── launch.bat             # Windows launcher
├── model/                 # place GGUF files here (not committed)
├── models/                # alternate model folder (not committed)
├── ollamamodel/           # portable Ollama model store (not committed)
├── ollama-model.cmd       # portable Ollama model manager
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
