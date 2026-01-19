import hashlib
import os
import uuid

from fastapi import UploadFile, File, HTTPException

from src.storage import upload_image

TMP_DIR = "/tmp"
ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".webp"}

def hash_file(path: str) -> str:
    sha256 = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def save_upload_to_tmp(file: UploadFile) -> str:
    ext = os.path.splitext(file.filename)[1].lower()
    if ext not in ALLOWED_EXT:
        raise ValueError("Unsupported file format")

    tmp_path = f"{TMP_DIR}/{uuid.uuid4()}{ext}"

    with open(tmp_path, "wb") as f:
        while True:
            chunk = file.file.read(1024 * 1024)
            if not chunk:
                break
            f.write(chunk)

    return tmp_path

def upload_image_handler(file: UploadFile = File(...)):
    try:
        # Save to temp
        tmp_path = save_upload_to_tmp(file)

        # Hash content
        file_hash = hash_file(tmp_path)
        ext = os.path.splitext(file.filename)[1].lower()
        final_filename = f"{file_hash}{ext}"

        # Upload to storage (Tigris)
        upload_image(final_filename, tmp_path)

        return {
            "status": "ok",
            "filename": final_filename,
            "hash": file_hash
        }

    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    finally:
        if "tmp_path" in locals() and os.path.exists(tmp_path):
            os.remove(tmp_path)