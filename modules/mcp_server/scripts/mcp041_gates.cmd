@echo off
REM ===========================================================================
REM  mcp041_gates.cmd -- TASK-041 gate battery, strictly serial.
REM
REM  Every gate writes its own log under %LOGS%; the summary lists each step's
REM  exit code. Two engines are never started at the same time (PLAYBOOK section
REM  3, R-1 / D62), and no scons is started here at all: the gates run against
REM  the binary that `scripts\build_local.cmd -Force` built at the anchor commit
REM  `49a99fdf1` (verified with --version).
REM ===========================================================================
setlocal

set "REPO=F:\RustProjects\godot-mcp-pro\code\godot"
set "LOGS=%TEMP%\mcp041\gates"
set "SUMMARY=%LOGS%\summary.txt"
set "PY=python"
if not exist "%LOGS%" mkdir "%LOGS%"
cd /d "%REPO%"

echo TASK-041 gate battery >> "%SUMMARY%"
echo binary: >> "%SUMMARY%"
bin\godot.windows.editor.x86_64.console.exe --version >> "%SUMMARY%" 2>&1
git rev-parse --short=9 HEAD >> "%SUMMARY%"

call :step gate3_module_doctest bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*"
call :step gate4_full_doctest bin\godot.windows.editor.x86_64.console.exe --headless --test
call :step gate1_contract_subset powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\check_contract_subset.ps1 -Group editor_input_simulation
call :step gate6a_narrowing python modules\mcp_server\scripts\check_narrowing_points.py
call :step gate6b_narrowing_coverage python modules\mcp_server\scripts\check_narrowing_points.py --coverage
call :step gate6c_coverage_probes powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp031_gate6_coverage_probes.ps1
call :step gate5_accept_run1 powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1
call :step gate5_accept_run2 powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\accept_m1.ps1
call :step gate2_wire_evidence powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp041_inputmap_persistence_evidence.ps1
call :step regress_mcp032 powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp032_d3_d4_d6_evidence.ps1
call :step regress_mcp033 powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp033_b5_animation_evidence.ps1
call :step regress_mcp034 powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp034_b5_audio_particle_theme_evidence.ps1
call :step regress_mcp035 powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp035_b5_tilemap_shader_physics_evidence.ps1
call :step regress_mcp036 powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp036_b5_navigation_theme_export_android_evidence.ps1
call :step regress_probe037 powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\probe037_d2_d1_r1r2.ps1
call :step regress_mcp040_probes powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp040_defect_probes.ps1 -Label task041
call :step regress_mcp040_racing powershell -NoProfile -ExecutionPolicy Bypass -File modules\mcp_server\scripts\mcp040_racing_regression.ps1

echo DONE >> "%SUMMARY%"
echo == summary ==
type "%SUMMARY%"
exit /b 0

:step
set "NAME=%~1"
shift
echo.
echo ===== STEP %NAME% =====
echo STEP %NAME% START %TIME% >> "%SUMMARY%"
%* > "%LOGS%\%NAME%.log" 2>&1
set "RC=%ERRORLEVEL%"
echo STEP %NAME% EXIT %RC% >> "%SUMMARY%"
echo STEP %NAME% EXIT %RC%
exit /b 0
