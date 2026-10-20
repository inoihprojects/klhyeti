# Klhyeti

A free and open-source, lightweight calendar and schedule app for
Android, Windows, and Arch Linux, built with Flutter.
Devices sync manually through a sync file or directly over the local network 
once they are paired, at the press of a button or automatically. 
If conflicting edits are present, the user decides which one stays.

Klhyeti is a name derived from Proto-Indo-European *\*kl̥h₁yéti*, a verb form 
that shares a root *\*kelh₁-* with the English word *calendar*.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the data model and sync design.

DISCLAIMER: Claude was used extensively in the development of 
Klhyeti. I do not claim that the code is entirely mine, nor that it represents 
my programming skill.

## Installing on Windows

Windows may warn that the app is from an unknown publisher because 
Klhyeti's Windows build isn't signed with a paid code-signing certificate. 
It can be ignored. To check that the download is the one published, 
compare its SHA-256 hash with `SHA256SUMS.txt` on the release page; in PowerShell:

```
Get-FileHash klhyeti-windows-x64.zip
```

## Licence

Klhyeti is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.

It is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the [GNU General Public License](./LICENSE)
for more details.

Copyright (C) 2026 InoIH.
