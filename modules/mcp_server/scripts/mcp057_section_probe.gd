# =============================================================================
#  mcp057_section_probe.gd -- TASK-057 (engine patch 2) live probe.
#
#  Runs inside a real Godot process (`--headless --path <project> --script
#  res://mcp057_section_probe.gd -- <args>`) so the section publish can be
#  exercised through the same engine a tool would call, on a real
#  `project.godot`, with the bytes checked from outside the process.
#
#  It is a `MainLoop`, not a `Node`: `--script` needs a main loop, and this run
#  must not need a scene tree (a section publish is a file operation).
#
#  Modes:
#    publish <path> <section> <key> <godot-literal> [<key> <godot-literal> ...]
#        Calls ProjectSettings.save_custom_section() and then reads the section
#        back with the engine's own ConfigFile reader.
#    has_action <action>
#        Prints whether the *engine's InputMap* knows the action. This is the
#        check the in-module text splice failed: a key appended after a
#        non-last `[input]` header parses fine but lands in the following
#        section, and only a reader that resolves `input/<action>` can see it.
#    save_custom <path>
#        Calls the whole-file writer on the same file, to show that the
#        declared behaviour of the existing entry point did not change.
# =============================================================================

extends MainLoop

var _args: PackedStringArray = []


func _initialize() -> void:
	_args = OS.get_cmdline_user_args()
	if _args.size() == 0:
		print("MCP057_PROBE error=no_mode")
		return
	match _args[0]:
		"publish":
			_publish()
		"input_action":
			_publish_input_action()
		"has_action":
			_has_action()
		"save_custom":
			_save_custom()
		_:
			print("MCP057_PROBE error=unknown_mode mode=", _args[0])


# `MainLoop::process()` reads the script's return value as "quit now"
# (core/os/main_loop.cpp:67-71), so `true` ends the run after one iteration.
# Without this the engine keeps running the main loop forever: measured, a
# `--script` run that only defines `_initialize` never exits, and a headless
# invocation of it has to be killed.
func _process(_delta: float) -> bool:
	return true


func _publish_input_action() -> void:
	# The input-action shape is built *here*, not passed on the command line.
	# A Dictionary literal on the command line is not safe: the argument contains
	# spaces and quotes, and the Windows argument parser eats the inner quotes
	# (measured: `str_to_var('{"deadzone": 0.5, "events": []}')` received
	# `{deadzone: 0.5, events: []}` and produced `null`, which the writer then
	# published as `fire=null` -- a real silent wrong-value trap this probe
	# avoids by construction).
	var path := _args[1]
	var action := _args[2]
	var settings := {}
	settings["input/" + action] = {"deadzone": 0.5, "events": []}
	_report_publish(path, "input", settings, "input_action")


func _publish() -> void:
	var path := _args[1]
	var section := _args[2]
	var settings := {}
	var i := 3
	while i + 1 < _args.size():
		settings[_args[i]] = str_to_var(_args[i + 1])
		i += 2
	_report_publish(path, section, settings, "publish")


func _report_publish(path: String, section: String, settings: Dictionary, mode: String) -> void:
	var err := ProjectSettings.save_custom_section(path, section, settings)
	print("MCP057_PROBE mode=", mode, " err=", err)
	var reader := ConfigFile.new()
	var load_err := reader.load(path)
	print("MCP057_PROBE load=", load_err)
	if reader.has_section(section):
		print("MCP057_PROBE keys=", reader.get_section_keys(section))
	else:
		print("MCP057_PROBE keys=NO_SECTION")
	for key in settings.keys():
		var name: String = key
		var short: String = name.substr(name.find("/") + 1)
		print("MCP057_PROBE key=", short, " present=", reader.has_section_key(section, short))


func _has_action() -> void:
	var action := _args[1]
	print("MCP057_PROBE mode=has_action action=", action, " has_action=", InputMap.has_action(action))
	if InputMap.has_action(action):
		print("MCP057_PROBE events=", InputMap.action_get_events(action).size())
		print("MCP057_PROBE deadzone=", InputMap.action_get_deadzone(action))


func _save_custom() -> void:
	var path := _args[1]
	var err := ProjectSettings.save_custom(path)
	print("MCP057_PROBE mode=save_custom err=", err)