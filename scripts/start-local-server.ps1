$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
Set-Location $repoPath

# WSL NAT mode: publish databases only on the Windows virtual adapter.
$gateway = (wsl -d Ubuntu-24.04 -- sh -c 'ip route show default').Trim().Split(' ')[2]
if ($gateway -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    throw 'Cannot determine the Windows host address from WSL.'
}
$env:DB_BIND_ADDRESS = $gateway
docker compose up -d --wait
if ($LASTEXITCODE -ne 0) { throw 'Failed to start databases. Check Docker Desktop.' }

$linuxRepo = (wsl -d Ubuntu-24.04 -- wslpath -a $repoPath.Replace('\', '/')).Trim()
wsl -d Ubuntu-24.04 --cd "$linuxRepo/server/skynet" -- make linux -j4
if ($LASTEXITCODE -ne 0) { throw 'Skynet build failed.' }

Write-Host 'Starting game server: ws://localhost:9601/ws (Ctrl+C to stop)'
wsl -d Ubuntu-24.04 --cd "$linuxRepo/server" -- env "DB_HOST=$gateway" sh ./run.sh config.wsl
exit $LASTEXITCODE
