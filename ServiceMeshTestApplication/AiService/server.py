from mcp.server.fastmcp import FastMCP
import random
import numpy as np
from PIL import Image
import os
import uuid

# ---------------------------------------------------------
# PURPOSE: 
#   Acts as an independent microservice that holds our procedural generation 
#   logic. It exposes these Python functions as "Tools" that the LLM can trigger 
#   over the network via Server-Sent Events (SSE).
#
# REQUIRES:
#   - mcp, numpy, Pillow (installed via requirements.txt)
# ---------------------------------------------------------

# Initialize the server and ensure the output directory exists
mcp = FastMCP("ProceduralTools")
os.makedirs("data/img", exist_ok=True)

@mcp.tool()
def generate_procedural_image(seed: int, width: int, height: int) -> str:
    """
    Generates a procedural noise image based on a deterministic seed.
    Returns: The generated filename (string) so the API knows what to fetch.
    """
    uid = uuid.uuid4().hex
    image_name = uid + ".png"

    # Use NumPy for extremely fast, matrix-level random number generation
    rng = np.random.RandomState(seed)
    pixels = rng.randint(0, 256, (height, width, 3), dtype=np.uint8)

    # Convert the matrix into a real image and save to disk
    img = Image.fromarray(pixels, 'RGB')
    img.save(f"data/img/{image_name}")

    return image_name

@mcp.tool()
def generate_random_numbers(count: int, min_val: int, max_val: int, seed: int) -> str:
    """
    Generates an array of random numbers. 
    Returns: A JSON-formatted string representation of the array (e.g., "[1, 2, 3]").
    """
    rng = random.Random(seed)
    numbers = [rng.randint(min_val, max_val) for _ in range(count)]

    return "[" + ", ".join(map(str, numbers)) + "]"

if __name__ == "__main__":
    # Crucial: Run over Server-Sent Events (SSE) so FastAPI can connect to it 
    # via HTTP on port 8000, rather than relying on standard input/output streams.
    mcp.run(transport="sse")