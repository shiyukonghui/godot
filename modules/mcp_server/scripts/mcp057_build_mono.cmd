@echo off
REM ===========================================================================
REM  modules/mcp_server/scripts/mcp057_build_mono.cmd
REM
REM  The tracked, verified MONO build command for the MCP server module
REM  (TASK-057 section 1 / defect D-B1).
REM
REM  Why this file exists: `build_local.cmd` builds the plain engine and always
REM  passes `module_mono_enabled=no`. The mono engine that two of the batch
REM  evidence scripts need (`mcp052_added_tools_evidence.ps1` and
REM  `mcp053_added_tools_evidence.ps1`, both of which call `project_build_csharp`)
REM  was therefore hand-built, and the 15-step regression battery that TASK-056
REM  ran against a mono binary built on a DIRTY working tree could not be
REM  reproduced: `engines_match_head` failed in both scripts because the binary
REM  reported `4e3de1090` while HEAD was `427fc79da`. The command was never
REM  written down, so nobody could re-run it.
REM
REM  This is that command, with the same rules `build_local.cmd` follows:
REM
REM    * `tests=yes` is mandatory - gates 3 and 4 run `--test`, and a binary
REM      without it aborts with "compiled without support for unit tests";
REM    * the stale test objects are deleted (`-Force` semantics) because scons
REM      keeps no dependency edge from `tests/test_mcp_server.h` to them;
REM    * `bin\obj\modules\mcp_server\mcp_trace.windows.editor.x86_64.obj` is
REM      deleted as well: `core/version_generated.gen.h` carries
REM      `GODOT_VERSION_MODULE_CONFIG` (".mono" here, "" for the plain build) and
REM      scons does not rebuild that object when the generated header changes, so
REM      after a variant switch the trace marker would name the other variant
REM      (measured in TASK-054, REPORT-054 section 5.1);
REM    * output goes to a log file (never through a pipe, so the real SCons exit
REM      code survives) in %TEMP%, and is also echoed, so nothing is suppressed.
REM
REM  Build SERIALLY. Two concurrent scons runs rewrite
REM  `modules/modules_tests.gen.h` and produce compile errors that have nothing
REM  to do with the tree (D62), and killing a background job does not guarantee
REM  its scons child dies.
REM
REM  After this build `bin\godot.windows.editor.x86_64.mono.console.exe` must
REM  report a `--version` ending in `git rev-parse --short=9 HEAD`; write the
REM  plain engine again with `build_local.cmd -Force` afterwards if the plain
REM  binary has to be the one the next gate runs on.
REM ===========================================================================
setlocal

set "REPO=%~dp0..\..\.."
if not exist "%REPO%\SConstruct" (
    echo FATAL: "%REPO%" does not look like the Godot repository root ^(no SConstruct^).
    exit /b 2
)

REM ===========================================================================
REM  D-5 (TASK-059): find the scons interpreter instead of hardcoding it.
REM
REM  This file used to call `D:\Anaconda\Scripts\scons.exe` by absolute path in
REM  two places. That works on exactly one machine and is invisible everywhere
REM  else until the build fails with a native "not recognized as an internal or
REM  external command" that says nothing about what is missing. The probe below
REM  tries three sources in order and, when none resolves, prints what to do.
REM
REM    1. %SCONS%                        - explicit override, a path or a name
REM    2. `scons` on PATH
REM    3. D:\Anaconda\Scripts\scons.exe  - the machine this file was written on
REM
REM  SCONS_NO_KNOWN_PATH=1 disables candidate 3. It exists so the readable error
REM  can be demonstrated deterministically on a machine where candidate 3 does
REM  exist (scripts\mcp059_d5_scons_probe_demo.ps1 uses it); it is a test hook,
REM  not a configuration knob.
REM
REM  --probe-only prints the resolution and exits without building.
REM ===========================================================================
set "PROBE_ONLY=0"
if /i "%~1"=="--probe-only" set "PROBE_ONLY=1"
if /i "%~1"=="-probe-only" set "PROBE_ONLY=1"

set "SCONS_BIN="
set "SCONS_FROM="

