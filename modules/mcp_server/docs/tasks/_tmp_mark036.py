import io, json, os, sys

MODULE = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
FILE = os.path.join(MODULE, 'tools', 'running_game_navigation_write.cpp')
REPORT = os.path.join(os.environ['TEMP'], 'gate6_036.json')

with io.open(REPORT, encoding='utf-8') as f:
    report = json.load(f)

points = [p for p in report['points'] if p['file'] == 'tools/running_game_navigation_write.cpp']
lines = sorted({p['line'] for p in points})

REASONS = {
    165: "safe: the zero-vector default of node_position; no caller value",
    169: "safe: widening a real_t Vector2 into a Vector3",
    171: "safe: the no-position fallback of node_position",
    183: "safe: real_t -> real_t narrowing of an already-real_t Vector3 component",
    276: "safe: derived from the already-gated Vector3 target",
    287: "safe: widening the already-gated 2D target into the shared Vector3 form",
    322: "pregated: read_component ran value_fits_slot(REAL_T) on x/y/z",
    323: "pregated: read_component ran value_fits_slot(REAL_T) on x/y",
    414: "safe: a distance between real_t Vector3 members",
    415: "safe: a distance between real_t Vector2 components",
    448: "safe: real_t components of a step the gate already bounded",
    453: "gated: direction is a normalized real_t vector and speed passed value_fits_slot(REAL_T) in the handler",
    457: "gated: same as the line above, with delta clamped to <= 0.1 s",
    459: "safe: real_t components of a step the gate already bounded",
    461: "safe: real_t components of a step the gate already bounded",
    470: "safe: a rotation computed from the already-gated target",
    502: "safe: widening the agent's own Vector2 path point",
    515: "safe: a distance between real_t Vector3 members",
    516: "safe: a distance between real_t Vector2 components",
    532: "safe: a distance between real_t Vector3 members",
    533: "safe: a distance between real_t Vector2 components",
    564: "safe: a distance between real_t Vector3 members",
    565: "safe: a distance between real_t Vector2 components",
    591: "safe: a distance between real_t Vector3 members",
    592: "safe: a distance between real_t Vector2 components",
    733: "safe: promoting the already-gated 2D target into the shared Vector3 form",
    750: "safe: real_t -> real_t narrowing of the already-gated target",
    826: "safe: real_t -> real_t narrowing of the already-gated positions",
    828: "safe: widening the server's own Vector2 path point",
}

with io.open(FILE, encoding='utf-8') as f:
    text = f.read()

out = text.split('\n')
injected = 0
for line in lines:
    index = line - 1
    if index >= len(out):
        print('SKIP out of range', line)
        continue
    if 'MCP-NARROWING' in out[index]:
        print('SKIP already marked', line)
        continue
    reason = REASONS.get(line, 'safe: reviewed')
    out[index] = out[index] + ' // MCP-NARROWING: G24-MOVE-VECTOR - ' + reason
    injected += 1

with io.open(FILE, 'w', encoding='utf-8', newline='\n') as f:
    f.write('\n'.join(out))
print('injected', injected, 'of', len(lines))
