Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File """ & Replace(WScript.ScriptFullName, WScript.ScriptName, "") & "CDriveCleaner.ps1""", 0, False
