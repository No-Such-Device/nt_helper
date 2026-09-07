<#
Causal test of the Windows .migrated / PathNotFoundException (errno 2) failure.
Run elevated only in a Windows test VM with Defender active, CFA initially off,
nt_helper closed, and its build runner idle. Temporarily enables real Defender
Controlled Folder Access and redirects the test user's known folders. Restores
Defender settings and registry values in finally. Do not interrupt the test.

Both executables must be extracted, complete public release packages:
  .\scripts\windows-startup-cfa-smoke.ps1 `
    -OldExecutable C:\old\nt_helper.exe -FixedExecutable C:\fixed\nt_helper.exe

The old binary must fail at .migrated with errno 2 and Defender event 1123;
the fixed binary must render a frame and create a non-empty fallback database.
Logs, event XML, package versions, and before/after settings are retained under
LocalAppData/nt-helper-cfa-causal-*. App processes inherit the elevated test token.
#>
param([Parameter(Mandatory=$true)][string]$OldExecutable,[Parameter(Mandatory=$true)][string]$FixedExecutable)
$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
if(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run elevated in a disposable Windows test VM.'}
if(Get-Process nt_helper -ErrorAction SilentlyContinue){throw 'nt_helper is already running.'}
$old=(Resolve-Path $OldExecutable).Path; $fixed=(Resolve-Path $FixedExecutable).Path
$pref=Get-MpPreference
if([int]$pref.EnableControlledFolderAccess -ne 0){throw 'This experiment requires CFA initially disabled; leave existing protection unchanged.'}
if(@($pref.ControlledFolderAccessAllowedApplications) -contains $old -or @($pref.ControlledFolderAccessAllowedApplications) -contains $fixed){throw 'Test executables must not already be explicitly allowed.'}
if(!(Get-MpComputerStatus).RealTimeProtectionEnabled){throw 'Defender real-time protection must be active.'}
$root=Join-Path $env:LOCALAPPDATA ('nt-helper-cfa-causal-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $root | Out-Null
$root | Set-Content "$env:TEMP\nt-helper-cfa-latest.txt"
Start-Transcript -Path (Join-Path $root 'transcript.txt') | Out-Null
$originalLocal=$env:LOCALAPPDATA
$pref=Get-MpPreference
$before=[pscustomobject]@{Mode=[int]$pref.EnableControlledFolderAccess;Protected=@($pref.ControlledFolderAccessProtectedFolders);Allowed=@($pref.ControlledFolderAccessAllowedApplications)}
$before | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $root 'defender-before.json')
$keys=@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders','HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders')
$backup=@(); $allowedAdded=$false; $protectedAdded=$false; $proc=$null; $failureRecord=$null
$protected=Join-Path $root 'ProtectedDocuments'
New-Item -ItemType Directory $protected | Out-Null
foreach($key in $keys){foreach($name in @('Personal','AppData')){$k=Get-Item $key; $exists=$k.GetValueNames() -contains $name; $backup += [pscustomobject]@{Key=$key;Name=$name;Exists=$exists;Value=if($exists){$k.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}else{$null};Kind=if($exists){$k.GetValueKind($name)}else{'String'}}}}
$backup | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $root 'registry-before.json')
# Prepare all fixtures before protection is enabled. No ACL or reparse changes.
foreach($phase in @('control','blocked','allowed','fixed','fixed-repeat')){
  New-Item -ItemType Directory -Force (Join-Path $protected "$phase\nt_helper"),(Join-Path $root "$phase\Roaming"),(Join-Path $root "$phase\Local") | Out-Null
}
function Invoke-Startup([string]$phase,[string]$exe,[string]$expect){
  $docs=Join-Path $protected $phase; $support=Join-Path $root "$phase\Roaming"
  foreach($b in $backup){$value=if($b.Name -eq 'Personal'){$docs}else{$support}; New-ItemProperty -Path $b.Key -Name $b.Name -Value $value -PropertyType ExpandString -Force | Out-Null}
  $env:LOCALAPPDATA=Join-Path $root "$phase\Local"
  $start=Get-Date; $script:proc=Start-Process $exe -PassThru
  $log=Join-Path $env:LOCALAPPDATA 'nt_helper\logs\nt_helper_startup.log'; $text=''
  try {
    for($i=0;$i -lt 100;$i++) {Start-Sleep -Milliseconds 300; if(Test-Path $log){$text=Get-Content $log -Raw; if($text -match 'UNCAUGHT startup zone error|First frame rendered'){break}}}
    if(Test-Path $log){Copy-Item $log (Join-Path $root "$phase-startup.log")}
    # Defender publishes blocks asynchronously, several seconds after CreateFile fails.
    $events=@()
    $attempts=if($expect -in @('blocked','fallback')){15}else{1}
    for($eventAttempt=0;$eventAttempt -lt $attempts;$eventAttempt++){
      $events=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational';Id=1123;StartTime=$start} -ErrorAction SilentlyContinue | Where-Object {
        $eventXml=[xml]$_.ToXml()
        $data=@{}; foreach($item in $eventXml.Event.EventData.Data){$data[$item.Name]=$item.'#text'}
        $data['Process Name'] -eq $exe -and $data['Path'] -like ('*\ProtectedDocuments\'+$phase+'\*')
      })
      if($events.Count -gt 0 -or $eventAttempt -eq $attempts-1){break}
      Start-Sleep -Seconds 2
    }
    $events | ForEach-Object {$_.ToXml()} | Set-Content (Join-Path $root "$phase-defender-events.xml")
    $failure=($text -split "`n" | Where-Object {$_ -match 'UNCAUGHT startup zone error'}) -join "`n"
    $result=[pscustomobject]@{Phase=$phase;Version=(Get-Item $exe).VersionInfo.FileVersion;Mode=[int](Get-MpPreference).EnableControlledFolderAccess;FirstFrame=($text -match 'First frame rendered');Failure=$failure;BlockEvents=$events.Count;DocumentsExists=(Test-Path $docs);DocumentsAttributes=(Get-Item $docs).Attributes.ToString();DocsDatabase=(Test-Path (Join-Path $docs 'nt_helper\nt_helper_db.sqlite'));FallbackDatabases=@(Get-ChildItem $support -Recurse -Filter nt_helper_db.sqlite | Select-Object FullName,Length)}
    $result | ConvertTo-Json -Depth 5 | Tee-Object -FilePath (Join-Path $root "$phase-result.json")
    if($expect -eq 'blocked'){
      if($text -notmatch 'PathNotFoundException: Cannot create file.*\.migrated.*errno = 2' -or $events.Count -lt 1){throw "Exact errno 2 marker failure plus Defender 1123 not reproduced in $phase"}
    }else{
      if($text -match 'UNCAUGHT startup zone error' -or $text -notmatch 'First frame rendered' -or $script:proc.HasExited){throw "Startup did not succeed in $phase"}
      if($expect -eq 'fallback' -and ($result.DocsDatabase -or $result.FallbackDatabases.Count -ne 1 -or $result.FallbackDatabases[0].Length -le 0 -or $events.Count -lt 1)){throw "Protected startup did not use fallback with an observed Defender block in $phase"}
      if($expect -eq 'documents' -and !$result.DocsDatabase){throw "Expected Documents database in $phase"}
    }
  }finally{if($script:proc -and !$script:proc.HasExited){Stop-Process -Id $script:proc.Id -Force; $script:proc.WaitForExit()};$script:proc=$null}
}
try {
  Invoke-Startup control $old documents
  Add-MpPreference -ControlledFolderAccessProtectedFolders $protected; $protectedAdded=$true
  Set-MpPreference -EnableControlledFolderAccess Enabled
  Start-Sleep -Seconds 4
  if([int](Get-MpPreference).EnableControlledFolderAccess -ne 1){throw 'CFA failed to enable'}
  Invoke-Startup blocked $old blocked
  Add-MpPreference -ControlledFolderAccessAllowedApplications $old; $allowedAdded=$true
  Start-Sleep -Seconds 4
  Invoke-Startup allowed $old documents
  Remove-MpPreference -ControlledFolderAccessAllowedApplications $old; $allowedAdded=$false
  Start-Sleep -Seconds 4
  Invoke-Startup fixed $fixed fallback
  Invoke-Startup fixed-repeat $fixed fallback
  'CFA_EXACT_CAUSE_AND_PUBLIC_FIX_VERIFIED' | Set-Content (Join-Path $root 'passed.txt')
} catch {
  $failureRecord=$_
  $_ | Out-String | Set-Content (Join-Path $root 'failure.txt')
  Write-Output "EXPERIMENT_FAILED: $_"
} finally {
  if($proc -and !$proc.HasExited){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue}
  Set-MpPreference -EnableControlledFolderAccess $before.Mode
  if($allowedAdded){Remove-MpPreference -ControlledFolderAccessAllowedApplications $old}
  if($protectedAdded){Remove-MpPreference -ControlledFolderAccessProtectedFolders $protected}
  foreach($b in $backup){if($b.Exists){New-ItemProperty -Path $b.Key -Name $b.Name -Value $b.Value -PropertyType $b.Kind -Force | Out-Null}else{Remove-ItemProperty -Path $b.Key -Name $b.Name -ErrorAction SilentlyContinue}}
  $env:LOCALAPPDATA=$originalLocal
  $p=Get-MpPreference
  [pscustomobject]@{Mode=[int]$p.EnableControlledFolderAccess;Protected=@($p.ControlledFolderAccessProtectedFolders);Allowed=@($p.ControlledFolderAccessAllowedApplications)} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $root 'defender-after.json')
  'RESTORED_DEFENDER_AND_KNOWN_FOLDERS'
  Stop-Transcript | Out-Null
}

if($failureRecord){throw $failureRecord}
