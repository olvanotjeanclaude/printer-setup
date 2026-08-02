# Configure l'imprimante thermique USB (XP-80) pour la Caisse Varotranaka.
#
# A lancer sur le poste ou l'imprimante est branchee (clic droit >
# "Executer avec PowerShell", le script se releve en administrateur seul).
# Fait exactement ce que l'ecran "Imprimante USB" de la Caisse fait, plus
# un ticket de test, en affichant chaque etape et sa vraie erreur.
#
# ASCII volontaire (pas d'accents): un .ps1 sans BOM lu par PowerShell 5.1
# passe en ANSI et abime les accents selon la page de code du poste.

param(
  [string]$Share = 'XP80',
  [string]$Port = ''
)

$ErrorActionPreference = 'Stop'
$Driver = 'Generic / Text Only'

function Pause-Exit([int]$Code) {
  Write-Host ''
  Read-Host 'Appuyez sur Entree pour fermer'
  exit $Code
}

function Fail([string]$Message) {
  Write-Host "[ECHEC] $Message" -ForegroundColor Red
  Pause-Exit 1
}

function Ok([string]$Message) {
  Write-Host "[OK] $Message" -ForegroundColor Green
}

# --- Droits administrateur: se relancer via UAC si besoin ------------------
$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host 'Droits administrateur requis, relance...'
  $scriptArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Share', $Share)
  if ($Port) { $scriptArgs += @('-Port', $Port) }
  Start-Process powershell -Verb RunAs -ArgumentList $scriptArgs
  exit
}

Write-Host "=== Configuration imprimante USB ($Share) ===" -ForegroundColor Cyan
Write-Host ''

# --- 1. Services: spouleur et partage --------------------------------------
foreach ($serviceName in 'Spooler', 'LanmanServer') {
  $service = Get-Service $serviceName -ErrorAction SilentlyContinue
  if ($null -eq $service) { Fail "Service $serviceName introuvable." }
  if ($service.Status -ne 'Running') {
    Write-Host "Demarrage du service $serviceName..."
    try { Start-Service $serviceName } catch { Fail "Service $serviceName impossible a demarrer: $($_.Exception.Message)" }
  }
  Ok "Service $serviceName actif"
}

# --- 2. Port USB -----------------------------------------------------------
if (-not $Port) {
  $usbPorts = @(Get-PrinterPort | Where-Object Name -like 'USB*' | Select-Object -ExpandProperty Name)
  if ($usbPorts.Count -eq 0) {
    Fail "Aucun port USB d'impression. Branchez l'imprimante, allumez-la, attendez 10 secondes et relancez."
  }
  $Port = $usbPorts[0]
  if ($usbPorts.Count -gt 1) {
    Write-Host "Plusieurs ports USB trouves ($($usbPorts -join ', ')), utilisation de $Port."
    Write-Host "Pour en choisir un autre: relancez avec -Port USB002 par exemple."
  }
}
Ok "Port d'impression: $Port"

# --- 3. Pilote texte generique (livre avec Windows) ------------------------
if (-not (Get-PrinterDriver -Name $Driver -ErrorAction SilentlyContinue)) {
  Write-Host 'Installation du pilote "Generic / Text Only"...'
  try { Add-PrinterDriver -Name $Driver } catch { Fail "Pilote impossible a installer: $($_.Exception.Message)" }
}
Ok "Pilote '$Driver' present"

# --- 4. File d'impression sur le port -------------------------------------
$queue = Get-Printer -Name $Share -ErrorAction SilentlyContinue
if ($null -eq $queue) {
  Write-Host "Creation de la file $Share sur $Port..."
  try { Add-Printer -Name $Share -DriverName $Driver -PortName $Port } catch { Fail "File impossible a creer: $($_.Exception.Message)" }
} elseif ($queue.PortName -ne $Port) {
  # L'imprimante a change de prise: on rebranche la file existante.
  Write-Host "La file $Share pointait sur $($queue.PortName), bascule sur $Port..."
  try { Set-Printer -Name $Share -PortName $Port } catch { Fail "Port impossible a changer: $($_.Exception.Message)" }
}
Ok "File d'impression $Share sur $Port"

