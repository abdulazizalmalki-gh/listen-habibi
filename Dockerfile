FROM vllm/vllm-openai:v0.23.0

ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir yt-dlp "vllm[audio]"

COPY cohere-transcribe-arabic-07-2026 /models/cohere-transcribe-arabic-07-2026

ENV VLLM_MAX_AUDIO_CLIP_FILESIZE_MB=1000

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
