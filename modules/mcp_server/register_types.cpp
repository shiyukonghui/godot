/**************************************************************************/
/*  register_types.cpp                                                    */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "register_types.h"

#include "mcp_server.h"
// TASK-012 section 2.1: `running_game_create_input_recording` needs an object
// that receives the game's input while the recording runs. The module supplies
// its own smallest equivalent of the migration source's GDScript autoload
// (`tools/input_recorder.{h,cpp}`) and registers it for `ClassDB::instantiate`.
// It overrides the plain `Node::input()` virtual rather than the `_input`
// GDVIRTUAL, so this registration is for construction only - the hook itself
// does not depend on it.
#include "tools/input_recorder.h"

#include "core/config/engine.h"
#include "core/core_bind.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/object/message_queue.h"

void initialize_mcp_server_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	GDREGISTER_CLASS(MCPServer);
	GDREGISTER_CLASS(MCPInputRecorderNode);

	MCPServer *server = memnew(MCPServer);
	MCPServer::singleton = server;

	if (CoreBind::Engine::get_singleton() != nullptr) {
		CoreBind::Engine::get_singleton()->register_singleton("MCPServer", server);
	}

	// The SceneTree does not exist yet at SCENE level, so defer attaching the
	// node (and therefore the per-frame pump) to the first main loop iteration.
	MessageQueue::get_singleton()->push_callable(callable_mp(server, &MCPServer::bootstrap));
}

void uninitialize_mcp_server_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	// If the node made it into the SceneTree it has already been destroyed by
	// the SceneTree teardown (which happens before SCENE uninitialization); in
	// that case the singleton pointer is null and there is nothing left to do.
	MCPServer *server = MCPServer::get_singleton();
	if (server != nullptr) {
		MCPServer::singleton = nullptr;
		if (CoreBind::Engine::get_singleton() != nullptr && CoreBind::Engine::get_singleton()->has_singleton("MCPServer")) {
			CoreBind::Engine::get_singleton()->unregister_singleton("MCPServer");
		}
		memdelete(server);
	}
}