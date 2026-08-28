FROM python:3.11-slim

# Install system utilities, git, curl, jq, and build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    jq \
    ca-certificates \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Google Cloud & Python security/testing dependencies
RUN pip install --no-cache-dir \
    pytest \
    requests \
    google-genai \
    google-cloud-secret-manager \
    google-cloud-aiplatform \
    pyyaml

WORKDIR /app

# Copy runner orchestrator scripts
COPY fix_orchestrator.py /app/fix_orchestrator.py
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh /app/fix_orchestrator.py

ENTRYPOINT ["/app/entrypoint.sh"]
