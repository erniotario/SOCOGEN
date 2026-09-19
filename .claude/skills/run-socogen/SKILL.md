---
name: run-socogen
description: Build, launch and drive the SM Flutter Windows desktop app (the SOCOGEN repository) - run it, screenshot it, click through its screens, and verify a change in the real app rather than only in tests. Use for "run the app", "start SM", "start SOCOGEN", "screenshot the app", "check X on the running app", "click through Inventaire/Rapports".
---

# Running SM

Windows Flutter desktop app. The product is named **SM**; the
repository, the Dart package and the database file are still named
socogen, and deliberately so. Paths below are relative to the
**repository root**.

The app is driven by `.claude/skills/run-socogen/drive.ps1` — launch,
capture, click, type — against a throwaway copy built by
`.claude/skills/run-socogen/sandbox.py`. Use the sandbox: the app keeps
its database **beside the executable**, so driving the build output in
place writes movements into the developer's real working data.

## Prerequisites

Flutter with Windows desktop support, plus the Visual Studio C++
toolchain (the runner is compiled with MSBuild/`cl.exe`). Already set up
on this machine. Python 3 for `sandbox.py` — stdlib only; the repo's
`.venv\Scripts\python.exe` works.

## Build

```bash
cd flutter_app && flutter build windows --debug
```

Produces `flutter_app/build/windows/x64/runner/Debug/SM.exe`.
Incremental builds take ~110 s; the first one is several minutes of
`cl.exe`. Release builds are `--release`, but debug is what you want for
driving.

## Run (agent path)

### 1. Make a sandbox

```bash
.venv/Scripts/python.exe .claude/skills/run-socogen/sandbox.py \
  flutter_app/build/windows/x64/runner/Debug \
  "$SCRATCH/sandbox"
```

Copies the whole runner folder, strips every account, and adds one
throwaway admin: **`verif` / `verif1234`**. It prints the catalogue size
and every negative balance, which is useful context before you start.
Delete the directory when done.

### 2. Launch and drive

`launch` prints the pid. Pass it to every later call as `-Pid` — the
driver refuses to guess when more than one instance is running.

```powershell
$D = ".claude\skills\run-socogen\drive.ps1"
powershell -ExecutionPolicy Bypass -File $D -Action launch -AppDir "$SCRATCH\sandbox"
# -> launched pid=15096

$AppPid = 15096
function Go($opts) { & powershell -ExecutionPolicy Bypass -File $D @opts -Pid $AppPid }

Go @{Action="maximize"}
Go @{Action="capture"; Out="$SCRATCH\shot.png"}
Go @{Action="click"; X=690; Y=410}
Go @{Action="keys";  Text="verif"}
Go @{Action="quit"}
```

**`click` takes the coordinates you read off the capture.** The
screenshot is the whole window; mouse input is client-relative. The
driver measures the frame and converts. Don't subtract anything
yourself. (`-Action info` prints the offset if you want to check.)

**Read every screenshot.** A blank frame or an error banner means the
step failed, however cheerful the driver's output was.

### 3. Log in and reach a screen

Coordinates below are for a **maximized 1382x754** window — re-read them
from your own capture if the window differs.

```powershell
Go @{Action="click"; X=690; Y=410}; Start-Sleep -Milliseconds 500   # Nom d'utilisateur
Go @{Action="keys";  Text="verif"}; Start-Sleep -Milliseconds 500
Go @{Action="click"; X=690; Y=467}; Start-Sleep -Milliseconds 500   # Mot de passe
Go @{Action="keys";  Text="verif1234"}; Start-Sleep -Milliseconds 500
Go @{Action="click"; X=690; Y=532}; Start-Sleep -Seconds 4          # Se connecter
```

Sidebar destinations, same window size: Tableau de bord `105,133`,
Produits `105,175`, Entrées `105,217`, Sorties `105,259`,
Transactions `105,318`, Inventaire `105,359`, Rapports `105,402`,
Magasins `105,461`, Sécurité `105,503`, Paramètres `105,545`.

Worked example — count an article on Inventaire (Ekie is preselected):

```powershell
Go @{Action="click"; X=105; Y=359}; Start-Sleep -Seconds 3   # Inventaire
Go @{Action="click"; X=648; Y=202}; Start-Sleep -Milliseconds 500   # Article
Go @{Action="keys";  Text="HUIDIA1"}; Start-Sleep -Seconds 2
Go @{Action="click"; X=648; Y=246}; Start-Sleep -Seconds 2   # autocomplete option
Go @{Action="click"; X=359; Y=256}; Start-Sleep -Milliseconds 500   # Quantité comptée
Go @{Action="keys";  Text="12"}; Start-Sleep -Seconds 1
Go @{Action="click"; X=376; Y=309}; Start-Sleep -Seconds 2   # Ajouter au comptage
Go @{Action="capture"; Out="$SCRATCH\counted.png"}
```

