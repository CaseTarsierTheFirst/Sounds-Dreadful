import re

def read_mif(filename):
    """Read MIF and return (bitwidth, depth, pixels as list of ints)."""
    with open(filename, 'r') as f:
        content = f.read()

    width_match = re.search(r'WIDTH=(\d+);', content)
    depth_match = re.search(r'DEPTH=(\d+);', content)
    width = int(width_match.group(1))
    depth = int(depth_match.group(1))

    # Extract pixel data lines: address:value;
    data_lines = re.findall(r'([0-9A-Fa-f]+):([0-9A-Fa-f]+);', content)
    pixels = [int(val, 16) for _, val in data_lines]

    return width, depth, pixels


def write_mif(filename, bitwidth, width, height, pixels):
    """Write a .mif file from flattened pixel list."""
    with open(filename, 'w') as f:
        f.write(f"WIDTH={bitwidth};\n")
        f.write(f"DEPTH={width * height};\n")
        f.write("ADDRESS_RADIX=HEX;\n")
        f.write("DATA_RADIX=HEX;\n")
        f.write("CONTENT BEGIN\n")
        for addr, px in enumerate(pixels):
            f.write(f"{addr:X}:{px:03X};\n")
        f.write("END;\n")
    print(f"Saved blurred image to {filename}")


def unpack_rgb444(value):
    """Convert 12-bit packed RGB444 -> (R,G,B) each 0–15."""
    r = (value >> 8) & 0xF
    g = (value >> 4) & 0xF
    b = value & 0xF
    return [r, g, b]


def pack_rgb444(rgb):
    """Convert (R,G,B) back to 12-bit packed RGB444."""
    r, g, b = rgb
    r = max(0, min(15, int(r)))
    g = max(0, min(15, int(g)))
    b = max(0, min(15, int(b)))
    return (r << 8) | (g << 4) | b


def apply_box_blur(image, width, height):
    """Apply 3×3 box blur to a 2D RGB list (no numpy)."""
    kernel_size = 5
    pad = kernel_size // 2

    # Create a new blank image
    blurred = [[[0,0,0] for _ in range(width)] for _ in range(height)]

    for y in range(height):
        for x in range(width):
            sum_r = sum_g = sum_b = count = 0
            for ky in range(-pad, pad+1):
                for kx in range(-pad, pad+1):
                    nx = x + kx
                    ny = y + ky
                    # Clamp coordinates at image boundaries
                    if 0 <= nx < width and 0 <= ny < height:
                        r, g, b = image[ny][nx]
                        sum_r += r
                        sum_g += g
                        sum_b += b
                        count += 1
            blurred[y][x][0] = sum_r / count
            blurred[y][x][1] = sum_g / count
            blurred[y][x][2] = sum_b / count

    return blurred


def blur_mif(input_file, output_file, width, height):
    bitwidth, depth, pixels = read_mif(input_file)

    # Unpack pixel data
    rgb_image = []
    for y in range(height):
        row = []
        for x in range(width):
            idx = y * width + x
            row.append(unpack_rgb444(pixels[idx]))
        rgb_image.append(row)

    # Apply blur
    blurred = apply_box_blur(rgb_image, width, height)

    # Flatten back to list
    blurred_flat = []
    for y in range(height):
        for x in range(width):
            blurred_flat.append(pack_rgb444(blurred[y][x]))

    # Write output MIF
    write_mif(output_file, bitwidth, width, height, blurred_flat)


# Example usage
if __name__ == "__main__":
    # Change resolution to your MIF image’s size
    blur_mif("pp.mif", "blurred_output.mif", width=640, height=480)
