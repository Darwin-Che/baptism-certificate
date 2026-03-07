FROM ccr-2vdh3abv-pub.cnc.bj.baidubce.com/paddlepaddle/paddleocr-vl:latest

RUN whoami

USER root

# System deps (minimal)
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

RUN pip install --upgrade pip

COPY requirements_ml.txt .

RUN pip install --no-cache-dir -r requirements_ml.txt

COPY requirements_hf.txt requirements_img.txt .

RUN pip install --no-cache-dir -r requirements_hf.txt
RUN pip install --no-cache-dir -r requirements_img.txt

# Pre-download models to /models volume

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

# Install light Python dependencies
COPY requirements.txt requirements_util.txt .

RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir -r requirements_util.txt

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
