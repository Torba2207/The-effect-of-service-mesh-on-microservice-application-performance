# 1. Base Image: Use a slim version of Python 3.11 to keep the image under 200MB
FROM python:3.11-slim

# 2. Install critical Linux utilities:
#   - curl: Needed by start.sh to download the Ollama archive.
#   - zstd: Needed by start.sh to extract the new Ollama .tar.zst format.
#   - procps: Needed by api.py (psutil) to read memory usage metrics.
RUN apt-get update && apt-get install -y curl zstd procps && rm -rf /var/lib/apt/lists/*

# 3. Set the working directory inside the container's isolated file system
WORKDIR /app

# 4. Copy and install Python dependencies (Done first to cache the layer and speed up rebuilds)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 5. Copy your application scripts into the container
COPY server.py .
COPY api.py .
COPY start.sh .

# 6. Sanitize Windows line endings (\r) so the bash script doesn't crash on Linux, 
#    and mark the script as executable.
RUN sed -i 's/\r$//' start.sh \
    && chmod +x start.sh

# 7. Expose the port the FastAPI Gateway runs on
EXPOSE 5005

# 8. Define the container's primary entry point
CMD ["./start.sh"]