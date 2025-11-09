FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/app/cache/hf \
    TRANSFORMERS_CACHE=/app/cache/hf \
    HUGGINGFACE_HUB_CACHE=/app/cache/hf \
    TTS_HOME=/app/cache/tts \
    DEMUCS_CACHE=/app/cache/demucs

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.11 \
        python3.11-venv \
        python3-pip \
        python3-dev \
        ffmpeg \
        libsndfile1 \
        build-essential \
        git \
        curl && \
    rm -rf /var/lib/apt/lists/*

RUN python3.11 -m pip install --upgrade pip

WORKDIR /app

COPY requirements.txt /tmp/requirements.txt

RUN python3.11 -m pip install -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

COPY app /app/app
COPY download_models /app/download_models

CMD ["python3.11", "-m", "app.worker"]
