import boto3
import os

s3 = boto3.client(
    "s3",
    endpoint_url=os.environ["AWS_ENDPOINT_URL_S3"],
    aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
    aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
    region_name=os.environ.get("AWS_REGION", "auto"),
)

BUCKET = os.environ["TIGRIS_BUCKET"]

def upload_image(filename: str, local_path: str):
    remote_path = f"raw_images/{filename}"
    s3.upload_file(local_path, BUCKET, remote_path)

def download_image(filename: str, local_path: str):
    remote_path = f"raw_images/{filename}"
    s3.download_file(BUCKET, remote_path, local_path)

def upload_headshot(filename: str, local_path: str):
    remote_path = f"headshots/{filename}"
    s3.upload_file(local_path, BUCKET, remote_path, ExtraArgs={"ContentType": "image/jpeg"})

def download_headshot(filename: str, local_path: str):
    remote_path = f"headshots/{filename}"
    s3.download_file(BUCKET, remote_path, local_path)

def upload_headshot_rembg(filename: str, local_path: str):
    remote_path = f"headshots_rembg/{filename}"
    s3.upload_file(local_path, BUCKET, remote_path, ExtraArgs={"ContentType": "image/png"})

def upload_paper(filename: str, local_path: str):
    remote_path = f"papers/{filename}"
    s3.upload_file(local_path, BUCKET, remote_path, ExtraArgs={"ContentType": "image/jpeg"})

def download_paper(filename: str, local_path: str):
    remote_path = f"papers/{filename}"
    s3.download_file(BUCKET, remote_path, local_path)