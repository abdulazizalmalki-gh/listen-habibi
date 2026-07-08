#!/bin/bash
set -euo pipefail

# Use local model if baked into image, otherwise download from HF
LOCAL_MODEL="/models/cohere-transcribe-arabic-07-2026"
if [[ -d "$LOCAL_MODEL" ]]; then
    MODEL="$LOCAL_MODEL"
else
    MODEL="CohereLabs/cohere-transcribe-arabic-07-2026"
fi
OUTPUT_FILE="${OUTPUT_FILE:-/output/transcript.txt}"
MODEL_DIR="${MODEL_DIR:-/models}"
HF_HOME="${HF_HOME:-/models/.cache}"
VLLM_PORT="${VLLM_PORT:-8000}"
MAX_WAIT="${MAX_WAIT:-300}"

export HF_HOME

# ── Parse args ──────────────────────────────────────────────
INPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o)
            OUTPUT_FILE="$2"; shift 2 ;;
        --language|-l)
            LANGUAGE="$2"; shift 2 ;;
        *)
            INPUT="$1"; shift ;;
    esac
done

if [[ -z "$INPUT" ]]; then
    echo "USAGE: docker run ... cohere-transcribe-arabic [--output /path/out.txt] <youtube-url|/path/to/video.mp4>"
    echo ""
    echo "  INPUT: YouTube URL or absolute path to a video/audio file inside the container"
    echo "  --output, -o: output text file path (default: /output/transcript.txt)"
    echo "  --language, -l: 'ar' or 'en' (default: ar)"
    echo ""
    echo "Environment:"
    echo "  HF_TOKEN     HuggingFace token (required for first-run model download)"
    echo "  OUTPUT_FILE  default output path (overridden by --output)"
    echo "  VLLM_PORT    vLLM server port (default 8000)"
    echo "  MAX_WAIT     max seconds to wait for server (default 300)"
    exit 1
fi

# Set default language
LANGUAGE="${LANGUAGE:-ar}"

# ── Prepare audio file ──────────────────────────────────────
AUDIO_FILE=""
CLEANUP_AUDIO=0

if [[ "$INPUT" =~ ^https?:// ]]; then
    echo "==> Downloading YouTube audio: $INPUT"
    WORKDIR=$(mktemp -d)
    CLEANUP_AUDIO=1
    yt-dlp -x --audio-format wav --audio-quality 0 \
        -o "$WORKDIR/audio_raw.%(ext)s" \
        --no-playlist \
        "$INPUT"
    # Resample to 16kHz mono for memory efficiency
    ffmpeg -y -i "$WORKDIR/audio_raw.wav" \
        -acodec pcm_s16le -ar 16000 -ac 1 \
        "$WORKDIR/audio.wav" 2>/dev/null
    rm -f "$WORKDIR/audio_raw.wav"
    AUDIO_FILE="$WORKDIR/audio.wav"
    if [[ -z "$AUDIO_FILE" ]]; then
        echo "ERROR: Failed to download/extract audio from YouTube URL"
        exit 1
    fi
elif [[ -f "$INPUT" ]]; then
    # Check if it's already audio or if we need to extract
    EXT="${INPUT##*.}"
    if [[ "$EXT" =~ ^(wav|mp3|flac|ogg|m4a|aac|opus)$ ]]; then
        echo "==> Using audio file: $INPUT"
        AUDIO_FILE="$INPUT"
    else
        echo "==> Extracting audio from video: $INPUT"
        WORKDIR=$(mktemp -d)
        CLEANUP_AUDIO=1
        ffmpeg -y -i "$INPUT" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$WORKDIR/audio_raw.wav" 2>/dev/null
        AUDIO_FILE="$WORKDIR/audio_raw.wav"
    fi
else
    echo "ERROR: Input is not a valid URL or existing file: $INPUT"
    exit 1
fi

# ── Ensure 16kHz mono WAV for vLLM compatibility ────────────
if [[ "$AUDIO_FILE" != *.wav ]] || ! ffprobe -v quiet -show_streams "$AUDIO_FILE" 2>/dev/null | grep -q "sample_rate=16000"; then
    echo "==> Converting to 16kHz mono WAV..."
    if [[ $CLEANUP_AUDIO -eq 0 ]]; then
        WORKDIR=$(mktemp -d)
        CLEANUP_AUDIO=1
    fi
    CONVERTED="$WORKDIR/audio_16k.wav"
    ffmpeg -y -i "$AUDIO_FILE" -acodec pcm_s16le -ar 16000 -ac 1 "$CONVERTED" 2>/dev/null
    AUDIO_FILE="$CONVERTED"
fi

echo "==> Audio file ready: $AUDIO_FILE ($(du -h "$AUDIO_FILE" | cut -f1))"

# ── Start vLLM server ───────────────────────────────────────
echo "==> Starting vLLM server on port $VLLM_PORT..."
export VLLM_MAX_AUDIO_CLIP_FILESIZE_MB=1000
vllm serve "$MODEL" \
    --host 0.0.0.0 \
    --port "$VLLM_PORT" \
    --trust-remote-code \
    --download-dir "$MODEL_DIR" \
    &>/var/log/vllm.log &
VLLM_PID=$!

# ── Wait for vLLM readiness ─────────────────────────────────
echo "==> Waiting for vLLM server (PID $VLLM_PID) to be ready..."
WAITED=0
while ! curl -s "http://localhost:$VLLM_PORT/health" >/dev/null 2>&1; do
    if ! kill -0 "$VLLM_PID" 2>/dev/null; then
        echo "ERROR: vLLM server died. Last 50 lines of log:"
        tail -50 /var/log/vllm.log
        exit 1
    fi
    sleep 2
    WAITED=$((WAITED + 2))
    if [[ $WAITED -ge $MAX_WAIT ]]; then
        echo "ERROR: vLLM server did not start within ${MAX_WAIT}s"
        tail -50 /var/log/vllm.log
        exit 1
    fi
    echo "   ... ${WAITED}s elapsed"
done
echo "==> vLLM server ready after ${WAITED}s"

# ── Transcribe ──────────────────────────────────────────────
echo "==> Transcribing (language=${LANGUAGE})..."
RESPONSE=$(curl -s -X POST "http://localhost:$VLLM_PORT/v1/audio/transcriptions" \
    -F "file=@$AUDIO_FILE" \
    -F "model=$MODEL")

# Check for error in response
if echo "$RESPONSE" | grep -q '"error"'; then
    echo "ERROR: Transcription API returned error:"
    echo "$RESPONSE" | python3 -m json.tool
    kill "$VLLM_PID" 2>/dev/null || true
    [[ $CLEANUP_AUDIO -eq 1 ]] && rm -rf "$WORKDIR"
    exit 1
fi

# Extract text from response
TEXT=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['text'])")

# ── Write output ────────────────────────────────────────────
mkdir -p "$(dirname "$OUTPUT_FILE")"
echo "$TEXT" > "$OUTPUT_FILE"
echo "==> Transcription written to: $OUTPUT_FILE"
echo "==> Transcript preview:"
echo "────────────────────────────────────────────"
echo "$TEXT"
echo "────────────────────────────────────────────"

# ── Cleanup ─────────────────────────────────────────────────
[[ $CLEANUP_AUDIO -eq 1 ]] && rm -rf "$WORKDIR"

# Stop vLLM gracefully
kill "$VLLM_PID" 2>/dev/null || true
wait "$VLLM_PID" 2>/dev/null || true

echo "==> Done."
