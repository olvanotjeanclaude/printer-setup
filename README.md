# printer-setup

Sets up the USB thermal printer (XP-80) of a Varotranaka till on Windows. The
script does what the till's "Imprimante USB" screen does, showing each step
and its real error, then prints a test ticket through the exact same path the
till uses.

```
XP80 queue (Generic / Text Only driver) ──► \\localhost\XP80 share ──► copy /b RAW ──► paper
```

## Usage

Copy both files into the same folder on the machine the printer is plugged
into, then double-click `setup-imprimante-usb.bat`. The script elevates
itself to administrator (one UAC prompt).

Straight from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File setup-imprimante-usb.ps1
powershell -ExecutionPolicy Bypass -File setup-imprimante-usb.ps1 -Share XP80 -Port USB002
```

| Parameter | Default | |
|---|---|---|
| `-Share` | `XP80` | queue and share name, the one the till expects |
| `-Port` | first `USB*` port | printer port tried first |

## What the script does

1. Starts the `Spooler` and `LanmanServer` services if they are asleep.
2. Finds the USB printer port (`USB001`, ...).
3. Installs the "Generic / Text Only" driver, shipped with Windows.
4. Creates the `XP80` queue on that port, or repoints it if the printer
   moved plugs.
5. Shares the queue under the same name. The till prints through
   `\\localhost\XP80`.
6. Sends a RAW test ticket (`copy /b`), exactly like the till does.

"Sent" is not "printed". The spooler accepts the job before the paper moves,
and when the queue points at the wrong USB port the job sits in it with no
paper coming out. So the script verifies the job actually leaves the queue.
If it stays stuck, the other USB ports are tried one by one, and stuck jobs
are purged on the way out so nothing is left behind.

## When it fails

| Message | Likely cause |
|---|---|
| Sending to `\\localhost\XP80` failed | "File and printer sharing" disabled on the machine's network profile (Settings > Network > Sharing options) |
| The job stays stuck | printer off, out of paper, loose cable, or wrong USB plug |
| No USB printer port | plug in and power on the printer, wait 10 seconds, run again |

## Last step, in the till

Paramètres imprimante > Imprimante USB > Déjà partagées > `XP80`.

## Why the .ps1 is plain ASCII

PowerShell 5.1 reads a BOM-less `.ps1` using the machine's code page and
mangles accented characters. The script therefore contains none. This README,
rendered by GitHub, can.
