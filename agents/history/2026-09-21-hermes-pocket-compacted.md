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
- Added config-driven CUDA support: the launcher downloads the official llama.cpp CUDA 13.3 x64 and cudart bundles into `.cache`, starts CUDA with all GPU layers, flash attention, one parallel slot, and falls back to the CPU bundle when configured.
- Added portable Ollama support modeled on the reference portable-codex runtime: setup downloads and checksum-validates the official Windows x64 Ollama ZIP, uses `ollamamodel/` as the portable `OLLAMA_MODELS` store, exposes `ollama-model.cmd` for `list`, `pull`, `run`, and `create`, and combines Ollama `/api/tags` models with GGUF files in the launcher picker.
- The same root `hermes-pocket.json` `use_gpu` flag controls both backends. Ollama receives the 64k context through `OLLAMA_CONTEXT_LENGTH`, uses its automatic CUDA runtime when enabled, and is forced to CPU with `OLLAMA_LLM_LIBRARY=cpu` when disabled.
- Created and pushed the public GitHub repository.

## Verification

- Both PowerShell scripts pass the PowerShell parser with no syntax errors.
- Bootstrap archive created successfully; no user credentials or hydrated runtime files are included.
- With `model/Spark-X2.5-4B-Q4_K_M.gguf`, model discovery, llama-server startup, config generation, and tracked-process cleanup all passed.
- `hermes-pocket.json` default `context_size: 65536` is written into Hermes config; the earlier 8192-token setting was rejected by Hermes' 64000-token minimum.
- The CUDA server started successfully for `Spark-X2.5-4B-Q4_K_M.gguf` with `context_size: 65536`, `parallel: 1`, `--n-gpu-layers all`, and `--flash-attn on`; a direct 16-token request measured about 82 tokens/second on the RTX 3060.
- The combined picker started portable Ollama on an available localhost port, discovered registered models from the reference Ollama store, selected `maternion/spark-x2.5-heretic:4b`, and wrote an `ollama-gpu` Hermes endpoint with context size 65536. `ollama-model.cmd list` also returned the two registered models. The manager and launcher cleanup stopped only their own Ollama process trees.
- Diagnosed a user-facing `APIConnectionError` as Hermes retrying a dead localhost endpoint: `data/config.yaml` referenced a previously stopped dynamic port (`127.0.0.1:56768/v1`) while no matching local server state/process existed. Fixed GGUF startup to prefer stable `model_port: 11435` and changed shutdown to remove the generated `model:` provider block, preventing stale endpoint reuse. Verified CUDA GGUF health on port 11435 and cleanup of both state and generated config.

## Release

- GitHub repository: https://github.com/fahimc/hermes-pocket
- Release: https://github.com/fahimc/hermes-pocket/releases/tag/v0.1.0
- Asset: `HermesPocket-win-x64.zip` (bootstrap folder, first-run setup required)
- Follow-up release: `v0.2.0` adds model-folder discovery, local llama.cpp startup, and root context configuration.
- Release: `v0.3.0` adds config-driven CUDA installation and GPU launch settings; asset `HermesPocket-v0.3.0-win-x64.zip` is published.
- Release: `v0.4.0` adds portable Ollama installation, model management, combined model selection, and shared GPU configuration; asset `HermesPocket-v0.4.0-win-x64.zip` is published.

## Known limitations

- Only the Windows x64 bootstrap path was validated in this environment.
- First-run setup needs internet access and downloads hundreds of megabytes of runtimes and packages.
- The release is a folder/launcher, not a single native executable, because Hermes depends on Python, Node, browser tooling, and its own source tree.
- A full agent response at 65536 context was not completed in this environment because a reasoning-heavy CPU inference run exceeded the interactive test window; CUDA server readiness, GPU launch flags, direct short request, Ollama discovery, and endpoint/config wiring passed.
- A manually started Hermes process can still retain an in-memory old endpoint if its model server is stopped externally; restart it through `launch.bat` after recovery rather than using a stale `data/config.yaml` directly.

## Resume point

For the next iteration, run a full 64k-context Hermes chat against both backends on suitable hardware and add a cross-platform Unix launcher if needed.
