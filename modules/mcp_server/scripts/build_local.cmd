@echo off
REM ===========================================================================
REM  modules/mcp_server/scripts/build_local.cmd  [ -Force ]
REM
REM  The tracked, verified local build command for the MCP server module.
REM  TASK-008 recorded that the untracked repository-root wrapper `build-m0.cmd`
REM  does NOT pass `tests=yes`, which is how a later batch ends up running
REM  gates 3 and 4 against a binary that has no doctest support at all.
REM
REM  Why `tests=yes` is mandatory for gates 3 and 4:
REM    * `env["tests"]` defaults to False (SConstruct:254), so a binary built
REM      without it aborts with
REM        `--test was specified on the command line, but this Godot binary was
REM         compiled without support for unit tests`
REM      and the module doctests never run. There is no way to notice the
REM      difference from the outside except by reading that line.
REM
REM  ---------------------------------------------------------------------------
REM  -Force: delete the stale test objects BEFORE the build.
REM
REM  After editing modules/mcp_server/tests/test_mcp_server.h you MUST delete
REM  the stale test objects, or the binary will silently run the OLD test cases:
REM
REM    del /q bin\obj\modules\mcp_server\tests\test_mcp_server.windows.editor.x86_64.obj
REM    del /q bin\obj\tests\test_main.windows.editor.x86_64.obj
REM
REM  SCons does not rebuild them when only that header changes, because
REM  `modules/SCsub:55` pulls `tests/test_mcp_server.h` in through
REM  `CommandNoCache` (the generated `modules/modules_tests.gen.h`), so no
REM  dependency edge back to the header exists. A green run of the old cases is
REM  exactly the failure this note prevents - and it is a **false green**: the
REM  new assertions never ran, so a fix that was never written looks proven.
REM
REM  Without `-Force` this script does NOT delete them by itself: a rebuild of
REM  `test_main.cpp` costs ~30 s and is only needed when the header really
REM  changed (TASK-022 section 5.2 turned that rule into this switch, because
REM  the M4b re-audit recorded the trap as risk R-5 and it is the one failure
REM  mode a reader cannot see from the output).
REM
REM  Use `build_local.cmd -Force` whenever `tests/*.h` changed - i.e. for every
REM  red/green run of a test-driven task, and for every gate run that follows
REM  one. A plain `build_local.cmd` is only for a rebuild after engine or
REM  module *source* changes, where scons has a real dependency edge.
REM  ---------------------------------------------------------------------------
REM
REM  The build output is redirected to a log file (never through a pipe, so the
REM  true SCons exit code survives) the same way `build-m0.cmd` does. The log
REM  lives in %TEMP% instead of the repository root on purpose: the working tree
REM  is supposed to keep only the already-known untracked files. Override the
REM  location with MCP_BUILD_LOG if you want it next to the build.
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
REM  This file hardcoded `D:\Anaconda\Scripts\scons.exe` in the same two places
REM  `mcp057_build_mono.cmd` did. The probe is the mono file's, verbatim, so the
REM  two builds cannot disagree about which interpreter they ran:
REM
REM    1. %SCONS%                        - explicit override, a path or a name
REM    2. `scons` on PATH
REM    3. D:\Anaconda\Scripts\scons.exe  - the machine this file was written on
REM
REM  SCONS_NO_KNOWN_PATH=1 disables candidate 3 (a test hook, used by
REM  scripts\mcp059_d5_scons_probe_demo.ps1 to demonstrate the error message).
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
    echo     modules\mcp_server\scripts\build_local.cmd --probe-only
    exit /b 3
)

for %%I in ("%SCONS_BIN%") do set "SCONS_DIR=%%~dpI"
set "PATH=%SCONS_DIR%;%PATH%"

echo scons: %SCONS_BIN%  ^(from %SCONS_FROM%^)
if "%PROBE_ONLY%"=="1" (
    echo probe-only: resolved, not building.
    exit /b 0
)

set "FORCE=0"
if /i "%~1"=="-Force" set "FORCE=1"
if /i "%~1"=="--force" set "FORCE=1"

if not defined MCP_BUILD_LOG set "MCP_BUILD_LOG=%TEMP%\mcp_server_build_local.log"

cd /d "%REPO%"
echo ===== build_local START %DATE% %TIME% ===== >> "%MCP_BUILD_LOG%"

if "%FORCE%"=="1" (
    echo FORCE: removing stale test objects >> "%MCP_BUILD_LOG%"
    if exist "bin\obj\modules\mcp_server\tests\test_mcp_server.windows.editor.x86_64.obj" (
        del /q "bin\obj\modules\mcp_server\tests\test_mcp_server.windows.editor.x86_64.obj"
        echo   deleted bin\obj\modules\mcp_server\tests\test_mcp_server.windows.editor.x86_64.obj >> "%MCP_BUILD_LOG%"
    ) else (
        echo   absent bin\obj\modules\mcp_server\tests\test_mcp_server.windows.editor.x86_64.obj >> "%MCP_BUILD_LOG%"
    )
    if exist "bin\obj\tests\test_main.windows.editor.x86_64.obj" (
        del /q "bin\obj\tests\test_main.windows.editor.x86_64.obj"
        echo   deleted bin\obj\tests\test_main.windows.editor.x86_64.obj >> "%MCP_BUILD_LOG%"
    ) else (
        echo   absent bin\obj\tests\test_main.windows.editor.x86_64.obj >> "%MCP_BUILD_LOG%"
    )
    REM TASK-054: mcp_trace.cpp includes core/version.h, whose
    REM GODOT_VERSION_FULL_BUILD carries GODOT_VERSION_MODULE_CONFIG (".mono" or
    REM ""), generated into core/version_generated.gen.h.  Measured: scons does
    REM NOT rebuild this object when that generated header changes, so after a
    REM variant switch (a module_mono_enabled=yes build followed by this one, or
    REM the other way round) the trace generation marker's "version" field would
    REM name the other variant while the executable's own --version names this
    REM one - and the doctest that pins the two together (TASK-054 O-12) fails
    REM on a stale artifact instead of on a defect.  The object is deleted here
    REM for the same reason the two test objects above are: it is the one
    REM dependency edge scons does not keep.  A manual mono build has to delete
    REM it too (see REPORT-054 section 3).
    if exist "bin\obj\modules\mcp_server\mcp_trace.windows.editor.x86_64.obj" (
        del /q "bin\obj\modules\mcp_server\mcp_trace.windows.editor.x86_64.obj"
        echo   deleted bin\obj\modules\mcp_server\mcp_trace.windows.editor.x86_64.obj >> "%MCP_BUILD_LOG%"
    ) else (
        echo   absent bin\obj\modules\mcp_server\mcp_trace.windows.editor.x86_64.obj >> "%MCP_BUILD_LOG%"
    )
    echo FORCE: stale test objects gone ^(the header has no dependency edge^) >> "%MCP_BUILD_LOG%"
)

echo COMMAND: %SCONS_BIN% platform=windows target=editor module_mono_enabled=no tests=yes -j8 >> "%MCP_BUILD_LOG%"
"%SCONS_BIN%" platform=windows target=editor module_mono_enabled=no tests=yes -j8 >> "%MCP_BUILD_LOG%" 2>&1
set "RC=%ERRORLEVEL%"
echo EXIT_CODE=%RC% >> "%MCP_BUILD_LOG%"
echo ===== build_local END %DATE% %TIME% ===== >> "%MCP_BUILD_LOG%"

echo build_local: exit code = %RC%
echo build_local: log = %MCP_BUILD_LOG%
exit /b %RC%