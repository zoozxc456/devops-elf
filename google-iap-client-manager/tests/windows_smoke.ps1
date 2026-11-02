#Requires -Version 7.2
# Windows smoke test: install and export without admin file-security privileges, then check private ACLs.
# -UserPath also exercises the user PATH update, which changes HKCU and is meant for disposable CI machines.
[CmdletBinding()]
param([switch]$UserPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows only.' }

# Hosted runners and elevated shells hold privileges a standard user lacks; with them, Set-Acl hid its SACL write.
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class IapSmokeToken {
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct TokenPrivileges { public uint Count; public long Luid; public uint Attributes; }
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool LookupPrivilegeValue(string system, string name, out long luid);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokenPrivileges state, uint length, IntPtr previous, IntPtr returned);
    [DllImport("kernel32.dll")]
    static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);
    public static void Remove(string name) {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28 /* TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY */, out token)) throw new Win32Exception();
        try {
            long luid;
            if (!LookupPrivilegeValue(null, name, out luid)) throw new Win32Exception();
            var state = new TokenPrivileges { Count = 1, Luid = luid, Attributes = 4 /* SE_PRIVILEGE_REMOVED */ };
            if (!AdjustTokenPrivileges(token, false, ref state, 0, IntPtr.Zero, IntPtr.Zero)) throw new Win32Exception();
            int error = Marshal.GetLastWin32Error();
            if (error != 0 && error != 1300 /* ERROR_NOT_ALL_ASSIGNED: not held */) throw new Win32Exception(error);
        } finally { CloseHandle(token); }
    }
}
'@
foreach ($name in @('SeSecurityPrivilege', 'SeBackupPrivilege', 'SeRestorePrivilege', 'SeTakeOwnershipPrivilege')) {
    [IapSmokeToken]::Remove($name)
}
if (whoami /priv | Select-String -SimpleMatch 'SeSecurityPrivilege') { throw 'SeSecurityPrivilege is still held.' }

$user = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Assert-PrivateFile([string]$Path) {
    $acl = Get-Acl -LiteralPath $Path
    $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    if (-not $acl.AreAccessRulesProtected -or $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $user -or
        $rules.Count -ne 1 -or $rules[0].IdentityReference.Value -ne $user -or
        $rules[0].AccessControlType -ne 'Allow' -or $rules[0].FileSystemRights -ne 'FullControl') {
        throw "Not private to the current user: $Path`n$($acl.Sddl)"
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) "iap smoke $([guid]::NewGuid().ToString('N'))"
$bin = Join-Path $root 'bin'
try {
    $installer = Join-Path $PSScriptRoot '../install.ps1'
    $pathOption = if ($UserPath) { @{} } else { @{ NoPath = $true } }
    & $installer -BinDir $bin @pathOption
    & $installer -BinDir $bin @pathOption
    Assert-PrivateFile (Join-Path $bin '.iap/powershell-source')
    if ($UserPath) {
        $entries = @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_.TrimEnd('\') -eq $bin })
        if ($entries.Count -ne 1) { throw "Expected one user PATH entry for $bin, found $($entries.Count)." }
    }

    $env:IAP_CONF = Join-Path $root 'hosts'
    [IO.File]::WriteAllText($env:IAP_CONF, "vm ssh - - vm`n")
    $iap = Join-Path $bin 'iap.ps1'
    $names = @(& $iap names)
    if ($names.Count -ne 1 -or $names[0] -cne 'vm') { throw "Unexpected iap names output: $names" }
    $exported = Join-Path $root 'export/hosts'
    & $iap export $exported
    Assert-PrivateFile $exported
    Write-Host 'Windows smoke test passed.'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
