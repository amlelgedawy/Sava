FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements-django.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements-django.txt

# Copy application code
COPY . .

# Collect static files
RUN python manage.py collectstatic --noinput

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/api/health || exit 1

# Start command
# IMPORTANT: keep --workers 1. StreamManager buffers video frames in
# process-local RAM, so multiple workers can't see each other's frames and the
# live stream breaks. --threads keeps requests (incl. MJPEG) concurrent.
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "1", "--threads", "8", "--timeout", "120"]
