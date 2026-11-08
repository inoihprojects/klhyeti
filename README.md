# Klhyeti

A lightweight calendar and schedule app for Android, Windows, and Arch Linux. 
Paired devices can sync schedules, manually or automatically. 

Klhyeti is a name derived from Proto-Indo-European *\*kl̥h₁yéti*, a verb form 
that shares a root *\*kelh₁-* with the English word *calendar*.

DISCLAIMER: Claude was used extensively in the development of 
Klhyeti. I do not claim that the code is entirely mine, nor that it represents 
my programming skill.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the data model and sync design.

## Installing on Windows

Windows may warn that the app is from an unknown publisher because 
Klhyeti's Windows build isn't signed with a paid code-signing certificate. 
It can be ignored. To check that the download is the one published, 
compare its SHA-256 hash with `SHA256SUMS.txt` on the release page; in PowerShell:

```
Get-FileHash klhyeti-windows-x64.zip
```

## Licence

Klhyeti is licensed under the GNU General Public License, version 3 or later. 
See the [GNU General Public License](./LICENSE) for license.

Copyright (C) 2026 InoIH.
