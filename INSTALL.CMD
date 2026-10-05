@echo off
rem  Dark Colony / Council Wars patcher - START HERE (double-click this file).
rem
rem  This file only starts patcher\Apply-DarkColonyPatches.ps1, the actual patcher: a plain-text
rem  PowerShell script you can read in Notepad.  It runs it with Windows PowerShell 5.1, which is
rem  part of every Windows 10 and 11; nothing is downloaded or installed.  The patcher\ folder also
rem  holds the patcher's own data files (patcher\game, patcher\editor); INSTALL.CMD, PATCH_HOWTO.TXT
rem  and patcher\ together are the installer package (ModDB) - the game itself is not in it: without
rem  a game folder beside this file the installer copies the game from your two original discs
rem  (the checkbox on its welcome page; see PATCH_HOWTO.TXT).
rem
rem  Why a starter file: Windows' own "Run with PowerShell" obeys the script execution policy, which
rem  refuses a script that came from the internet (the GitHub ZIP) - the console flashes and closes -
rem  or, on many PCs, every script.  "-ExecutionPolicy Bypass" lifts that for this one run only; no
rem  setting of your PC is changed.
rem
rem  Double-click: the installer opens (Welcome, Options, one page each for Dark Colony Ultimate and
rem  the map editor, Ready to patch, Finished).  Choose the screen resolution and the battlefield
rem  interface - light (classic) or dark (console style) - once (nothing is preselected; 640x480 is the
rem  original), the originals of this folder (ENGEXP16.EXE, maped.exe) are ticked with all their fixes,
rem  and Patch writes "Dark Colony Ultimate.exe" and "Dark Colony Map Editor.exe" beside them and a
rem  desktop shortcut of the same name to each.  (The deprecated Classic "Dark Colony.exe" left the
rem  installer on 5 Oct 2026: Dark Colony Ultimate plays the whole Dark Colony campaign.)
rem  Nothing else is installed.  From a command prompt the command-line options work too:
rem     INSTALL.CMD -All -Resolution 1024x768 -Theme dark -DesktopShortcut    (like the window)
rem     INSTALL.CMD -InstallDir "%USERPROFILE%\Documents\Dark Colony" -CouncilWarsDisc D:\ -DarkColonyDisc "E:\Dark Colony.iso" -All -Resolution 1920x1080 -Theme dark
rem                                                                           (the game from the two discs, then patched there)
rem     INSTALL.CMD -List
rem     INSTALL.CMD -Verify "DC - Council wars\Dark Colony Ultimate.exe"

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0patcher\Apply-DarkColonyPatches.ps1" %*

rem  On an error keep the console open when the file was double-clicked (started without arguments:
rem  the window was to open), so the message can be read; with arguments (a command prompt) just pass
rem  the exit code on.
set "rc=%errorlevel%"
if not "%rc%"=="0" if "%~1"=="" echo. & echo The patcher stopped with an error - see the message above. & pause
exit /b %rc%
