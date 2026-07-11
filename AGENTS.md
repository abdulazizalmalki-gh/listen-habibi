# AGENTS.md — listen-habibi

Arabic speech transcription Docker image using Cohere's Arabic ASR model via vLLM.

## Project Structure

```
/opt/stacks/cohere-transcribe-arabic/
  Dockerfile        — vllm/vllm-openai:v0.23.0 + vllm[audio] + ffmpeg + yt-dlp
  entrypoint.sh     — input → 16kHz mono → chunk 30s → vLLM → text output
  README.md         — human usage docs
  AGENTS.md         — this file
  cohere-transcribe-arabic-07-2026/  — model files (3.9GB, COPY'd into image)
```

## Docker Image Build

```bash
cd /opt/stacks/cohere-transcribe-arabic
DOCKER_BUILDKIT=0 docker build -t listen-habibi .
```

Model is downloaded to build context first, then COPY'd — no HF token in image layers.

## Key Design Decisions

- **vLLM 0.23 not 0.24**: 0.24 doesn't recognize `CohereAsrForConditionalGeneration`. v0.23 does.
- **`vllm[audio]` pip extra**: Base image lacks `av`/`soundfile` — audio loading fails without it.
- **16kHz mono conversion**: vLLM audio loading fails on large 48kHz stereo WAVs. All audio resampled.
- **30s chunking**: Model has `max_position_embeddings=1024` (~30s speech). Audio auto-split via ffmpeg.
- **`VLLM_MAX_AUDIO_CLIP_FILESIZE_MB=1000`**: ENV in Dockerfile. Default too low for real-world audio.
- **yt-dlp smart client**: Uses `player_client=android` (no JS needed) by default; switches to web client when `--cookies` provided.
- **Silent output**: Only progress indicators shown. Transcript written to file, not printed.
- **Model via host COPY**: Token never touches image layers. Downloaded on host, COPY'd in.
- **Apache 2.0**: Both project and Cohere model are Apache 2.0 licensed.

## Pipeline Flow

1. Download/extract audio (yt-dlp for YouTube, ffmpeg for local)
2. Convert to 16kHz mono PCM WAV
3. If >30s: split into 30s chunks via ffmpeg segment muxer
4. Start vLLM server (single-line spinner during ~50s startup)
5. Transcribe each chunk via `/v1/audio/transcriptions` (single-line progress counter)
6. Concatenate → write to output file
7. Print "Done. Transcription saved to <path>"

## Debugging

If transcription fails:
```bash
docker run --gpus all --rm --entrypoint "" listen-habibi bash -c '
export VLLM_MAX_AUDIO_CLIP_FILESIZE_MB=1000
vllm serve /models/cohere-transcribe-arabic-07-2026 --host 0.0.0.0 --port 8000 --trust-remote-code &>/tmp/vllm.log &
for i in $(seq 1 60); do curl -s http://localhost:8000/health >/dev/null 2>&1 && break; sleep 1; done
# Test with a short WAV
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=5" -acodec pcm_s16le -ar 16000 -ac 1 /tmp/t.wav 2>/dev/null
curl -s -X POST http://localhost:8000/v1/audio/transcriptions -F "file=@/tmp/t.wav" -F "model=/models/cohere-transcribe-arabic-07-2026"
tail -20 /tmp/vllm.log
'
```

## Pushing to GHCR

```bash
docker tag listen-habibi:latest ghcr.io/abdulazizalmalki-gh/listen-habibi:latest
docker push ghcr.io/abdulazizalmalki-gh/listen-habibi:latest
```

Requires `write:packages` token scope.
