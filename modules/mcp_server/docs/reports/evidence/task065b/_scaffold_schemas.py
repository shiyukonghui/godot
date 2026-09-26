import json, io
d = json.load(io.open('modules/mcp_server/docs/tools_list.renamed.json', encoding='utf-8'))
want = ['editor_open_scene','editor_save_scene','editor_set_node_property','editor_get_scene_tree',
        'editor_list_signal_connections','editor_analyze_screenshot_diff','editor_get_project_info',
        'running_game_run_test_scenario','running_game_get_node_property_samples',
        'running_game_get_node_properties','running_game_find_nodes_by_script','running_game_get_scene_tree',
        'running_game_capture_screenshot','running_game_set_node_property']
for t in d['result']['tools']:
    if t['name'] in want:
        print('==', t['name'])
        print(json.dumps(t['inputSchema'], ensure_ascii=True))
