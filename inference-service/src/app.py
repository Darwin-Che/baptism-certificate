from fastapi import FastAPI, HTTPException
import uuid
import os
import torch

from src.storage import download_image, upload_headshot, upload_paper
from src.face import extract_headshot
from src.paper import extract_paper
from src.timer import Timer

app = FastAPI(
    title="Extraction Inference API",
    docs_url="/",
    redoc_url=None,
    openapi_url="/openapi.json"
)

@app.get("/health")
def health():
    gpu_available = torch.cuda.is_available()
    gpu_name = torch.cuda.get_device_name(0) if gpu_available else None

    return {
        "status": "ok",
        "gpu_available": gpu_available,
        "gpu_name": gpu_name
    }

@app.post("/extract")
def extract(filename: str):
    gpu_name = torch.cuda.get_device_name(0) if torch.cuda.is_available() else "cpu"

    local_input = f"/tmp/{uuid.uuid4()}.jpg"
    local_output = f"/tmp/{uuid.uuid4()}_headshot.jpg"
    local_paper = f"/tmp/{uuid.uuid4()}_paper.jpg"

    timer = Timer()

    try:
        # Download from Tigris
        download_image(filename, local_input)
        timer.mark("download")

        # headshot
        headshot_result = extract_headshot(local_input, local_output)
        timer.mark("headshot_inference")
        if headshot_result:
            upload_headshot(filename, local_output)
            timer.mark("upload_headshot")

        # paper
        paper_result = extract_paper(local_input, local_paper)
        timer.mark("paper_inference")
        if paper_result:
            upload_paper(filename, local_paper)
            timer.mark("upload_paper")

        return {
            "status": "ok",
            "gpu": gpu_name,
            "filename": filename,
            "headshot_result": headshot_result,
            "paper_result": paper_result,
            "timing": timer.steps
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        # Clean up temporary files
        for f in [local_input, local_output, local_paper]:
            if os.path.exists(f):
                os.remove(f)