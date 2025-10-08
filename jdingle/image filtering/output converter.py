from PIL import Image

# --- USER PARAMETERS ---
input_hex_file = 'out_image.hex'  # output from your SV simulation
output_image_file = 'grayscale_image.png'
width = 32   # set your image width
height = 32  # set your image height
# ------------------------

# Read hex pixel values into a list
pixels = []
with open(input_hex_file, 'r') as f:
    for line in f:
        line = line.strip()
        if line:  # ignore empty lines
            pixels.append(int(line, 16))

# Check that number of pixels matches width*height
if len(pixels) != width * height:
    print(f"Warning: pixel count ({len(pixels)}) != width*height ({width*height})")

# Create grayscale image ('L' mode = 8-bit)
img = Image.new('L', (width, height))
img.putdata(pixels)
img.save(output_image_file)

print(f"Grayscale image saved as '{output_image_file}'")
