FROM runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404

# System deps (minimal)
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Python requirements and install
COPY requirements.txt .
RUN pip install --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

ENV INSIGHTFACE_HOME=/app/.cache/insightface
RUN mkdir -p /app/.cache/insightface

RUN python3 - <<EOF
import os
os.environ["INSIGHTFACE_HOME"] = "/app/.cache/insightface"
from insightface.app import FaceAnalysis
app = FaceAnalysis(name="buffalo_l")
app.prepare(ctx_id=-1, det_size=(640,640))
print("InsightFace model cached in volume path")
EOF

# Copy source code
COPY src ./src

# Create volume paths
RUN mkdir -p /app/data/models /app/data/outputs /app/data/logs

# Expose FastAPI & Jupyter ports
EXPOSE 8000 8888

# Copy entrypoint
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# Make src importable
ENV PYTHONPATH=/app

CMD ["/app/entrypoint.sh"]
