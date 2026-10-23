#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('remove','edit','reset','uninstall')][string]$Action,
    [string]$Name, [Parameter(Mandatory)][string]$Config,
    [Parameter(Mandatory)][string]$BinDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"
function Confirm-Action([string]$Message) {
    $answer = Read-Host "$Message [y/N]"
    return $null -ne $answer -and $answer -match '^(y|yes)$'
}
function Get-TextGroups([string]$Text) {
    $headers = [regex]::Matches($Text, '(?m)^[\t ]*[^\s#>][^\r\n]*')
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $end = if ($i + 1 -lt $headers.Count) { $headers[$i + 1].Index } else { $Text.Length }
        [pscustomobject]@{ Name = ($headers[$i].Value.Trim() -split '\s+')[0]; Start = $headers[$i].Index; End = $end }
    }
}
function Assert-EditedHost($HostConfig) {
    if ($null -eq $HostConfig) { $HostConfig = @{} }
    if ($HostConfig -isnot [Collections.IDictionary]) { throw '連線必須是 map。' }
    $kind = $HostConfig['type'] ?? 'ssh'
    if ($kind -cnotin @('ssh','tunnel')) { throw 'type 只支援 ssh / tunnel。' }
    foreach ($key in @('project','zone')) {
        if ([string]($HostConfig[$key] ?? '-') -cnotmatch '^(-|[A-Za-z0-9][A-Za-z0-9._-]*)$') { throw "無效欄位：$key" }
    }
    $instance = [string]($HostConfig['instance'] ?? $Name)
    if ($instance -cnotmatch '^([A-Za-z0-9._-]+@)?[A-Za-z0-9][A-Za-z0-9._-]*$') { throw '無效 instance。' }
    if ($kind -ceq 'tunnel') {
        if ($instance.Contains('@')) { throw 'Tunnel instance 不可包含使用者。' }
        foreach ($value in @($HostConfig['remote_port'], ($HostConfig['local_port'] ?? $HostConfig['remote_port']))) {
            if ([string]$value -cnotmatch '^[1-9][0-9]{0,4}$' -or [int]$value -gt 65535) { throw 'Tunnel port 必須為 1–65535。' }
        }
    }
}
if ($Action -in @('edit','remove') -and -not $Name) { throw "$Action 需要指定連線名稱。" }
if ($Action -in @('reset','uninstall') -and $Name) { throw "$Action 不接受連線名稱。" }
if ($Action -eq 'uninstall') {
    if (-not (Test-Path -LiteralPath "$BinDir/.iap/scripts/manage.ps1" -PathType Leaf)) {
        throw '只能從複製安裝的 iap 執行 uninstall；不會刪除原始碼。'
    }
    if (-not (Confirm-Action "移除 $BinDir/iap.ps1 與 PowerShell 配套檔案；保留設定 ${Config}，是否繼續？")) { return }
    foreach ($relative in @('iap.ps1','.iap/scripts/setup.ps1','.iap/scripts/common.ps1','.iap/scripts/manage.ps1','.iap/completions/iap.ps1','.iap/powershell-source')) {
        $file = Join-Path $BinDir $relative
        if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file -Force }
    }
    foreach ($relative in @('.iap/scripts','.iap/completions','.iap')) {
        $directory = Join-Path $BinDir $relative
        if ((Test-Path -LiteralPath $directory -PathType Container) -and -not @(Get-ChildItem -LiteralPath $directory -Force).Count) {
            Remove-Item -LiteralPath $directory
        }
    }
    Write-Host '已解除安裝 PowerShell iap，連線設定已保留。請自行移除 $PROFILE 中的補全設定。'
    return
}
$Config = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Config)
Assert-IapRegularTarget $Config
if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) { throw "找不到設定檔：$Config" }
$original = [IO.File]::ReadAllBytes($Config)
$text = [IO.File]::ReadAllText($Config)
$structured = [IO.Path]::GetExtension($Config) -in @('.json','.yaml','.yml')
$data = $null
$groups = @()
if ($structured) { $data = Read-IapStructuredConfig $Config; $names = @($data['hosts'].Keys) }
else { $groups = @(Get-TextGroups $text); $names = @($groups | ForEach-Object Name) }
if ($Action -in @('edit','remove') -and @($names | Where-Object { $_ -ceq $Name }).Count -ne 1) {
    throw "找不到唯一連線：$Name"
}
if ($Action -eq 'reset') {
    if (-not (Confirm-Action "清空 $Config 的全部 $($names.Count) 組連線，先備份並保留 defaults，是否繼續？")) { return }
    if ($structured) { $data['hosts'] = @{} } else { $text = "# IAP hosts — reset`n" }
} elseif ($Action -eq 'remove') {
    if (-not (Confirm-Action "從 $Config 移除連線 $Name 與其入口，是否繼續？")) { return }
    if ($structured) { $data['hosts'].Remove($Name) | Out-Null }
    else {
        $group = @($groups | Where-Object { $_.Name -ceq $Name })[0]
        $block = $text.Substring($group.Start, $group.End - $group.Start)
        $keep = [regex]::Replace($block, '\A[^\r\n]*(\r?\n|$)|(?m)^\s*>[^\r\n]*(\r?\n|$)', '')
        $text = $text.Substring(0, $group.Start) + $keep + $text.Substring($group.End)
    }
} else {
    if ($structured) {
        $isolated = [ordered]@{ hosts = [ordered]@{} }
        $isolated.hosts[$Name] = $data['hosts'][$Name]
        if ($data.Contains('defaults')) { $isolated.defaults = $data['defaults'] }
        $payload = ($isolated | ConvertTo-Json -Depth 100) + "`n"
        $suffix = '.json'
    } else {
        $group = @($groups | Where-Object { $_.Name -ceq $Name })[0]
        $payload = $text.Substring($group.Start, $group.End - $group.Start)
        $suffix = '.hosts'
    }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("iap-edit-$([guid]::NewGuid().ToString('N'))$suffix")
    try {
        Write-IapPrivateFile $temp $payload
        $editor = if ($env:EDITOR) { $env:EDITOR } elseif ($IsWindows) { 'notepad.exe' } else { 'vi' }
        $global:LASTEXITCODE = 0
        & $editor $temp
        if ($LASTEXITCODE -ne 0) { throw '編輯器失敗，未修改設定。' }
        $edited = [IO.File]::ReadAllText($temp)
        if ($edited -ceq $payload) { Write-Host '沒有變更。'; return }
        if ($structured) {
            $changed = Read-IapStructuredConfig $temp
            if ($changed['hosts'].Count -ne 1 -or $Name -cnotin @($changed['hosts'].Keys)) { throw '只能修改指定連線，請保留原本名稱。' }
            if (($changed['defaults'] | ConvertTo-Json -Depth 100 -Compress) -cne ($data['defaults'] | ConvertTo-Json -Depth 100 -Compress)) {
                throw '修改特定連線時不可變更 defaults。'
            }
            Assert-EditedHost $changed['hosts'][$Name]
            $data['hosts'][$Name] = $changed['hosts'][$Name]
        } else {
            $changedGroups = @(Get-TextGroups $edited)
            if ($changedGroups.Count -ne 1 -or $changedGroups[0].Name -cne $Name) { throw '只能修改指定連線，請保留原本名稱。' }
            $fields = @(([regex]::Matches($edited, '(?m)^[\t ]*[^\s#>][^\r\n]*')[0].Value.Trim()) -split '\s+')
            if ($fields.Count -lt 5 -or $fields.Count -gt 7) { throw '設定欄位數量不符。' }
            $hostConfig = @{type=$fields[1];project=$fields[2];zone=$fields[3];instance=$fields[4]}
            if ($fields.Count -ge 6) { $hostConfig.remote_port=$fields[5]; $hostConfig.local_port=$fields[-1] }
            Assert-EditedHost $hostConfig
            $text = $text.Substring(0, $group.Start) + $edited.TrimEnd("`r", "`n") + "`n" + $text.Substring($group.End)
        }
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
    if (-not (Confirm-Action "儲存 $Name 的修改到 $Config（先備份），是否繼續？")) { return }
}
Assert-IapRegularTarget $Config
if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($Config)) -cne [Convert]::ToBase64String($original)) {
    throw '設定在操作期間已變更，未寫入，請重試。'
}
$backup = "$Config.backup-$([guid]::NewGuid().ToString('N'))"
Write-IapPrivateFile $backup ''
[IO.File]::WriteAllBytes($backup, $original)
$staged = "$Config.tmp-$([guid]::NewGuid().ToString('N'))"
$content = if ($structured) { (($data | ConvertTo-Json -Depth 100).Replace("`r`n", "`n")) + "`n" } else { $text }
try {
    Write-IapPrivateFile $staged $content
    [IO.File]::Move($staged, $Config, $true)
} finally {
    if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Force }
}
Write-Host "原檔備份：$backup"
Write-Host "已更新：$Config"
