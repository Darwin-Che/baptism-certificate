import os
import uuid

from fastapi import HTTPException

import torch

from src.storage import download_image, upload_headshot, upload_paper, upload_headshot_rembg
from src.face import extract_headshot
from src.paper import extract_paper
from src.ocr import extract_ocr, parse_ocr
from src.timer import Timer
from src.facerembg import remove_background

def pipeline(filename: str):
    gpu_name = torch.cuda.get_device_name(0) if torch.cuda.is_available() else "cpu"

    id = uuid.uuid4()

    local_input = f"/tmp/{id}.jpg"
    local_output = f"/tmp/{id}_headshot.jpg"
    local_rembg_output = f"/tmp/{id}_headshot_rembg.png"
    local_paper = f"/tmp/{id}_paper.jpg"

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

        # Remove background
        facermbg_result = remove_background(local_output, local_rembg_output)
        timer.mark("remove_background")
        if facermbg_result:
            upload_headshot_rembg(filename, local_rembg_output)
            timer.mark("upload_headshot_rembg")

        # paper
        paper_result = extract_paper(local_input, local_paper)
        timer.mark("paper_inference")
        if paper_result:
            upload_paper(filename, local_paper)
            timer.mark("upload_paper")

        # OCR
        extract_ocr_result = extract_ocr(local_paper)
        timer.mark("extract_ocr_inference")
        parse_ocr_result = parse_ocr(extract_ocr_result.lower())
        timer.mark("parse_ocr_inference")

        return {
            "status": "ok",
            "gpu": gpu_name,
            "filename": filename,
            "headshot_result": headshot_result,
            "paper_result": paper_result,
            "extract_ocr_result": extract_ocr_result,
            "parse_ocr_result": parse_ocr_result,
            "timing": timer.steps
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        # Clean up temporary files
        for f in [local_input, local_output, local_rembg_output, local_paper]:
            if os.path.exists(f):
                os.remove(f)