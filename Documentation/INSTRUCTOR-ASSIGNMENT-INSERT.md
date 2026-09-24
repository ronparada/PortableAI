# Portable Offline AI

Copy or extract the complete `PortableAI` folder onto the large data partition of the USB drive. Do not place it on `VTOYEFI`.

The standard activity uses **Qwen 3 4B**, a local language model suited to general questions and coding assistance. An optional second model, **Nous Hermes 3 Llama 3.2 3B**, is also available as an alternate offline chatbot.

## Student steps

### Windows

1. Open `PortableAI/Windows` and read `README-FIRST.txt`.
2. Double-click `1-SETUP-PORTABLE-CHAT.cmd` and choose option 1.
3. Double-click `2-START-QWEN-CHAT.cmd`.

### macOS

1. Open `PortableAI/macOS` and read `README-FIRST.txt`.
2. Open Terminal, type `bash `, drag `1-SETUP-PORTABLE-CHAT.sh` into Terminal, and press Return.
3. Run `2-START-QWEN-CHAT.sh` the same way.

### Linux

1. Open a terminal in `PortableAI/Linux`.
2. Run `bash 1-SETUP-PORTABLE-CHAT.sh`, choose option 1, then run `bash 2-START-QWEN-CHAT.sh`.

Setup requires internet access only when the correct engine or model is missing. Afterward, disconnect from the internet and demonstrate that the chat at `http://127.0.0.1:18765` answers a short question. Record the operating system and model tested. Run file 4 if a previous session was closed without stopping its server.

Allow about 2.7 GB for the standard Qwen setup or about 4.7 GB for both models and the cross-platform files. At least 8 GB of system RAM is recommended.
