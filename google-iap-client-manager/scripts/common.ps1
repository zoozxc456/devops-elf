# Shared helpers for PowerShell 7.2+; no user configuration is executed.
function Get-IapConfigPath {
    if ($env:IAP_CONF) { return $env:IAP_CONF }
    $root = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
    $directory = Join-Path $root 'iap'
    foreach ($name in @('hosts.yaml', 'hosts.yml', 'hosts.json', 'hosts')) {
        $path = Join-Path $directory $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }
    return (Join-Path $directory 'hosts')
}
function Set-IapPrivateFile([string]$Path) {
    if ($IsWindows) {
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl = [Security.AccessControl.FileSecurity]::new()
        $acl.SetOwner($user)
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($user, 'FullControl', 'Allow'))
        Set-Acl -LiteralPath $Path -AclObject $acl
    } else {
        [IO.File]::SetUnixFileMode($Path, [IO.UnixFileMode]'UserRead,UserWrite')
    }
}
function Write-IapPrivateFile([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, '', [Text.UTF8Encoding]::new($false))
    Set-IapPrivateFile $Path
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}
function Assert-IapRegularTarget([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
        throw "拒絕覆寫目錄或連結：$Path"
    }
}
function Quote-IapPowerShell([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }

function Read-IapStructuredConfig([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    try { $data = ConvertFrom-Json -InputObject $text -AsHashtable }
    catch {
        if ([IO.Path]::GetExtension($Path) -eq '.json') { throw }
        $yq = Get-Command yq -CommandType Application -ErrorAction SilentlyContinue
        if ($null -eq $yq) { throw '讀一般 YAML 需要 mikefarah yq；原檔未修改。' }
        $json = & $yq.Source -o=json '.' $Path
        if ($LASTEXITCODE -ne 0) { throw 'YAML 格式有誤或不是 mikefarah yq。' }
        $data = ConvertFrom-Json -InputObject ($json -join "`n") -AsHashtable
    }
    if ($data -isnot [Collections.IDictionary] -or $data['hosts'] -isnot [Collections.IDictionary]) {
        throw '設定必須包含 hosts map。'
    }
    return $data
}
