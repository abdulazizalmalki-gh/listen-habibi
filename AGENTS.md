# AGENTS.md — listen-habibi

Arabic speech transcription Docker image using Cohere's Arabic ASR model via vLLM.

## Project Structure

```
/opt/stacks/cohere-transcribe-arabic/
  Dockerfile        — vllm/vllm-openai:v0.23.0 + model + ffmpeg + yt-dlp
  entrypoint.sh     — input → 16kHz mono WAV → vLLM → text output
  README.md         — human usage docs
  AGENTS.md          — this file
  cohere-transcribe-arabic-07-2026/  — model files (3.9GB, COPY'd into image)
```

## Docker Image Build

```bash
cd /opt/stacks/cohere-transcribe-arabic
DOCKER_BUILDKIT=0 docker build -t cohere-transcribe-arabic .
```

The model is downloaded to the build context first, then COPY'd into the image. No HF token baked in.

To update the model:
1. Delete `cohere-transcribe-arabic-07-2026/` from the build context
2. Re-download: `python3 -c "from huggingface_hub import snapshot_download; snapshot_download('CohereLabs/cohere-transcribe-arabic-07-2026', local_dir='cohere-transcribe-arabic-07-2026', token='$HF_TOKEN')"`
3. Rebuild

## Key Design Decisions

- **vLLM 0.23 not 0.24**: vLLM 0.24 doesn't recognize `CohereAsrForConditionalGeneration`. v0.23 does.
- **16kHz mono conversion**: vLLM's audio loading (soundfile/pyav) fails on large 48kHz stereo WAVs. All audio is resampled to 16kHz mono PCM before transcription.
- **`VLLM_MAX_AUDIO_CLIP_FILESIZE_MB=1000`**: Default limit is too low for real-world audio. Set to 1GB as ENV in Dockerfile (not runtime).
- **No `--max-model-len`**: The ASR model has `max_position_embeddings=1024`, and overriding it with a larger value crashes vLLM.
- **No `language` param in API call**: The cohere model auto-detects language. Passing `language` parameter is supported but defaults to auto-detect.
- **Model baked in via host COPY**: Token never touches the image layers. Downloaded on host, COPY'd in.
- **No librosa/soundfile in image**: Not needed — ffmpeg handles all audio conversion. Minimal dependencies.
- **Apache 2.0 license**: Both this project and the Cohere model are Apache 2.0 licensed.

## Debugging

If transcription fails with "Invalid or unsupported audio file":
1. Check audio is 16kHz mono WAV
2. Check file size < 1GB (set `VLLM_MAX_AUDIO_CLIP_FILESIZE_MB`)
3. Check vLLM log: `tail -50 /var/log/vllm.log`

If vLLM server dies:
```bash
docker run --gpus all --rm --entrypoint "" cohere-transcribe-arabic bash -c '
vllm serve /models/cohere-transcribe-arabic-07-2026 --host 0.0.0.0 --port 8000 --trust-remote-code
'
```

## Pushing to GHCR

```bash
docker tag cohere-transcribe-arabic ghcr.io/abdulazizalmalki-gh/listen-habibi:latest
docker push ghcr.io/abdulazizalmalki-gh/listen-habibi:latest
```

Requires `write:packages` token scope.
