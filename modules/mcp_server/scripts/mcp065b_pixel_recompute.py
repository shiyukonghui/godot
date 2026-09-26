# =============================================================================
#  mcp065b_pixel_recompute.py -- TASK-065 section B, criterion 6 route 3.
#
#  The third, INDEPENDENT recomputation of the capture line's numbers: the two
#  PNGs the windowed editor wrote for one tools/call are decoded here and the
#  comparison is re-done from scratch, with no engine code in the loop.
#
#  The rule is the module's own (tools/tool_helpers.cpp compare_screenshot_pixels,
#  the raw-byte path): for every pixel, dr/dg/db are the absolute per-channel byte
#  differences, max_diff = max(dr, dg, db), and a pixel counts as changed when
#  max_diff > threshold. Alpha is never read. The default threshold is 10.
#
#  Usage: python mcp065b_pixel_recompute.py <pairs.json> <out.json>
#  pairs.json: [{"label":..., "before":..., "after":..., "threshold":10,
#                "log_changed_pixels":N, "log_total_pixels":N,
#                "tool_changed_pixels":N, "tool_total_pixels":N}, ...]
# =============================================================================
import json
import sys
from PIL import Image


def recompute(before_path, after_path, threshold):
    a = Image.open(before_path)
    b = Image.open(after_path)
    a = a.convert("RGBA") if a.mode not in ("RGB", "RGBA") else a
    b = b.convert("RGBA") if b.mode not in ("RGB", "RGBA") else b
    if a.size != b.size:
        return {"error": "size mismatch", "a": a.size, "b": b.size}
    pa = list(a.getdata())
    pb = list(b.getdata())
    changed = 0
    for ca, cb in zip(pa, pb):
        dr = abs(ca[0] - cb[0])
        dg = abs(ca[1] - cb[1])
        db = abs(ca[2] - cb[2])
        if max(dr, dg, db) > threshold:
            changed += 1
    total = a.size[0] * a.size[1]
    return {
        "width": a.size[0],
        "height": a.size[1],
        "total_pixels": total,
        "changed_pixels": changed,
        "identical": changed == 0,
        "changed_pixel_ratio": (float(changed) / float(total)) if total else 0.0,
        "diff_percentage": round(float(changed) / float(total) * 100.0, 2),
    }


def main():
    pairs = json.load(open(sys.argv[1], "r", encoding="utf-8"))
    out = []
    for entry in pairs:
        threshold = int(entry.get("threshold", 10))
        r = recompute(entry["before"], entry["after"], threshold)
        item = {"label": entry["label"], "threshold": threshold,
                "before": entry["before"], "after": entry["after"],
                "before_sha256": entry.get("before_sha256"),
                "after_sha256": entry.get("after_sha256"),
                "independent": r}
        if "error" not in r:
            log_cp = entry.get("log_changed_pixels")
            log_tp = entry.get("log_total_pixels")
            tool_cp = entry.get("tool_changed_pixels")
            tool_tp = entry.get("tool_total_pixels")
            item["log_matches_independent"] = (log_cp == r["changed_pixels"] and log_tp == r["total_pixels"])
            item["tool_matches_independent"] = (
                None if tool_cp is None else (tool_cp == r["changed_pixels"] and tool_tp == r["total_pixels"]))
            item["log_changed_pixels"] = log_cp
            item["log_total_pixels"] = log_tp
            item["tool_changed_pixels"] = tool_cp
            item["tool_total_pixels"] = tool_tp
        out.append(item)
    payload = {"script": "mcp065b_pixel_recompute.py",
               "rule": "max(|dr|,|dg|,|db|) > threshold, alpha ignored (tools/tool_helpers.cpp raw-byte path)",
               "pairs": out,
               "all_three_routes_agree": all(
                   p.get("log_matches_independent") and (p.get("tool_matches_independent") in (True, None))
                   for p in out if "error" not in p.get("independent", {}))}
    json.dump(payload, open(sys.argv[2], "w", encoding="utf-8"), indent=2)
    print(json.dumps({"pairs": len(out), "all_three_routes_agree": payload["all_three_routes_agree"]}))
    for p in out:
        print(json.dumps(p))


if __name__ == "__main__":
    main()