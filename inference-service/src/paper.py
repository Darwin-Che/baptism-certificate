import cv2
import numpy as np
from insightface.app import FaceAnalysis

# Initialize face detector once
face_app = FaceAnalysis(name="buffalo_l")
face_app.prepare(ctx_id=0, det_size=(640, 640))

def extract_below_chin(img, chin_offset=0, center_ratio=0.05):
    """
    Extract the paper using center color sampling and convex hull.
    
    Args:
        img (np.ndarray): BGR image
        chin_offset (int): pixels below chin to start crop
        center_width_ratio (float): fraction of width around horizontal center for sampling

    Returns:
        np.ndarray: Cropped paper image
    """
    h, w, _ = img.shape

    # Detect face
    faces = face_app.get(img)
    if len(faces) == 0:
        crop_img = img
    else:
        f = faces[0]
        x1, y1, x2, y2 = map(int, f.bbox)
        crop_top = y2 + chin_offset
        crop_bottom = h
        face_middle = (x1 + x2) / 2
        face_width = (x2 - x1)
        crop_left = max(0, int(face_middle - face_width))
        crop_right = min(w, int(face_middle + face_width))
        crop_img = img[crop_top:crop_bottom, crop_left:crop_right]

    return crop_img

def extract_paper(input_path, output_path):
    img = cv2.imread(input_path)
    paper_crop = extract_below_chin(img)
    if paper_crop is None:
        print("Paper not found")
        return False
    rotated = paper_crop
    cv2.imwrite(output_path, rotated)

    return True