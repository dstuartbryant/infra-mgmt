import colorsys
import random


def generate_pastel_hex():
    """
    Generates a random, developer-friendly pastel hex color code.

    This is achieved by generating a color in HSL format with a random hue,
    and then keeping the saturation and lightness within a specific range
    that defines "pastel" colors (high lightness, mid-range saturation).
    """
    hue = random.random()  # Random hue from 0.0 to 1.0
    saturation = random.uniform(0.65, 0.85)  # Saturation in a pleasant range
    lightness = random.uniform(0.80, 0.90)  # Lightness for a pastel feel

    # Convert HSL to RGB
    rgb_float = colorsys.hls_to_rgb(hue, lightness, saturation)

    # Convert float (0-1) RGB values to integer (0-255)
    rgb_int = [int(c * 255) for c in rgb_float]

    # Format as a hex string
    return f"#{rgb_int[0]:02x}{rgb_int[1]:02x}{rgb_int[2]:02x}"
