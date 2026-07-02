Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & Replace(WScript.ScriptFullName, WScript.ScriptName, "") & "CDriveCleaner.ps1""", 0, False
