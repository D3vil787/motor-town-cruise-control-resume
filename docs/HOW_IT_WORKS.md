# How it works / Как это устроено

## Findings about the game (UE4)

- Player pawn is e.g. `Golima_Semi_C` (`/Script/MotorTown.MTVehicle`), controller `MotorTownPlayerControllerBP_C`.
- `Pawn.Throttle` is overwritten by the game every frame → writing it has no effect on physics.
- Cruise state is not exposed as a reflected property. The native cruise is toggled by game actions `Driving_ToggleCruiseControl`, `Driving_IncSpeed`, `Driving_DecSpeed` (default keys here: `5`, `Page Up`, `Page Down`; 1 km/h per press, auto-repeat ~6/s when held).
- The HUD exposes the state:
  - `CruiseControlSpeedTextBlock` — text is the current cruise **target** speed (stays at the last value when cruise is off);
  - `CruiseControlVerticalBox` — `GetVisibility()` = 4 (visible) when cruise is on, 1 (Collapsed) when off.
- Vehicle speed: `pawn:GetVelocity()` × 0.036 → km/h.

## Dead ends

- Direct throttle writes (overwritten each frame).
- Enhanced Input injection: the game uses its own `MTInputKeyMapping`, no `Driving_*` InputAction objects exist.
- Hooks on `Actor:ReceiveTick` / `UserWidget:Tick` never fire.
- `R` as Resume key conflicts with the game's roadside-service menu → F7.

## Final design

1. `tick()` (every 150 ms): while cruise is on, store the HUD target as `saved` (fallback: stable speed). Reset on vehicle change.
2. `F7` while cruise is off: send tap `5`, then run closed-loop **rounds**: read HUD target `T`, `diff = saved - T`, queue `min(|diff|, 15)` taps of `pgup`/`pgdn`, wait `n*90 + 350` ms, repeat until `diff == 0` (max 25 rounds).
3. Taps are delivered via files `q\<unix time>_<seq>.cmd` containing `tap <name>`.
4. `helper/keyhelper.ps1` polls `q\` every 20 ms, drops commands older than 6 s, and only sends a key (scancode `SendInput`) if the foreground window belongs to `MotorTown-Win64-Shipping`. It writes a heartbeat `alive.txt` every 2 s (the mod considers it alive if ≤ 6 s old), uses mutex `Global\CruiseResumeKeyHelper`, logs to `helper.log`, and exits 20 s after the game closes (or after 15 min if the game never started).
5. The mod autostarts the helper through `os.execute('start "" /B powershell ...')`.

## Gotchas

- `keyhelper.ps1` must stay **ASCII-only**: Windows PowerShell 5.1 misreads UTF-8 without BOM.
- Access violations in UE4SS can't be caught by `pcall`; all engine calls are wrapped, and risky object scans (e.g. `FindAllOf("ActorComponent")` + `GetOwner`) are avoided.
