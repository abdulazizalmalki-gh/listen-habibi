# listen-habibi 🎙️

Arabic speech transcription via [Cohere Transcribe Arabic](https://huggingface.co/CohereLabs/cohere-transcribe-arabic-07-2026), served with vLLM. Converts YouTube videos or local media files to Arabic text.

## Requirements

- NVIDIA GPU with **8GB+ VRAM** (model is 2B params, ~4GB BF16)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (`nvidia-docker`)
- Docker

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

### Supported Input Formats

| Type | Example |
|------|---------|
| YouTube URL | `https://youtu.be/xxx` or `https://www.youtube.com/watch?v=xxx` |
| Local video | Mount with `-v` and pass absolute container path (MP4, MKV, AVI, etc.) |
| Local audio | WAV, MP3, FLAC, OGG, M4A, AAC, OPUS (auto-converted to 16kHz mono WAV) |

> **Note:** vLLM's audio API only accepts 16kHz mono WAV. All input formats are auto-converted via ffmpeg.

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
| `Invalid or unsupported audio file` | Audio is auto-converted to 16kHz mono — if persistent, manually convert: `ffmpeg -i in.wav -acodec pcm_s16le -ar 16000 -ac 1 out.wav` |
| `Maximum file size exceeded` | Video too long — the Dockerfile already sets `VLLM_MAX_AUDIO_CLIP_FILESIZE_MB=1000` (1GB). Trim audio if still exceeding this. |
| GPU out of memory | Model needs ~6GB. Close other GPU processes. |
| YouTube 403 Forbidden | Rate limited — wait a few minutes or use a local file |

## License

This project is licensed under the Apache License 2.0 — see [LICENSE](LICENSE) for details.

The model ([CohereLabs/cohere-transcribe-arabic-07-2026](https://huggingface.co/CohereLabs/cohere-transcribe-arabic-07-2026)) is also Apache 2.0 licensed.