if defined SCONS if exist "%SCONS%" (
    set "SCONS_BIN=%SCONS%"
    set "SCONS_FROM=%SCONS% environment variable"
)
if not defined SCONS_BIN if defined SCONS for /f "delims=" %%I in ('where %SCONS% 2^>nul') do if not defined SCONS_BIN (
    set "SCONS_BIN=%%I"
    set "SCONS_FROM=%%I resolved from the SCONS environment variable"
)
if not defined SCONS_BIN for /f "delims=" %%I in ('where scons 2^>nul') do if not defined SCONS_BIN (
    set "SCONS_BIN=%%I"
    set "SCONS_FROM=first `scons` on PATH"
)
if not defined SCONS_BIN if not defined SCONS_NO_KNOWN_PATH if exist "D:\Anaconda\Scripts\scons.exe" (
    set "SCONS_BIN=D:\Anaconda\Scripts\scons.exe"
    set "SCONS_FROM=the known absolute path D:\Anaconda\Scripts\scons.exe"
)

if not defined SCONS_BIN (
    echo FATAL: no scons interpreter found; this build cannot run.
    echo.
    echo   Looked at, in this order:
    echo     1. the SCONS environment variable  ^(currently: "%SCONS%"^)
    echo     2. `scons` on PATH                 ^(where scons found nothing^)
    echo     3. D:\Anaconda\Scripts\scons.exe   ^(does not exist or disabled^)
    echo.
    echo   Fix it with either:
    echo     set SCONS=C:\Python312\Scripts\scons.exe   ^(then run this file again^)
    echo     or install scons and put it on PATH:  python -m pip install scons
    echo.
    echo   The probe can be inspected without building:
    echo     modules\mcp_server\scripts\mcp057_build_mono.cmd --probe-only
    exit /b 3
)

REM A pip `scons.exe` is a launcher for `python -m SCons`; it can fail to find
REM Python when its own directory is not on PATH, so that directory is added.
for %%I in ("%SCONS_BIN%") do set "SCONS_DIR=%%~dpI"
set "PATH=%SCONS_DIR%;%PATH%"

echo scons: %SCONS_BIN%  ^(from %SCONS_FROM%^)
if "%PROBE_ONLY%"=="1" (
    echo probe-only: resolved, not building.
    exit /b 0
)

if not defined MCP_BUILD_LOG set "MCP_BUILD_LOG=%TEMP%\mcp057\mono_build.log"
if not exist "%TEMP%\mcp057" mkdir "%TEMP%\mcp057" >nul 2>&1

cd /d "%REPO%"
echo ===== mcp057_build_mono START %DATE% %TIME% ===== >> "%MCP_BUILD_LOG%"
echo SCONS: %SCONS_BIN% ^(from %SCONS_FROM%^) >> "%MCP_BUILD_LOG%"

for %%F in (
    "bin\obj\modules\mcp_server\tests\test_mcp_server.windows.editor.x86_64.obj"
    "bin\obj\tests\test_main.windows.editor.x86_64.obj"
    "bin\obj\modules\mcp_server\mcp_trace.windows.editor.x86_64.obj"
    "bin\obj\modules\mcp_server\mcp_trace.windows.editor.x86_64.mono.obj"
) do (
    if exist "%%~F" (
        del /q "%%~F"
        echo   deleted %%~F >> "%MCP_BUILD_LOG%"
    ) else (
        echo   absent %%~F >> "%MCP_BUILD_LOG%"
    )
)

echo COMMAND: %SCONS_BIN% platform=windows target=editor module_mono_enabled=yes tests=yes -j8 >> "%MCP_BUILD_LOG%"
REM Never through a pipe: a pipe hands the exit code to the wrong process. The
REM whole scons output goes to the log, and the caller prints its tail, so
REM nothing is suppressed.
"%SCONS_BIN%" platform=windows target=editor module_mono_enabled=yes tests=yes -j8 >> "%MCP_BUILD_LOG%" 2>&1
set "RC=%ERRORLEVEL%"
echo EXIT_CODE=%RC% >> "%MCP_BUILD_LOG%"
echo ===== mcp057_build_mono END %DATE% %TIME% ===== >> "%MCP_BUILD_LOG%"

echo mcp057_build_mono: exit code = %RC%
echo mcp057_build_mono: log = %MCP_BUILD_LOG%
exit /b %RC%