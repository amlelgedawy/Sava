FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for torch, opencv, and mediapipe
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libxcb1 \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install CPU-only PyTorch first (smaller than CUDA version)
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# Install remaining Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Start command
CMD ["waitress-serve", "--host", "0.0.0.0", "--port", "8000", "activity_server:app"]
