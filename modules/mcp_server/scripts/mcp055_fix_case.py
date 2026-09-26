import io

# The ScriptPath source generator (and the engine's own `can_instantiate()` error
# message) require the file name to match the class name *exactly*, case
# included: `legit.cs` with `class Legit` produced no `[ScriptPath]` attribute,
# which is why the pre-run fixture never resolved as a compiled script.
replacements = [
    ("scripts\\legit.cs", "scripts\\Legit.cs"),
    ("scripts\\broken.cs", "scripts\\Broken.cs"),
    ("'legit.cs'", "'Legit.cs'"),
    ("'broken.cs'", "'Broken.cs'"),
    ("res://scripts/legit.cs", "res://scripts/Legit.cs"),
    ("res://scripts/broken.cs", "res://scripts/Broken.cs"),
    ("contains('broken.cs')", "contains('Broken.cs')"),
]

for path in [
    r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\scripts\mcp055_csharp_compile_verdict_evidence.ps1",
    r"F:\RustProjects\godot-mcp-pro\code\godot\modules\mcp_server\scripts\mcp055_pre_post_compare.py",
]:
    text = io.open(path, encoding="utf-8").read()
    for old, new in replacements:
        text = text.replace(old, new)
    io.open(path, "w", encoding="utf-8", newline="").write(text)
    print(path, "->", text.count("Legit.cs"), "Legit.cs /", text.count("Broken.cs"), "Broken.cs")
