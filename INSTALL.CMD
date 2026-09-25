@echo off
rem  Dark Colony / Council Wars patcher - START HERE (double-click this file).
rem
rem  This file only starts Apply-DarkColonyPatches.ps1 from the same folder, the actual patcher: a
rem  plain-text PowerShell script you can read in Notepad.  It runs it with Windows PowerShell 5.1,
rem  which is part of every Windows 10 and 11; nothing is downloaded or installed.
rem
rem  Why a starter file: Windows' own "Run with PowerShell" obeys the script execution policy, which
rem  refuses a script that came from the internet (the GitHub ZIP) - the console flashes and closes -
rem  or, on many PCs, every script.  "-ExecutionPolicy Bypass" lifts that for this one run only; no
rem  setting of your PC is changed.
rem
rem  Double-click: the installer opens (Welcome, one page each for Dark Colony, Dark Colony Ultimate
rem  and the map editor, Finished).  All three originals of this folder (dc16.exe, ENGEXP16.EXE,
rem  maped.exe) are ticked with all their fixes: Next, Next, Next, Patch writes "Dark Colony.exe",
rem  "Dark Colony Ultimate.exe" and "Dark Colony map editor 1.2.exe" beside them and a desktop
rem  shortcut of the same name to each.
rem  Nothing else is installed.  From a command prompt the command-line options work too:
rem     INSTALL.CMD -All -DesktopShortcut          (all three, like the window)
rem     INSTALL.CMD -List
rem     INSTALL.CMD -Verify "DC - Council wars\Dark Colony.exe"

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-DarkColonyPatches.ps1" %*

rem  On an error keep the console open when the file was double-clicked (started without arguments:
rem  the window was to open), so the message can be read; with arguments (a command prompt) just pass
rem  the exit code on.
set "rc=%errorlevel%"
if not "%rc%"=="0" if "%~1"=="" echo. & echo The patcher stopped with an error - see the message above. & pause
exit /b %rc%
