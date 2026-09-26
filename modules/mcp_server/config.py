def can_build(env, platform):
    # v1 targets Windows only (see REQUIREMENTS.md, assumptions).
    return platform == "windows"


def configure(env):
    pass