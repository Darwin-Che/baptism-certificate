import cv2
import numpy as np
from insightface.app import FaceAnalysis

# Initialize face detector once
face_app = FaceAnalysis(name="buffalo_l")
face_app.prepare(ctx_id=0, det_size=(640, 640))

def extract_paper_center_color(img, chin_offset=0, center_ratio=0.05):
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
        crop_img = img[crop_top:crop_bottom, :]

    ch, cw, _ = crop_img.shape

    # Sample middle box to estimate paper color
    slice_w = max(1, int(cw * center_ratio))
    slice_h = max(1, int(ch * center_ratio))
    mid_start_w = cw // 2 - slice_w // 2
    mid_end_w = mid_start_w + slice_w
    mid_start_h = ch // 2 - slice_h // 2
    mid_end_h = mid_start_h + slice_h
    center_slice = crop_img[mid_start_h:mid_end_h, mid_start_w:mid_end_w]

    # Compute average color in BGR
    avg_color = np.mean(center_slice.reshape(-1, 3), axis=0)

    # Compute mask of pixels close to average (paper)
    diff = cv2.absdiff(crop_img, avg_color.astype(np.uint8))
    diff_gray = cv2.cvtColor(diff, cv2.COLOR_BGR2GRAY)
    _, mask = cv2.threshold(diff_gray, 20, 255, cv2.THRESH_BINARY_INV)

    # Find largest contour
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None

    # Pick largest contour that intersects center
    cx_center = cw // 2
    def contour_score(c):
        x, y, w_rect, h_rect = cv2.boundingRect(c)
        # area * proximity to center
        center_dist = abs((x + w_rect//2) - cx_center)
        return cv2.contourArea(c) - center_dist*10  # tune factor if needed

    best_contour = max(contours, key=contour_score)

    # Convex hull
    hull = cv2.convexHull(best_contour)
    x, y, w_rect, h_rect = cv2.boundingRect(hull)

    paper_crop = crop_img[y:y+h_rect, x:x+w_rect]

    return paper_crop

def rotate_paper(paper_crop):
    """
    Rotate the extracted paper to make it roughly upright,
    without cropping the height or width.

    Args:
        paper_crop (np.ndarray): BGR image

    Returns:
        np.ndarray: rotated image, same size as input
    """
    # Convert to grayscale and threshold for white
    gray = cv2.cvtColor(paper_crop, cv2.COLOR_BGR2GRAY)
    _, thresh = cv2.threshold(gray, 200, 255, cv2.THRESH_BINARY)

    # Find contours
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return paper_crop  # fallback

    # Use largest contour
    largest_contour = max(contours, key=cv2.contourArea)

    # Compute minimum area rectangle
    rect = cv2.minAreaRect(largest_contour)
    angle = rect[-1]

    # OpenCV angle conventions
    if angle < -45:
        angle += 90
    elif angle > 45:
        angle -= 90

    # Rotate around center
    h, w = paper_crop.shape[:2]
    M = cv2.getRotationMatrix2D((w//2, h//2), angle, 1.0)
    rotated = cv2.warpAffine(paper_crop, M, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)

    return rotated

def extract_paper(input_path, output_path):
    img = cv2.imread(input_path)
    paper_crop = extract_paper_center_color(img)
    if paper_crop is None:
        print("Paper not found")
        return False
    # rotated = rotate_paper(paper_crop)
    rotated = paper_crop
    cv2.imwrite(output_path, rotated)

    return True