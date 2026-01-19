import os

from fastapi import FastAPI, HTTPException, UploadFile, File, BackgroundTasks, Body
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import torch

from src.pipeline import pipeline
from src.upload_image import upload_image_handler
from src.storage import download_headshot, download_paper

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(BASE_DIR, "static")

app = FastAPI(
    title="Extraction Inference API",
    docs_url="/doc",
    redoc_url=None,
    openapi_url="/openapi.json"
)

# Serve static files
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

# Serve UI at root
@app.get("/")
def index():
    return FileResponse(os.path.join(STATIC_DIR, "index.html"))

@app.get("/health")
def health():
    gpu_available = torch.cuda.is_available()
    gpu_name = torch.cuda.get_device_name(0) if gpu_available else None

    return {
        "status": "ok",
        "gpu_available": gpu_available,
        "gpu_name": gpu_name
    }

class ExtractRequest(BaseModel):
    filename: str

@app.post("/extract")
def extract(request: ExtractRequest):
    filename = request.filename
    if not filename.endswith((".jpg", ".png", ".jpeg")):
        raise HTTPException(400, "Invalid image format")

    return pipeline(filename)


@app.post("/upload")
def upload_image_endpoint(file: UploadFile = File(...)):
    return upload_image_handler(file)

def delete_file(path: str):
    try:
        if os.path.exists(path):
            os.remove(path)
    except Exception as e:
        print(f"Failed to delete {path}: {e}")

@app.get("/headshot/{filename}")
def get_headshot(filename: str, background_tasks: BackgroundTasks):
    local_path = f"/tmp/headshot_{filename}"
    download_headshot(filename, local_path)
    background_tasks.add_task(delete_file, local_path)
    return FileResponse(local_path)

@app.get("/paper/{filename}")
def get_paper(filename: str, background_tasks: BackgroundTasks):
    local_path = f"/tmp/paper_{filename}"
    download_paper(filename, local_path)
    background_tasks.add_task(delete_file, local_path)
    return FileResponse(local_path)
