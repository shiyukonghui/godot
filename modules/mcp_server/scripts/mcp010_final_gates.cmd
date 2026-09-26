@echo off
REM TASK-010: re-run every gate serially on the final binary, one log per gate.
REM Serialised on purpose: every gate that binds 9888/9889 must not overlap with
REM another one, and the doctest suite is CPU bound.
setlocal
set GDIR=F:\RustProjects\godot-mcp-pro\code\godot
set MDIR=%GDIR%\modules\mcp_server
set LOGS=%TEMP%\mcp010-final
if not exist "%LOGS%" mkdir "%LOGS%"

cd /d %GDIR%
echo ===== mcp doctest ===== >> "%LOGS%\runner.log"
bin\godot.windows.editor.x86_64.console.exe --headless --test --test-case="[MCPServer]*" > "%LOGS%\mcp-doctest.log" 2>&1
echo MCP_DOCTEST_EXIT=%ERRORLEVEL% >> "%LOGS%\runner.log"

echo ===== full engine test ===== >> "%LOGS%\runner.log"
bin\godot.windows.editor.x86_64.console.exe --headless --test > "%LOGS%\full-test.log" 2>&1
echo FULL_TEST_EXIT=%ERRORLEVEL% >> "%LOGS%\runner.log"

cd /d %MDIR%
echo ===== gate1 observation ===== >> "%LOGS%\runner.log"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check_contract_subset.ps1 -Group running_game_observation > "%LOGS%\gate1-observation.log" 2>&1
echo GATE1_OBSERVATION_EXIT=%ERRORLEVEL% >> "%LOGS%\runner.log"

echo ===== gate1 script ===== >> "%LOGS%\runner.log"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check_contract_subset.ps1 -Group running_game_script_execution > "%LOGS%\gate1-script.log" 2>&1
echo GATE1_SCRIPT_EXIT=%ERRORLEVEL% >> "%LOGS%\runner.log"

echo ===== evidence count ===== >> "%LOGS%\runner.log"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp010_b2_observation_evidence.ps1 -Phase count > "%LOGS%\evidence-count.log" 2>&1
echo EVIDENCE_COUNT_EXIT=%ERRORLEVEL% >> "%LOGS%\runner.log"

echo ===== evidence game ===== >> "%LOGS%\runner.log"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp010_b2_observation_evidence.ps1 -Phase game > "%LOGS%\evidence-game.log" 2>&1
echo EVIDENCE_GAME_EXIT=%ERRORLEVEL% >> "%LOGS%\runner.log"

echo ===== evidence scope ===== >> "%LOGS%\runner.log"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\mcp010_b2_observation_evidence.ps1 -Phase scope > "%LOGS%\evidence-scope.log" 2>&1
echo EVIDENCE_SCOPE_EXIT=%ERRORLEVEL% >> "%LOGS%\runner.log"

echo ===== accept_m1 run A ===== >> "%LOGS%\runner.log"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\accept_m1.ps1 > "%LOGS%\accept-runA.log" 2>&1
echo ACCEPT_A_EXIT=%ERRORLEVEL% >> "%LOGS%\runner.log"

echo ===== accept_m1 run B ===== >> "%LOGS%\runner.log"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\accept_m1.ps1 > "%LOGS%\accept-runB.log" 2>&1
echo ACCEPT_B_EXIT=%ERRORLEVEL% >> "%LOGS%\runner.log"

echo ===== ALL GATES DONE ===== >> "%LOGS%\runner.log"
exit /b 0