Lands a row reading `HUIDIA1 | Ekie | -149 théorique | 12 compté | +161`.

### 4. Check what the app wrote

The sandbox database is ordinary SQLite; read it directly rather than
squinting at screenshots. Current stock is **derived**
(`initial_stock + entrées − sorties`), never stored:

```bash
.venv/Scripts/python.exe -c "
import sqlite3
db = sqlite3.connect(r'$SCRATCH/sandbox/socogen_stock.db')
print(db.execute(\"SELECT date, reference, quantity FROM stock_entries WHERE supplier='Inventaire physique'\").fetchall())
"
```

## Run (human path)

`cd flutter_app && flutter run -d windows` builds and launches with hot
reload attached. Fine for a person at the keyboard; useless for an agent
— it opens on the developer's real database and waits.

## Test

```bash
cd flutter_app && flutter analyze   # keep at zero
cd flutter_app && flutter test      # ~300 tests
```

Don't run the suite while a driven app is up: `web_report_test.dart`
binds port 8765, which CLAUDE.md notes collides with a running build
serving its Wi-Fi sync.

## Gotchas

- **`PrintWindow` needs flag 2 (`PW_RENDERFULLCONTENT`).** Flutter draws
  into a child HWND; a normal screen grab, or flag 0, returns a solid
  blank rectangle. Flag 2 also captures without the window being
  foreground.
- **The driver refuses to type when it cannot take the foreground, and
  that refusal is the point.** Windows blocks `SetForegroundWindow` for a
  process that has not recently received input, so while a person is
  typing, the call returns, the window stays behind, and `SendKeys` goes
  to *their* foreground window. A `^a` followed by `{DEL}` sent into
  someone's editor is not a failed step, it is their work deleted.
  `Assert-Foreground` now retries for ~1.5 s and exits 3 rather than
  send input blind — check `$LASTEXITCODE` in your wrapper and stop.
- **`^a` does not select-all in these text fields.** The typed text is
  appended instead of replacing, so `admin` + `verif` becomes
  `adminverif` and the login fails for a reason the screenshot explains
  only if you read it. Clear with `{END}{BS 40}`.
- **Re-capture before every click, not once per sequence.** A click that
  navigates changes the layout under the coordinates you read a moment
  ago, and the next blind click lands on whatever moved into that spot —
  here it opened an edit dialog on a real movement. Nothing was saved,
  but `Annuler` and `Enregistrer` sit side by side.
- **Clipboard paste does not reach Flutter's text fields.**
  `Set-Clipboard` + `SendKeys ^v` leaves the field empty and the login
  reports "Renseignez le nom et le mot de passe." Use
  `-Action keys` (SendKeys). It sends `+ ^ % ~ ( ) { } [ ]` as control
  characters — brace them (`{+}`) in literal text.
- **PowerShell variables are case-insensitive**, and this bites twice
  here. A local `$h` silently overwrites a `-H` parameter; a function
  parameter `$p` overwrites an outer `$P`. The driver avoids `$h`; in
  your own wrappers name the pid `$AppPid`, not `$P`.
- **Use `-Action maximize`, not `resize`.** `MoveWindow` can leave the
  Flutter child view at its old size, which shows up in captures as an
  unpainted black band down the right edge — easily misread as a layout
  bug. It is not one.
- **The Windows database lives beside the executable.**
  `build/windows/x64/runner/Debug/socogen_stock.db` is real working
  data, not build junk, and `flutter clean` destroys it. That is the
  whole reason for `sandbox.py`.
- **No session persistence.** Every launch lands on the login screen.
- **Someone may be using the machine.** The window steals focus when
  clicked, so a person at the keyboard and the driver will interleave
  keystrokes. The sandbox holds only `verif`, which makes this
  detectable: if the sidebar shows any other name, you are not the only
  one driving — stop and ask.
- CLAUDE.md records that `flutter build windows` can exit 0 on failure;
  read the output text, not just the exit code.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `SM window not found` | Nothing running — `-Action launch` first. |
| `several SM instances running (pids: ...)` | Pass `-Pid <id>`; don't let it pick. |
| `Cannot convert value "System.Collections.Hashtable" to type "System.Int32"` | Your wrapper's `$p` collided with `-Pid`. Rename to `$opts`/`$AppPid`. |
| Capture is a blank rectangle | Not using `PrintWindow` flag 2. |
| Typed text never appears | Clipboard paste; use `-Action keys`. |
| Black band right/bottom of capture | Used `resize`; use `maximize`. |
| Sidebar shows a name other than `verif` | A human is typing into the same window. |
| Clicks land slightly off | Window was resized between capture and click — re-capture, re-read coordinates. |
