import cv2
import numpy as np
from insightface.app import FaceAnalysis

print("Loading InsightFace model...")
app = FaceAnalysis(name="buffalo_l")
app.prepare(ctx_id=0, det_size=(640, 640))
print("InsightFace model ready")


def calculate_rotation_angle(face):
    """Calculate rotation angle based on eye positions to straighten the head."""
    kps = face.kps  # Facial landmarks from InsightFace
    left_eye = kps[0]   # Left eye
    right_eye = kps[1]  # Right eye
    
    # Calculate angle between eyes
    dx = right_eye[0] - left_eye[0]
    dy = right_eye[1] - left_eye[1]
    angle = np.degrees(np.arctan2(dy, dx))
    
    return angle


def rotate_image(img, angle, center):
    """Rotate image around center point to correct tilt."""
    h, w = img.shape[:2]
    M = cv2.getRotationMatrix2D(center, angle, 1.0)
    
    # Calculate new image size to prevent cropping
    cos = np.abs(M[0, 0])
    sin = np.abs(M[0, 1])
    new_w = int((h * sin) + (w * cos))
    new_h = int((h * cos) + (w * sin))
    
    # Adjust translation to keep image centered
    M[0, 2] += (new_w / 2) - center[0]
    M[1, 2] += (new_h / 2) - center[1]
    
    rotated = cv2.warpAffine(img, M, (new_w, new_h), 
                             flags=cv2.INTER_CUBIC,
                             borderMode=cv2.BORDER_REPLICATE)
    return rotated


def extract_headshot(input_path: str, output_path: str):
    img = cv2.imread(input_path)
    if img is None:
        return False

    faces = app.get(img)
    if len(faces) == 0:
        return False

    best_face = max(faces, key=lambda f: (f.bbox[2]-f.bbox[0]) * (f.bbox[3]-f.bbox[1]))
    
    # Calculate rotation angle to straighten head
    angle = calculate_rotation_angle(best_face)
    
    # Only rotate if tilt is significant (> 2 degrees)
    if abs(angle) > 2:
        # Get face center for rotation
        x1, y1, x2, y2 = best_face.bbox
        center = ((x1 + x2) / 2, (y1 + y2) / 2)
        img = rotate_image(img, angle, center)
        
        # Re-detect face in rotated image for accurate bounding box
        faces = app.get(img)
        if len(faces) > 0:
            best_face = max(faces, key=lambda f: (f.bbox[2]-f.bbox[0]) * (f.bbox[3]-f.bbox[1]))
    
    x1, y1, x2, y2 = map(int, best_face.bbox)

    h, w, _ = img.shape
    pad = int(0.30 * (y2 - y1))

    x1 = max(0, x1 - pad)
    y1 = max(0, y1 - pad)
    x2 = min(w, x2 + pad)
    y2 = min(h, y2 + pad)

    headshot = img[y1:y2, x1:x2]
    cv2.imwrite(output_path, headshot)

    return True
