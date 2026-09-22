# Accessing the dev-Windows runner

`dev-Windows` is the nt_helper Windows 11 x64 GitHub Actions runner. It is the
VirtualBox VM `nt-helper-windows-x64` on the Linux host
`neal@dev.allosaurus-newton.ts.net`. The Linux host stays booted while the VM
runs. The VM files are under `/mnt/LINDATA/nt-helper-windows-runner`.

## Check or start the VM

From a machine with SSH access to the Linux host:

```bash
ssh neal@dev.allosaurus-newton.ts.net \
  'VBoxManage showvminfo "nt-helper-windows-x64" --machinereadable | grep "^VMState="'
```

If it reports `poweroff`, start it with:

```bash
ssh neal@dev.allosaurus-newton.ts.net \
  'VBoxManage startvm "nt-helper-windows-x64" --type headless'
```

The Windows service `actions.runner.No-Such-Device.dev-Windows` starts
automatically after boot. It has a delayed start, so allow a few minutes before
checking GitHub. Use the `thorinside` GitHub CLI credential for this repository:

```bash
gh auth switch -u thorinside
gh api orgs/No-Such-Device/actions/runners \
  --jq '.runners[] | select(.name=="dev-Windows") | {name,status,busy,labels:[.labels[].name]}'
```

The expected labels are `self-hosted`, `Windows`, `X64`, and `nt-helper`. Wait
for `status: online` and `busy: false` before scheduling maintenance or manual
tests.

## Run a GitHub Actions job

For Windows tests or builds, use this job selector:

```yaml
runs-on: [self-hosted, Windows, X64, nt-helper]
```

The existing release workflow in `.github/workflows/tag-build.yml` uses this
runner for the Windows package. `subosito/flutter-action` installs the pinned
Flutter SDK for that job. An interactive Windows shell does not necessarily
have `flutter` on its `PATH`; let the workflow set up Flutter for CI work.

## Run a one-off command in Windows

VirtualBox Guest Additions is installed, so commands can be run from the Linux
host without opening a desktop. The local Windows account is `runner`. Its
credential file is readable only by `neal` on the Linux host; do not print or
copy its contents into logs, scripts, or the repository.

```bash
ssh neal@dev.allosaurus-newton.ts.net \
  'VBoxManage guestcontrol "nt-helper-windows-x64" run \
    --username runner \
    --passwordfile /mnt/LINDATA/nt-helper-windows-runner/nt-helper-windows-x64/runner-password.txt \
    --exe "C:\Program Files\PowerShell\7\pwsh.exe" \
    -- -NoProfile -Command "Write-Output WINDOWS_POWERSHELL_OK"'
```

Arguments after `--` go straight to PowerShell; do not repeat the executable
path there. Use `Administrator` instead of `runner` only for tasks requiring
elevation. The GitHub runner service itself runs as `NETWORK SERVICE`, so a
manual command under `runner` is not identical to a CI job.

For manual app experiments, use a separate directory under
`C:\Users\runner\AppData\Local` instead of changing the Actions checkout at
`C:\actions-runner\_work`.

## View and control the Windows desktop

The VM's VNC endpoint listens only on the Linux host's loopback interface at
port `5930`. From the Mac, create an SSH tunnel in a terminal:

```bash
ssh -N -L 15930:127.0.0.1:5930 neal@dev.allosaurus-newton.ts.net
```

Keep that terminal open. In macOS Screen Sharing, connect to
`vnc://127.0.0.1:15930`. Use the VM's VNC credential supplied separately by
the owner; it is not stored in this repository. Close the Screen Sharing
window and stop the tunnel when finished.

## Stop the VM

The VM may stay running as the persistent runner. If host resources are needed,
check that GitHub reports it idle and that no Windows job is queued, then ask
Windows to shut down gracefully:

```bash
ssh neal@dev.allosaurus-newton.ts.net \
  'VBoxManage controlvm "nt-helper-windows-x64" acpipowerbutton'
```

Do not power it off during a job. The next `startvm` command above brings the
runner service back automatically.
