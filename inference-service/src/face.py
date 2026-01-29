import cv2
from insightface.app import FaceAnalysis

print("Loading InsightFace model...")
app = FaceAnalysis(name="buffalo_l")
app.prepare(ctx_id=0, det_size=(640, 640))
print("InsightFace model ready")

def extract_headshot(input_path: str, output_path: str):
    img = cv2.imread(input_path)
    if img is None:
        return False

    faces = app.get(img)
    if len(faces) == 0:
        return False

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
