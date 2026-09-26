import io, os, re

MODULE = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
HEADER = os.path.join(MODULE, 'tests', 'test_mcp_server.h')

with io.open(HEADER, encoding='utf-8') as f:
    text = f.read()

before = text

# 1. `visible(false)` on the editor-process table is the game endpoint's view:
#    game-only + both = 69 after this batch (it was 57). The 46 value belongs to
#    an editor's view of the *game* table (`get_visible_tool_count(true)`), which
#    the editor table also answers as 46 - but `visible(false)` never was it.
text = text.replace('editor_registry.get_visible_tool_count(false) == 46',
                    'editor_registry.get_visible_tool_count(false) == 69')

# 2. Reset the error before the calls that follow a deliberate failure, so the
#    "no error" assertion is about the call under test and not the previous one.
text = text.replace(
    '''	const Dictionary size_result = MCPTools::theme_set_font_size(theme, save_path, "Button", "font_size", 16, error);
	CHECK_FALSE(error.is_error());''',
    '''	error = MCPToolError();
	const Dictionary size_result = MCPTools::theme_set_font_size(theme, save_path, "Button", "font_size", 16, error);
	CHECK_FALSE(error.is_error());''')
text = text.replace(
    '''	const Dictionary zero_result = MCPTools::theme_set_font_size(theme, save_path, "Button", "zero_size", 0, error);
	CHECK_FALSE(error.is_error());''',
    '''	error = MCPToolError();
	const Dictionary zero_result = MCPTools::theme_set_font_size(theme, save_path, "Button", "zero_size", 0, error);
	CHECK_FALSE(error.is_error());''')
text = text.replace(
    '''	const Dictionary box_result = MCPTools::theme_set_stylebox(theme, save_path, "Panel", "panel", box_args, error);
	CHECK_FALSE(error.is_error());''',
    '''	error = MCPToolError();
	const Dictionary box_result = MCPTools::theme_set_stylebox(theme, save_path, "Panel", "panel", box_args, error);
	CHECK_FALSE(error.is_error());''')
text = text.replace(
    '''	const Dictionary constant_result = MCPTools::theme_set_constant(theme, save_path, "Button", "separation", 4, error);
	CHECK_FALSE(error.is_error());''',
    '''	error = MCPToolError();
	const Dictionary constant_result = MCPTools::theme_set_constant(theme, save_path, "Button", "separation", 4, error);
	CHECK_FALSE(error.is_error());''')

# 3. A plain Node2D does not declare `speed`, so the helper's documented fallback
#    is what this process can prove; the scripted-player branch is wire-proven.
text = text.replace(
    '''	CHECK(MCPTools::move_speed_of(player, 7.0, true, speed_source) == 14.0);
	player->set("speed", 3.0);
	CHECK(MCPTools::move_speed_of(player, 0.0, false, speed_source) == 3.0);
	CHECK(speed_source == "player_speed");
	Node2D *bare = memnew(Node2D);''',
    '''	CHECK(MCPTools::move_speed_of(player, 7.0, true, speed_source) == 14.0);
	// `speed` is not an engine member of a `Node2D`, so an object that does not
	// declare it falls back to the documented default. The scripted-player
	// branch (`Object::get`/`get_property_list` through a `ScriptInstance`, which
	// is how a game's own `var speed` becomes readable) is exercised on the wire
	// in REPORT-036 section 6.
	player->set("speed", 3.0);
	CHECK(MCPTools::move_speed_of(player, 0.0, false, speed_source) == 200.0);
	CHECK(speed_source == "default_200");
	Node2D *bare = memnew(Node2D);''')

with io.open(HEADER, 'w', encoding='utf-8', newline='\n') as f:
    f.write(text)

print('changed' if text != before else 'NO CHANGE')
