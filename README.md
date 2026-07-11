# listen-habibi 🎙️

Arabic speech transcription via [Cohere Transcribe Arabic](https://huggingface.co/CohereLabs/cohere-transcribe-arabic-07-2026), served with vLLM. Converts YouTube videos or local media files to Arabic text.

## Requirements

- NVIDIA GPU with **8GB+ VRAM** (model is 2B params, ~4GB BF16)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (`nvidia-docker`)
- Docker
- **~34GB disk space** for the image (vLLM + CUDA + baked-in model)
- **~70GB free disk** during `docker pull` (Docker temporarily stores compressed + uncompressed layers)

## Quick Start

```bash
# Pull from GitHub Container Registry
docker pull ghcr.io/abdulazizalmalki-gh/listen-habibi:latest

# Transcribe a YouTube video (output → ./transcript.txt)
docker run --gpus all --rm -v $(pwd):/output \
  ghcr.io/abdulazizalmalki-gh/listen-habibi \
  "https://youtu.be/xxx"

# Transcribe a local video/audio file
docker run --gpus all --rm \
  -v $(pwd):/output \
  -v /path/to/video.mp4:/data/media.mp4 \
  ghcr.io/abdulazizalmalki-gh/listen-habibi \
  "/data/media.mp4"
```

## Usage

```
docker run --gpus all --rm [options] listen-habibi [--output PATH] [--language ar|en] <input>
```

| Argument | Description |
|----------|-------------|
| `<input>` | YouTube URL or absolute path to video/audio file inside container |
| `--output, -o` | Output text file path (default: `/output/transcript.txt`) |
| `--language, -l` | `ar` for Arabic, `en` for English (default: `ar`) |
| `--cookies, -c` | Path to Netscape cookies file (optional, avoids YouTube rate-limiting) |

### Using Cookies (Optional)

To avoid YouTube rate-limiting, export cookies from your browser in **Netscape format** (use [Get cookies.txt](https://chrome.google.com/webstore/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc) for Chrome, or the `--cookies-from-browser` flag) and mount:

```bash
docker run --gpus all --rm \
  -v $(pwd):/output \
  -v ~/cookies.txt:/cookies.txt \
  ghcr.io/abdulazizalmalki-gh/listen-habibi \
  --cookies /cookies.txt \
  "https://youtu.be/xxx"
```

Cookies are optional — the image works without them, but authenticated users may see fewer blocks.

### Supported Input Formats

| Type | Example |
|------|---------|
| YouTube URL | `https://youtu.be/xxx` or `https://www.youtube.com/watch?v=xxx` |
| Local video | Mount with `-v` and pass absolute container path (MP4, MKV, AVI, etc.) |
| Local audio | WAV, MP3, FLAC, OGG, M4A, AAC, OPUS (auto-converted to 16kHz mono WAV) |

> **Note:** vLLM's audio API only accepts 16kHz mono WAV. All input formats are auto-converted via ffmpeg. Audio longer than 30s is automatically split into chunks for the model's context window.

### How It Works

1. Downloads/extracts audio (YouTube via yt-dlp, local via ffmpeg)
2. Converts to 16kHz mono WAV for vLLM compatibility
3. Splits audio into 30-second chunks (model context: 1024 tokens)
4. Transcribes each chunk via vLLM's OpenAI-compatible `/v1/audio/transcriptions`
5. Concatenates and writes result to output file

Output is silent except for progress indicators — the transcript is written to the file, not printed to terminal.

### Volume Mounts

| Mount | Purpose |
|-------|---------|
| `-v $(pwd):/output` | Where the transcript file is written |
| `-v /host/path:/data/file` | Mount local media files into the container |

## Model

- **Model**: [CohereLabs/cohere-transcribe-arabic-07-2026](https://huggingface.co/CohereLabs/cohere-transcribe-arabic-07-2026)
- **Size**: 2B params, BF16 (~4GB VRAM)
- **Architecture**: Conformer encoder-decoder
- **Languages**: Arabic, English (code-switching supported)
- **License**: Apache 2.0
- **Engine**: vLLM 0.23 with `--trust-remote-code`

## Build from Source

```bash
# 1. Download model (requires HF token — accept terms at model page first)
HF_TOKEN=your_token python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('CohereLabs/cohere-transcribe-arabic-07-2026',
    local_dir='cohere-transcribe-arabic-07-2026', token='$HF_TOKEN')
"

# 2. Build image
DOCKER_BUILDKIT=0 docker build -t listen-habibi .

# 3. Run
docker run --gpus all --rm -v $(pwd):/output listen-habibi "https://youtu.be/xxx"
```

## Example

```bash
# Transcribe an Arabic podcast
docker run --gpus all --rm -v $(pwd):/output \
  ghcr.io/abdulazizalmalki-gh/listen-habibi \
  "https://youtu.be/ulDugCU4L1M"

# Output saved to ./transcript.txt
cat transcript.txt
```

## Troubleshooting

| Error | Fix |
|-------|-----|
| GPU out of memory | Model needs ~6GB VRAM. Close other GPU processes. |
| YouTube 403 Forbidden | Rate limited — wait a few minutes or use a local file |

## License

This project is licensed under the Apache License 2.0 — see [LICENSE](LICENSE) for details.

The model ([CohereLabs/cohere-transcribe-arabic-07-2026](https://huggingface.co/CohereLabs/cohere-transcribe-arabic-07-2026)) is also Apache 2.0 licensed.

## Disclaimer

- YouTube and all related trademarks and logos are the property of Google LLC.
- Cohere and all related trademarks and logos are the property of Cohere Inc.
- Users are responsible for complying with the terms of service of any platform they interact with.
- Do not use this tool to infringe on anyone's rights, privacy, or intellectual property.
- The authors assume no liability for any misuse of this software.
