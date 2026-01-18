#!/bin/bash

set -e

# Start Jupyter notebook in background
jupyter notebook \
  --ip=0.0.0.0 \
  --port=8888 \
  --allow-root \
  --NotebookApp.token='' \
  --NotebookApp.password='' \
  --NotebookApp.disable_check_xsrf=True \
  --NotebookApp.allow_origin='*' &

# Start FastAPI
uvicorn src.app:app --host 0.0.0.0 --port 8000