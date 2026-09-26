# =============================================================================
#  mcp066b_make_pngs.py -- TASK-066 role B, criterion B6 probes.
#
#  Builds the three images the editor_analyze_screenshot_diff refusal paths need,
#  all in memory and tiny:
#
#    * two images of DIFFERENT size  -> the size-mismatch refusal (-32602);
#    * one image WIDER than the tool's MAX_DIFF_DIMENSION (4096, see
#      tools/tool_helpers.h:474)     -> the dimension refusal (-32602).
#
#  Usage: python mcp066b_make_pngs.py <outdir>
#  Writes <outdir>\probe-pngs.json with, for each image, its path, size and the
#  base64 of its PNG bytes (the tool accepts a path or raw base64).
# =============================================================================
import base64
import io
import json
import os
import sys

from PIL import Image


def png_bytes(width, height, color):
    image = Image.new("RGB", (width, height), color)
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def main():
    outdir = sys.argv[1]
    if not os.path.isdir(outdir):
        os.makedirs(outdir)
    specs = [
        ("sm_64x64", 64, 64, (10, 20, 30)),
        ("sm_64x32", 64, 32, (10, 20, 30)),
        ("big_4097x1", 4097, 1, (10, 20, 30)),
    ]
    out = {"note": "B6 probes: a size mismatch pair and one image over MAX_SCREENSHOT_DIFF_DIMENSION=4096",
           "images": []}
    for name, width, height, color in specs:
        data = png_bytes(width, height, color)
        path = os.path.join(outdir, name + ".png")
        with open(path, "wb") as handle:
            handle.write(data)
        out["images"].append({
            "name": name,
            "path": path,
            "width": width,
            "height": height,
            "bytes": len(data),
            "sha256": __import__("hashlib").sha256(data).hexdigest(),
            "base64": base64.b64encode(data).decode("ascii"),
        })
    with open(os.path.join(outdir, "probe-pngs.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(out, handle, indent=2)
    print(json.dumps({"images": len(out["images"]), "outdir": outdir}))


if __name__ == "__main__":
    main()
