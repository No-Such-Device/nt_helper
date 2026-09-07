<#
Reproduce Windows startup when Documents exists but refuses file creation.
Run only in a test VM, with nt_helper closed. This temporarily redirects the
current user's Documents and Roaming AppData to a new isolated directory,
and restores registry values and ACLs in finally. Existing user data is untouched.
Evidence is retained under LocalAppData/nt-helper-marker-repro-*.

Example:
  .\scripts\windows-startup-storage-smoke.ps1 -ExecutablePath C:\app\nt_helper.exe
To prove the v2.51.0 regression, also pass -ExpectedOutcome marker-failure.
#>
param(
  [Parameter(Mandatory=$true)][string]$ExecutablePath,
  [ValidateSet('starts','marker-failure')][string]$ExpectedOutcome='starts'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (Get-Process nt_helper -ErrorAction SilentlyContinue) { throw 'An nt_helper process is already running; leave it alone.' }
$originalLocalAppData = $env:LOCALAPPDATA
$root = Join-Path $env:LOCALAPPDATA ('nt-helper-marker-repro-' + [guid]::NewGuid().ToString('N'))
$docs = Join-Path $root 'OneDrive\Dokumente'
$app = Join-Path $docs 'nt_helper'
$support = Join-Path $root 'Roaming'
New-Item -ItemType Directory -Force $app,$support | Out-Null
$acl = Get-Acl $app
$deny = New-Object System.Security.AccessControl.FileSystemAccessRule([System.Security.Principal.WindowsIdentity]::GetCurrent().Name, 'CreateFiles', 'Deny')
$acl.AddAccessRule($deny)
Set-Acl $app $acl
$keys = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders','HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders')
$backup = @()
$proc = $null
try {
  foreach ($key in $keys) {
    foreach ($name in @('Personal','AppData')) {
      $k=Get-Item $key
      $exists=$k.GetValueNames() -contains $name
      $backup += [pscustomobject]@{Key=$key;Name=$name;Exists=$exists;Value=if($exists){$k.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}else{$null};Kind=if($exists){$k.GetValueKind($name)}else{'String'}}
    }
  }
  $backup | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $root 'registry-before.json')
  foreach ($entry in $backup) {
    $value=if($entry.Name -eq 'Personal'){$docs}else{$support}
    New-ItemProperty -Path $entry.Key -Name $entry.Name -Value $value -PropertyType ExpandString -Force | Out-Null
  }
  $env:LOCALAPPDATA=Join-Path $root 'Local'
  New-Item -ItemType Directory -Force $env:LOCALAPPDATA | Out-Null
  $exe=(Resolve-Path $ExecutablePath).Path
  $proc=Start-Process $exe -PassThru
  $log=Join-Path $env:LOCALAPPDATA 'nt_helper\logs\nt_helper_startup.log'
  for($i=0;$i -lt 100;$i++) {
    Start-Sleep -Milliseconds 300
    if(Test-Path $log) {
      $text=Get-Content $log -Raw
      if($text -match 'UNCAUGHT startup zone error|First frame rendered') {break}
    }
  }
  if(!(Test-Path $log)){throw "No startup log found at $log"}
  Copy-Item $log (Join-Path $root 'first-startup.log')
  $text=Get-Content $log -Raw
  if($ExpectedOutcome -eq 'marker-failure') {
    if($text -notmatch 'UNCAUGHT startup zone error: .*Cannot create file.*\.migrated') {
      throw "Expected marker creation failure; inspect $root"
    }
    "WINDOWS_MARKER_FAILURE_REPRODUCED evidence=$root"
  } else {
    if($text -match 'UNCAUGHT startup zone error' -or $text -notmatch 'First frame rendered' -or $proc.HasExited) {
      throw "App did not render its first frame; inspect $root"
    }
    $databases=@(Get-ChildItem $support -Recurse -Filter nt_helper_db.sqlite)
    if($databases.Count -ne 1 -or $databases[0].Length -le 0) {
      throw "Expected one non-empty fallback database; inspect $root"
    }
    $database=$databases[0].FullName
    $marker=Join-Path $databases[0].DirectoryName '.migrated'
    if(!(Test-Path $marker) -or (Test-Path (Join-Path $app 'nt_helper_db.sqlite'))) {
      throw "Incorrect storage selection; inspect $root"
    }
    # Restart with Documents writable: the initialized fallback must remain in use.
    Stop-Process -Id $proc.Id -Force
    $proc.WaitForExit()
    $acl.RemoveAccessRuleSpecific($deny)
    Set-Acl $app $acl
    Move-Item $log (Join-Path $root 'first-live-startup.log')
    $proc=Start-Process $exe -PassThru
    for($i=0;$i -lt 100;$i++) {
      Start-Sleep -Milliseconds 300
      if(Test-Path $log) {
        $text=Get-Content $log -Raw
        if($text -match 'UNCAUGHT startup zone error|First frame rendered') {break}
      }
    }
    Copy-Item $log (Join-Path $root 'second-startup.log')
    if($text -match 'UNCAUGHT startup zone error' -or $text -notmatch 'First frame rendered' -or $proc.HasExited) {
      throw "App did not restart after Documents recovered; inspect $root"
    }
    if((Test-Path (Join-Path $app '.migrated')) -or !(Test-Path $database)) {
      throw "App switched away from the initialized fallback; inspect $root"
    }
    "WINDOWS_STORAGE_SMOKE_PASSED database=$database evidence=$root"
  }
} finally {
  if($proc -and !$proc.HasExited) {Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue}
  foreach($b in $backup) {
    if($b.Exists){New-ItemProperty -Path $b.Key -Name $b.Name -Value $b.Value -PropertyType $b.Kind -Force | Out-Null}
    else{Remove-ItemProperty -Path $b.Key -Name $b.Name -ErrorAction SilentlyContinue}
  }
  $acl.RemoveAccessRuleSpecific($deny)
  Set-Acl $app $acl
  $env:LOCALAPPDATA=$originalLocalAppData
  'RESTORED_DOCUMENTS_APPDATA_AND_ACL'
}
