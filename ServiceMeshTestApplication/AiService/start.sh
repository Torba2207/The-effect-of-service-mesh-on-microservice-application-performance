#!/bin/bash

# ---------------------------------------------------------
# PURPOSE:
#   The master boot script for the Docker container. It implements the 
#   "Bring Your Own Binary" (BYOB) pattern to keep the Docker image tiny.
#   It dynamically downloads the Ollama engine to a mapped Windows folder 
#   if it doesn't exist, boots the engine, and launches our Python servers.
#
# REQUIRES:
#   - A mapped volume at /app/ollama_engine (For the executable)
#   - A mapped volume at /root/.ollama (For the AI models)
#   - 'curl' and 'zstd' installed in the Dockerfile
# ---------------------------------------------------------

# 1. Define paths inside the mapped Windows volume
ENGINE_DIR="/app/data/ollama_engine"
ENGINE_BIN="$ENGINE_DIR/bin/ollama"

# 2. Dynamic Engine Download (The BYOB Pattern)
if [ ! -f "$ENGINE_BIN" ]; then
    echo "Engine missing! Downloading Zstandard archive to mapped volume..."
    
    # Auto-detect CPU architecture (Supports both standard PCs and ARM/Macs)
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ]; then
        DOWNLOAD_URL="https://ollama.com/download/ollama-linux-arm64.tar.zst"
    else
        DOWNLOAD_URL="https://ollama.com/download/ollama-linux-amd64.tar.zst"
    fi
    
    # Download the compressed engine directly into the mapped folder
    curl -L "$DOWNLOAD_URL" -o "$ENGINE_DIR/ollama.tar.zst"
    
    # Extract using 'zstd' (Forces tar to use the new compression algorithm)
    tar -I zstd -xf "$ENGINE_DIR/ollama.tar.zst" -C "$ENGINE_DIR"
    
    # Delete the zip file so we don't waste 2GB of hard drive space
    rm "$ENGINE_DIR/ollama.tar.zst"
else
    echo "Engine already exists in mapped volume! Skipping download."
fi

# 3. Boot the Ollama Engine in the background (&)
# We set max queues and parallel limits to optimize memory usage
OLLAMA_NUM_PARALLEL=4 OLLAMA_MAX_QUEUE=512 "$ENGINE_BIN" serve &
sleep 5

# 4. Wait for the Engine's HTTP API to fully wake up before proceeding
echo "Waiting for Ollama to initialize..."
while ! curl -s http://127.0.0.1:11434/api/tags > /dev/null; do
    sleep 1
done

# 5. Pull the required AI Model (Defaults to llama3.2 if not set)
CURRENT_MODEL="${TARGET_MODEL:-llama3.2}"
echo "Bash is checking if $CURRENT_MODEL is downloaded..."
"$ENGINE_BIN" pull "$CURRENT_MODEL"

# 6. Boot the FastMCP Tool Provider in the background (&)
echo "Starting FastMCP Procedural Server..."
python server.py &

# Give the server 3 seconds to successfully bind to port 8000
sleep 3

# 7. Boot the FastAPI Gateway in the FOREGROUND
# (Docker containers instantly shut down if their foreground process ends. 
# Running FastAPI here keeps the container alive permanently).
echo "Starting FastAPI Gateway..."
python api.py