from rembg import remove
from PIL import Image

print("Loading background removal model...")
# The model will be downloaded on first use
print("Background removal model ready")

def remove_background(input_path: str, output_path: str):
    """
    Remove the background from an image.
    
    Args:
        input_path: Path to the input image
        output_path: Path to save the output image with removed background
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        # Read the input image
        with open(input_path, 'rb') as input_file:
            input_data = input_file.read()
        
        # Remove background
        output_data = remove(input_data)
        
        # Save the output image
        with open(output_path, 'wb') as output_file:
            output_file.write(output_data)
        
        return True
    except Exception as e:
        print(f"Error removing background: {e}")
        return False
