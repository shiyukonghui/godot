@echo off
REM ===========================================================================
REM  modules/mcp_server/scripts/mcp070_build_double.cmd -- TASK-070 item 4.
REM
REM  The DOUBLE PRECISION build command (`precision=double`), written down for
REM  the same reason `mcp057_build_mono.cmd` was (TASK-057 D-B1): a build variant
REM  that is only ever produced by hand cannot be reproduced, and a claim about
REM  `ValueSlot::FLOAT32` "in a `precision=double` build" is exactly that kind of
REM  claim.
REM
REM  Why this is a SEPARATE variant and does not disturb the other two builds
REM  (`SConstruct:1051-1053, 1171-1173`):
REM
REM      suffix += ".double"            when env["precision"] == "double"
REM      env["PROGSUFFIX"] = suffix + env.module_version_string + PROGSUFFIX
REM      env["OBJSUFFIX"]  = suffix + OBJSUFFIX
REM
REM  so the executables are `bin\godot.windows.editor.double.x86_64[.console].exe`
REM  and the object files are `<name>.windows.editor.double.x86_64.obj`.  The
REM  plain (`...x86_64.console.exe`) and mono (`...x86_64.mono.console.exe`)
REM  binaries are untouched, and the double build starts from an EMPTY object
REM  cache, i.e. it is a full build.
REM
REM  Same rules as the other two build scripts:
REM    * `tests=yes` is mandatory (the measurement runs a doctest);
REM    * the stale test objects and the mcp_trace object are deleted first
REM      (`core/version_generated.gen.h` and `tests/test_mcp_server.h` have no
REM      dependency edge back to their objects);
REM    * output goes to a log file AND to the console (nothing is suppressed);
REM    * BUILD SERIALLY (two concurrent scons runs rewrite
REM      `modules/modules_tests.gen.h`, D62).
REM
REM  Usage:
REM    modules\mcp_server\scripts\mcp070_build_double.cmd
REM    modules\mcp_server\scripts\mcp070_build_double.cmd --probe-only
REM ===========================================================================
setlocal

set "REPO=%~dp0..\..\.."
if not exist "%REPO%\SConstruct" (
    echo FATAL: "%REPO%" does not look like the Godot repository root ^(no SConstruct^).
    exit /b 2
)

set "PROBE_ONLY=0"
if /i "%~1"=="--probe-only" set "PROBE_ONLY=1"

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
    echo   Looked at, in this order:
    echo     1. the SCONS environment variable  ^(currently: "%SCONS%"^)
    echo     2. `scons` on PATH
    echo     3. D:\Anaconda\Scripts\scons.exe
    exit /b 3
)

for %%I in ("%SCONS_BIN%") do set "SCONS_DIR=%%~dpI"
set "PATH=%SCONS_DIR%;%PATH%"

echo scons: %SCONS_BIN%  ^(from %SCONS_FROM%^)
if "%PROBE_ONLY%"=="1" (
    echo probe-only: resolved, not building.
    exit /b 0
)

if not defined MCP_BUILD_LOG set "MCP_BUILD_LOG=%TEMP%\mcp070\double_build.log"
if not exist "%TEMP%\mcp070" mkdir "%TEMP%\mcp070" >nul 2>&1

cd /d "%REPO%"
echo ===== mcp070_build_double START %DATE% %TIME% ===== >> "%MCP_BUILD_LOG%"
echo SCONS: %SCONS_BIN% ^(from %SCONS_FROM%^) >> "%MCP_BUILD_LOG%"

for %%F in (
    "bin\obj\modules\mcp_server\tests\test_mcp_server.windows.editor.double.x86_64.obj"
    "bin\obj\tests\test_main.windows.editor.double.x86_64.obj"
    "bin\obj\modules\mcp_server\mcp_trace.windows.editor.double.x86_64.obj"
) do (
    if exist "%%~F" (
        del /q "%%~F"
        echo   deleted %%~F >> "%MCP_BUILD_LOG%"
    ) else (
        echo   absent %%~F >> "%MCP_BUILD_LOG%"
    )
)

echo COMMAND: %SCONS_BIN% platform=windows target=editor module_mono_enabled=no tests=yes precision=double -j8 >> "%MCP_BUILD_LOG%"
"%SCONS_BIN%" platform=windows target=editor module_mono_enabled=no tests=yes precision=double -j8 >> "%MCP_BUILD_LOG%" 2>&1
set "RC=%ERRORLEVEL%"
echo EXIT_CODE=%RC% >> "%MCP_BUILD_LOG%"
echo ===== mcp070_build_double END %DATE% %TIME% ===== >> "%MCP_BUILD_LOG%"

echo mcp070_build_double: exit code = %RC%
echo mcp070_build_double: log = %MCP_BUILD_LOG%
exit /b %RC%