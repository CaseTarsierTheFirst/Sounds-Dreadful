import numpy as np
from PIL import Image
import re

def mif_to_image(mif_filename, resolution=(640, 480), RGB_format=[4,4,4], output_filename=None):
    """
    Convert a .mif file (Intel Memory Init File) back into an image (e.g. .jpg)

    Args:
        mif_filename : str
            Path to .mif file
        resolution : tuple (width, height)
            Resolution of the original image
        RGB_format : list [R_bits, G_bits, B_bits]
            Bit-depth of each color channel used in encoding
        output_filename : str or None
            Name of output file (if None, auto-generates .jpg)
    """

    width, height = resolution
    R_bits, G_bits, B_bits = RGB_format
    num_pixels = width * height

    # === Step 1: Read MIF content ===
    with open(mif_filename, "r") as f:
        lines = f.readlines()

    # Extract only address:value lines
    content = []
    capture = False
    for line in lines:
        if "CONTENT BEGIN" in line:
            capture = True
            continue
        elif "END" in line:
            break
        if capture:
            match = re.match(r"([0-9A-Fa-f]+):([0-9A-Fa-f]+);", line.strip())
            if match:
                address, hex_val = match.groups()
                content.append(int(hex_val, 16))

    if len(content) != num_pixels:
        raise ValueError(f"Pixel count mismatch. Expected {num_pixels}, found {len(content)}.")

    # === Step 2: Unpack RGB channels ===
    image = np.zeros((height, width, 3), dtype=np.uint8)

    R_mask = (1 << R_bits) - 1
    G_mask = (1 << G_bits) - 1
    B_mask = (1 << B_bits) - 1

    for i, pixel in enumerate(content):
        R = (pixel >> (G_bits + B_bits)) & R_mask
        G = (pixel >> B_bits) & G_mask
        B = pixel & B_mask

        # Normalize to 8-bit
        R = int((R / R_mask) * 255)
        G = int((G / G_mask) * 255)
        B = int((B / B_mask) * 255)

        y = i // width
        x = i % width
        image[y, x] = [R, G, B]

    # === Step 3: Save as image ===
    img = Image.fromarray(image, mode="RGB")
    if output_filename is None:
        output_filename = mif_filename.replace(".mif", "_reconstructed.jpg")
    img.save(output_filename, quality=95)

    print(f"Successfully reconstructed image saved to {output_filename}")
    return img

mif_to_image(
    "blurred_output.mif",
    resolution=(640, 480),
    RGB_format=[4,4,4]
)