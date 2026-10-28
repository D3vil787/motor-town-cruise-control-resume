# keyhelper.ps1 - CruiseResume key helper. Presses keys on commands from q\*.cmd files.
# Safety:
#  - presses keys ONLY if the foreground window belongs to MotorTown-Win64-Shipping
#  - commands older than 6 seconds are dropped
#  - exits itself after the game was seen and then closed
# File is ASCII-only on purpose (Windows PowerShell 5.1 misreads UTF-8 without BOM).
param([string]$QueueDir)

if ([string]::IsNullOrEmpty($QueueDir)) {
    $QueueDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'q'
}
$baseDir   = Split-Path -Parent $QueueDir
$logFile   = Join-Path $baseDir 'helper.log'
$aliveFile = Join-Path $baseDir 'alive.txt'

function Log($m) {
    try { Add-Content -Path $logFile -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $m) } catch {}
}

Log ("helper process started pid={0} ps={1} queue={2}" -f $PID, $PSVersionTable.PSVersion, $QueueDir)

try {
    $mutex = New-Object System.Threading.Mutex($false, 'Global\CruiseResumeKeyHelper')
    if (-not $mutex.WaitOne(0)) { Log 'another helper is already running - exit'; exit }

    $cs = @"
using System;
using System.Runtime.InteropServices;
public static class KB {
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] public struct U { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public U u; }
    [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint n, INPUT[] p, int cb);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    public static void Send(ushort scan, bool ext, bool up) {
        INPUT[] a = new INPUT[1];
        a[0].type = 1;
        a[0].u.ki.wVk = 0;
        a[0].u.ki.wScan = scan;
        a[0].u.ki.dwFlags = 0x0008u | (ext ? 0x0001u : 0u) | (up ? 0x0002u : 0u);
        SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
    }
    public static uint ForegroundPid() {
        uint pid = 0;
        GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        return pid;
    }
}
"@
    Add-Type -TypeDefinition $cs
    Log 'Add-Type ok'

    # name -> (scan code, extended key)
    $keys = @{
        '1' = @(0x02, $false); '2' = @(0x03, $false); '3' = @(0x04, $false); '4' = @(0x05, $false)
        '5' = @(0x06, $false); '6' = @(0x07, $false); '7' = @(0x08, $false); '8' = @(0x09, $false)
        '9' = @(0x0A, $false); '0' = @(0x0B, $false)
        'pgup' = @(0x49, $true); 'pgdn' = @(0x51, $true)
    }

    $procName = 'MotorTown-Win64-Shipping'
    if (-not (Test-Path $QueueDir)) { New-Item -ItemType Directory -Path $QueueDir | Out-Null }

    $seenGame  = $false
    $missing   = 0
    $lastBeat  = 0
    $startedAt = Get-Date

    while ($true) {
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if (($now - $lastBeat) -ge 2) {
            Set-Content -Path $aliveFile -Value $now
            $lastBeat = $now
            if (Get-Process -Name $procName -ErrorAction SilentlyContinue) {
                if (-not $seenGame) { Log 'game process seen' }
                $seenGame = $true
                $missing = 0
            } else {
                $missing += 2
                if ($seenGame -and $missing -ge 20) { Log 'game closed - exit'; break }
                if ((-not $seenGame) -and (((Get-Date) - $startedAt).TotalMinutes -ge 15)) { Log 'game never started - exit'; break }
            }
        }

        $files = @(Get-ChildItem -Path $QueueDir -Filter '*.cmd' | Sort-Object Name)
        foreach ($f in $files) {
            $txt = Get-Content -Raw -Path $f.FullName
            if ([string]::IsNullOrWhiteSpace($txt)) { continue }
            $age = ((Get-Date) - $f.LastWriteTime).TotalSeconds
            Remove-Item -Path $f.FullName
            if ($age -gt 6) { Log ("drop stale cmd '{0}' age={1:N1}s" -f $txt.Trim(), $age); continue }

            $parts = $txt.Trim().Split(' ')
            if ($parts[0] -ne 'tap' -or $parts.Count -lt 2) { Log ("bad cmd '{0}'" -f $txt.Trim()); continue }
            $name = $parts[1].ToLower()
            if (-not $keys.ContainsKey($name)) { Log "unknown key '$name'"; continue }

            $gamePids = @(Get-Process -Name $procName -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
            $fg = [KB]::ForegroundPid()
            if ($gamePids -notcontains [int]$fg) { Log "skip tap ${name}: foreground pid $fg is not the game"; continue }

            $scan = [uint16]$keys[$name][0]
            $ext  = [bool]$keys[$name][1]
            [KB]::Send($scan, $ext, $false)
            Start-Sleep -Milliseconds 45
            [KB]::Send($scan, $ext, $true)
            Log "tap $name"
        }
        Start-Sleep -Milliseconds 20
    }
} catch {
    Log ("FATAL: " + ($_ | Out-String))
}
Log 'helper exit'
