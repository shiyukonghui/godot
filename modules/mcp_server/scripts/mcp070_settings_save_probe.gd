# =============================================================================
#  mcp070_settings_save_probe.gd -- TASK-070 item 2, the reverse control.
#
#  Runs inside a real Godot process (`--headless --path <project> --script
#  res://mcp070_probe.gd -- <mode>`) so the EXISTING public entry points can be
#  called on the same fixture the windowed editor is opened on.
#
#  Modes:
#    save_whole
#        Calls `ProjectSettings.save()` -- the whole-file writer that patch 3
#        replaced at ONE call site. It must still behave exactly as before
#        (seven header comment lines of its own, every hand written comment
#        gone), which is what makes "the patch moved a call site, not the
#        writer" a measurement rather than a claim.
#    save_custom_section <section> <key> <godot-literal> ...
#        Calls the section publisher directly (the engine API patch 2 added),
#        for completeness.
# =============================================================================

extends MainLoop

var _args: PackedStringArray = []


func _initialize() -> void:
	_args = OS.get_cmdline_user_args()
	if _args.size() == 0:
		print("MCP070_PROBE error=no_mode")
		return
	match _args[0]:
		"save_whole":
			_save_whole()
		"save_custom_section":
			_save_custom_section()
		_:
			print("MCP070_PROBE error=unknown_mode mode=", _args[0])


# `MainLoop::process()` reads the script's return value as "quit now"
# (core/os/main_loop.cpp:67-71), so `true` ends the run after one iteration.
func _process(_delta: float) -> bool:
	return true


func _save_whole() -> void:
	var err := ProjectSettings.save()
	print("MCP070_PROBE mode=save_whole err=", err)


func _save_custom_section() -> void:
	var section := _args[1]
	var settings := {}
	var i := 2
	while i + 1 < _args.size():
		settings[_args[i]] = str_to_var(_args[i + 1])
		i += 2
	var err := ProjectSettings.save_custom_section("", section, settings)
	print("MCP070_PROBE mode=save_custom_section err=", err)
