@echo off
setlocal
cd /d F:\RustProjects\godot-mcp-pro\code\godot
set ENG=bin\godot.windows.editor.x86_64.console.exe
set SCRIPTS=modules\mcp_server\scripts

echo === gate3 module doctests ===
%ENG% --headless --test --test-case="[MCPServer]*" > "%TEMP%\g3_final.log" 2>&1
echo gate3_exit=%errorlevel%

echo === gate4 full regression ===
%ENG% --headless --test > "%TEMP%\g4_final.log" 2>&1
echo gate4_exit=%errorlevel%

echo === accept_m1 run 1 ===
powershell -NoProfile -ExecutionPolicy Bypass -File %SCRIPTS%\accept_m1.ps1 > "%TEMP%\acc1_final.log" 2>&1
echo accept1_exit=%errorlevel%

echo === accept_m1 run 2 ===
powershell -NoProfile -ExecutionPolicy Bypass -File %SCRIPTS%\accept_m1.ps1 > "%TEMP%\acc2_final.log" 2>&1
echo accept2_exit=%errorlevel%

for %%S in (mcp030_live_open_scene_write_evidence mcp032_d3_d4_d6_evidence mcp033_b5_animation_evidence mcp034_b5_audio_particle_theme_evidence mcp035_b5_tilemap_shader_physics_evidence) do (
    echo === regression %%S ===
    powershell -NoProfile -ExecutionPolicy Bypass -File %SCRIPTS%\%%S.ps1 > "%TEMP%\reg_%%S.log" 2>&1
    echo reg_%%S_exit=!errorlevel!
)

for %%G in (editor_navigation_write editor_navigation_read running_game_navigation_write project_theme_write project_theme_read project_export_read project_android_read os_android_read os_android_write) do (
    echo === gate1 %%G ===
    powershell -NoProfile -ExecutionPolicy Bypass -File %SCRIPTS%\check_contract_subset.ps1 -Group %%G > "%TEMP%\gate1f_%%G.log" 2>&1
)

echo === ALL DONE ===