# --- 5. Partage (la Caisse imprime via \\localhost\XP80) -------------------
try { Set-Printer -Name $Share -Shared $true -ShareName $Share } catch { Fail "Partage impossible: $($_.Exception.Message)" }
Ok "Partagee sous le nom $Share"

# --- 6. Ticket de test, par le meme chemin que la Caisse -------------------
# "Envoye" n'est pas "imprime": copy /b reussit des que le spouleur accepte
# le travail. Si la file pointe sur le mauvais port USB, le travail reste
# coince dedans sans papier. Donc: purger, envoyer, verifier que le travail
# QUITTE la file; sinon essayer les autres ports USB un par un.

function Send-TestTicket([string]$OnPort) {
  Get-PrintJob -PrinterName $Share -ErrorAction SilentlyContinue |
    Remove-PrintJob -ErrorAction SilentlyContinue

  $bytes = New-Object System.Collections.Generic.List[byte]
  $bytes.AddRange([byte[]](0x1B, 0x40))                                # init
  $bytes.AddRange([Text.Encoding]::ASCII.GetBytes("VAROTRANAKA`nTest imprimante USB OK`n$Share sur $OnPort`n`n`n`n`n"))
  $bytes.AddRange([byte[]](0x1D, 0x56, 0x42, 0x00))                    # coupe papier
  $testFile = Join-Path $env:TEMP 'varotranaka-test.bin'
  [IO.File]::WriteAllBytes($testFile, $bytes.ToArray())

  cmd /c copy /b "$testFile" "\\localhost\$Share" | Out-Null
  $sendFailed = ($LASTEXITCODE -ne 0)
  Remove-Item $testFile -Force -ErrorAction SilentlyContinue
  if ($sendFailed) { return 'envoi-refuse' }

  for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 1
    $jobs = @(Get-PrintJob -PrinterName $Share -ErrorAction SilentlyContinue)
    if ($jobs.Count -eq 0) { return 'imprime' }
  }
  return 'coince'
}

Write-Host ''
$allPorts = @(Get-PrinterPort | Where-Object Name -like 'USB*' | Select-Object -ExpandProperty Name)
$candidates = @($Port) + @($allPorts | Where-Object { $_ -ne $Port })

$printedOn = ''
foreach ($tryPort in $candidates) {
  if ((Get-Printer -Name $Share).PortName -ne $tryPort) {
    Write-Host "Essai sur le port $tryPort..."
    Set-Printer -Name $Share -PortName $tryPort
  }
  Write-Host "Impression du ticket de test sur $tryPort..."
  $result = Send-TestTicket $tryPort

  if ($result -eq 'envoi-refuse') {
    Write-Host ''
    Write-Host "[ECHEC] L'envoi vers \\localhost\$Share a echoue." -ForegroundColor Red
    Write-Host 'Cause probable: "Partage de fichiers et d''imprimantes" desactive'
    Write-Host 'sur le profil reseau du poste (Parametres > Reseau > Options de partage).'
    Pause-Exit 1
  }
  if ($result -eq 'imprime') { $printedOn = $tryPort; break }

  Write-Host "Le travail reste coince sur $tryPort (pas de reponse de l'imprimante)."
}

# Ne pas laisser de travaux coinces derriere nous.
Get-PrintJob -PrinterName $Share -ErrorAction SilentlyContinue |
  Remove-PrintJob -ErrorAction SilentlyContinue

if (-not $printedOn) {
  Write-Host ''
  Write-Host "[ECHEC] Aucun port USB ($($candidates -join ', ')) n'a accepte le ticket." -ForegroundColor Red
  Write-Host "L'imprimante est-elle allumee, avec du papier, cable bien enfonce ?"
  Write-Host 'Essayez une autre prise USB du poste puis relancez ce script.'
  Pause-Exit 1
}

Ok "Ticket imprime sur $printedOn. Verifiez que le papier est sorti."
Write-Host ''
Write-Host 'Derniere etape, dans la Caisse:' -ForegroundColor Cyan
Write-Host "  Parametres imprimante > Imprimante USB > Deja partagees > $Share"
Pause-Exit 0
