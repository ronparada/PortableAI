# Portable Offline AI technical notes

This kit runs local GGUF language models through `llama.cpp`. The models, downloaded runtimes, cache, logs, and temporary files stay under `_PortableAI-System` on the USB.

## Student workflow

The first setup menu has three choices:

1. Qwen 3 4B only, recommended, approximately 2.7 GB with runtime files.
2. Qwen 3 4B plus Nous Hermes 3 3B, approximately 4.7 GB.
3. Nous Hermes 3 3B only, approximately 2.2 GB.

The former “chat engine only” choice was removed because it produced a setup that students could not use until they separately added a model.

| Model | Role | Approximate model size |
|---|---|---:|
| Qwen 3 4B Q4_K_M | Recommended general and coding assistant | 2.50 GB |
| Nous Hermes 3 Llama 3.2 3B Q4_K_M | Optional alternate instruction model | 2.02 GB |

“Nous Hermes 3” is the model’s real name. It is a fine-tuned Llama 3.2 3B language model published by Nous Research. In this kit it runs as an ordinary browser chatbot.

## Security software

The standard kit downloads release binaries from the official `llama.cpp` project and model files from Hugging Face, then verifies pinned SHA-256 hashes before using them. Executables downloaded to removable media can still trigger endpoint-security policy or reputation warnings.

Do not tell students to disable antivirus protection or add broad exclusions. Record the exact file and detection, retain the hash, and have campus IT review or allow-list the approved package. The standard Qwen workflow should remain the classroom baseline.

## Portability limits

- Windows x64 uses a Vulkan runtime first and falls back to CPU. The package deploys signed Microsoft Visual C++ runtime DLLs beside the x64 executable, which supports portable use without changing Windows. Windows ARM64 uses CPU and may require the Microsoft runtime on the host until an ARM64 app-local bundle is added and tested.
- Apple Silicon and Intel macOS have separate runtimes.
- Linux packages target current Ubuntu-compatible x64 or ARM64 systems.
- The USB must allow large files; exFAT is suitable for the model files and all three desktop operating systems.
- Running from a slow flash drive increases model load time. Once loaded, CPU, RAM, and GPU performance matter more than USB transfer speed.

## Distribution

The GitHub/source ZIP excludes models, runtimes, downloads, and generated data. Students run setup to retrieve the selected files. A prepared classroom USB may include verified models and one or more runtimes. The runtime for a different operating system can be added to the same folder during first use.

Upstream projects:

- Engine: <https://github.com/ggml-org/llama.cpp>
- Qwen model conversion: <https://huggingface.co/bartowski/Qwen_Qwen3-4B-GGUF>
- Nous Hermes model conversion: <https://huggingface.co/bartowski/Hermes-3-Llama-3.2-3B-GGUF>
- Microsoft C++ local deployment guidance: <https://learn.microsoft.com/cpp/windows/choosing-a-deployment-method>
