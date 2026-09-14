# Driver for the SM Flutter Windows desktop app (the product the
# SOCOGEN repository builds -- the process is named SM since the
# rename, while the database file kept its socogen_stock.db name).
#
# Gives an agent a programmatic handle on the running app: launch it,
# photograph it, click it, type into it, close it.
#
# Two things here are not guessable and are the reason this file exists:
#
#   1. PrintWindow needs PW_RENDERFULLCONTENT (flag 2). Flutter draws
#      through a child HWND that a normal screen grab -- or PrintWindow
#      with flag 0 -- captures as a solid blank rectangle. Flag 2 also
#      means the window does not need to be foreground to be captured.
#
#   2. `click` takes the coordinates you read off the screenshot. The
#      screenshot is the whole window (title bar and borders included)
#      while mouse input is addressed in client coordinates, and the two
#      differ by the frame. This script measures the frame with
#      ClientToScreen and converts for you. Pass what you see.
#
# Usage (from the repository root):
#   $D = ".claude\skills\run-socogen\drive.ps1"
#   powershell -ExecutionPolicy Bypass -File $D -Action launch -AppDir <dir>
#   powershell -ExecutionPolicy Bypass -File $D -Action capture -Out shot.png
#   powershell -ExecutionPolicy Bypass -File $D -Action click -X 640 -Y 202
#   powershell -ExecutionPolicy Bypass -File $D -Action keys -Text "HUIDIA1"
#   powershell -ExecutionPolicy Bypass -File $D -Action quit

param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("launch","quit","capture","click","keys","maximize","resize","info")]
  [string]$Action,

  [string]$AppDir = "",
  [string]$Out = "shot.png",
  [int]$X = 0,
  [int]$Y = 0,
  [string]$Text = "",
  [int]$W = 1360,
  [int]$H = 730,
  [int]$TimeoutSec = 90,

  # Pin every action to one instance. `launch` prints the pid to use.
  [Alias("Pid")][int]$PidTarget = 0
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$sig = @'
using System;
using System.Runtime.InteropServices;
public class SgWin {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int t, bool repaint);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, int extra);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
'@
if (-not ("SgWin" -as [type])) { Add-Type -TypeDefinition $sig }

# NOTE: do not name any local variable $h -- PowerShell variables are
# case-insensitive, so $h would silently overwrite the -H parameter and
# the window gets resized to the value of a window handle.
function Get-AppWindow {
  $all = @(Get-Process SM -ErrorAction SilentlyContinue |
           Where-Object { $_.MainWindowHandle -ne 0 })
  if ($all.Count -eq 0) { throw "SM window not found. Launch it first." }

  # Never pick blind. A developer commonly has their own instance open
  # on the real database; driving that one would type into their
  # session and write movements into their data. -Pid pins the instance
  # (launch prints it), and more than one running without it is an
  # error, not a coin flip.
  if ($PidTarget -ne 0) {
    $match = $all | Where-Object { $_.Id -eq $PidTarget } | Select-Object -First 1
    if ($null -eq $match) { throw "no SM window for pid $PidTarget" }
    return $match.MainWindowHandle
  }
  if ($all.Count -gt 1) {
    $ids = ($all | ForEach-Object { $_.Id }) -join ", "
    throw "several SM instances running (pids: $ids). Re-run with -Pid <id>."
  }
  return $all[0].MainWindowHandle
}

# Distance from the window's top-left (what a screenshot shows) to the
# client area's top-left (what mouse input is addressed in).
function Get-FrameOffset($hw) {
  $wr = New-Object SgWin+RECT
  [void][SgWin]::GetWindowRect($hw, [ref]$wr)
  $origin = New-Object SgWin+POINT
  $origin.X = 0; $origin.Y = 0
  [void][SgWin]::ClientToScreen($hw, [ref]$origin)
  return @{ X = $origin.X - $wr.Left; Y = $origin.Y - $wr.Top }
}

