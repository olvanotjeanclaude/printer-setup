@echo off
rem Double-clic = configuration imprimante USB de la Caisse.
rem Copier ce .bat AVEC setup-imprimante-usb.ps1 dans le meme dossier.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-imprimante-usb.ps1" %*