switch ($Action) {

  "launch" {
    if ([string]::IsNullOrWhiteSpace($AppDir)) {
      throw "launch needs -AppDir (the folder holding SM.exe)"
    }
    $exe = Join-Path $AppDir "SM.exe"
    if (-not (Test-Path $exe)) { throw "no SM.exe in $AppDir -- build first" }

    # -PassThru so we hold the process WE started. Scanning for "a
    # SM window" instead would hand back a developer's own installed
    # copy if one happens to be open -- and every later click would land
    # in their live session, on their real data.
    $started = Start-Process -FilePath $exe -WorkingDirectory $AppDir -PassThru
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
      $started.Refresh()
      if ($started.HasExited) {
        throw "app exited immediately (code $($started.ExitCode))"
      }
      if ($started.MainWindowHandle -ne 0) {
        Start-Sleep -Seconds 2      # let the first frame paint
        Write-Output "launched pid=$($started.Id)"
        exit 0
      }
      Start-Sleep -Milliseconds 500
    }
    throw "app did not open a window within $TimeoutSec s"
  }

  "quit" {
    # Only ever stops the pinned instance unless there is exactly one, so
    # a stray `quit` cannot close a developer's own copy mid-use.
    if ($PidTarget -ne 0) {
      Stop-Process -Id $PidTarget -Force -ErrorAction SilentlyContinue
      Write-Output "stopped pid=$PidTarget"
    } else {
      $all = @(Get-Process SM -ErrorAction SilentlyContinue)
      if ($all.Count -gt 1) {
        $ids = ($all | ForEach-Object { $_.Id }) -join ", "
        throw "several SM instances running (pids: $ids). Re-run with -Pid <id>."
      }
      $all | Stop-Process -Force
      Write-Output "stopped"
    }
  }

  "capture" {
    $hw = Get-AppWindow
    $r = New-Object SgWin+RECT
    [void][SgWin]::GetWindowRect($hw, [ref]$r)
    $width = $r.Right - $r.Left
    $height = $r.Bottom - $r.Top
    $bmp = New-Object System.Drawing.Bitmap($width, $height)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $gfx.GetHdc()
    [void][SgWin]::PrintWindow($hw, $hdc, 2)   # 2 = PW_RENDERFULLCONTENT
    $gfx.ReleaseHdc($hdc); $gfx.Dispose()
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "saved $Out (${width}x${height})"
  }

  "click" {
    # -X/-Y are coordinates read off a capture; converted here.
    $hw = Get-AppWindow
    [void][SgWin]::SetForegroundWindow($hw)
    Start-Sleep -Milliseconds 250
    $off = Get-FrameOffset $hw
    $pt = New-Object SgWin+POINT
    $pt.X = $X - $off.X
    $pt.Y = $Y - $off.Y
    [void][SgWin]::ClientToScreen($hw, [ref]$pt)
    [void][SgWin]::SetCursorPos($pt.X, $pt.Y)
    Start-Sleep -Milliseconds 120
    [SgWin]::mouse_event(0x0002, 0, 0, 0, 0)   # LEFTDOWN
    Start-Sleep -Milliseconds 60
    [SgWin]::mouse_event(0x0004, 0, 0, 0, 0)   # LEFTUP
    Write-Output "clicked image($X,$Y)"
  }

  "keys" {
    # SendKeys, NOT clipboard paste: Ctrl+V does not reach Flutter's
    # text fields here -- the field stays empty and the app reports
    # "Renseignez le nom et le mot de passe."
    # SendKeys treats + ^ % ~ ( ) { } [ ] as control characters; brace
    # them ("{+}") if a value needs them.
    $hw = Get-AppWindow
    [void][SgWin]::SetForegroundWindow($hw)
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait($Text)
    Write-Output "typed: $Text"
  }

  "maximize" {
    # Prefer this over -Action resize. MoveWindow can leave the Flutter
    # child view at its old size, which shows up in captures as an
    # unpainted black band down the right edge and along the bottom.
    $hw = Get-AppWindow
    [void][SgWin]::ShowWindow($hw, 3)   # SW_MAXIMIZE
    Start-Sleep -Seconds 2
    Write-Output "maximized"
  }

  "resize" {
    $hw = Get-AppWindow
    [void][SgWin]::MoveWindow($hw, 40, 30, $W, $H, $true)
    Start-Sleep -Seconds 2
    Write-Output "resized to ${W}x${H}"
  }

  "info" {
    $hw = Get-AppWindow
    $r = New-Object SgWin+RECT
    [void][SgWin]::GetWindowRect($hw, [ref]$r)
    $c = New-Object SgWin+RECT
    [void][SgWin]::GetClientRect($hw, [ref]$c)
    $off = Get-FrameOffset $hw
    Write-Output ("hwnd={0} window={1}x{2} client={3}x{4} frameOffset={5},{6}" -f `
      $hw, ($r.Right-$r.Left), ($r.Bottom-$r.Top), $c.Right, $c.Bottom, $off.X, $off.Y)
  }
}
