# Motor Town: Cruise Control Resume

A small [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) Lua mod for **Motor Town: Behind the Wheel** that adds a real-car style **Resume** to the game's built-in cruise control.

Cancel cruise (brake, etc.), slow down, then press **F7** — cruise turns back on and returns to the speed you had before.

[Русская версия](README.ru.md)

## How it works (short)

The mod watches the cruise-control HUD and remembers the target speed. On **F7** it presses the game's own keys for you: *toggle cruise* (`5`) and then *speed up / down* (`Page Up` / `Page Down`) until the target matches the remembered speed, checking the HUD after every burst. It does **not** write physics values or touch game files. Details: [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md).

Key presses are sent by a tiny PowerShell helper (`SendInput`) that only presses keys while the **game window is in the foreground**.

## Requirements

- Windows, Motor Town (Steam)
- [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) (experimental-latest, non-zDEV build) installed into `MotorTown\Binaries\Win64`
- Windows PowerShell 5.1 (built into Windows 10/11)

## Install

1. Install UE4SS so that `...\Motor Town\MotorTown\Binaries\Win64\ue4ss\Mods\` exists.
2. Copy the `CruiseResume` folder from this repo into that `Mods` folder:
   `...\Win64\ue4ss\Mods\CruiseResume\`
3. Start the game. The helper starts automatically and exits when the game closes.

Uninstall: delete the `CruiseResume` folder.

## Controls

| Key | Action |
|-----|--------|
| **F7** | Resume: turn cruise on and set the remembered speed |
| F9 | Enable / disable the mod (use while typing in chat) |
| F8 | Print status to `UE4SS.log` |
| F6 | Toggle verbose debug log |

The game's key bindings are assumed to be: toggle cruise = `5`, speed up = `Page Up`, speed down = `Page Down`. If yours differ, change `TOGGLE_KEY`, `INC_KEY`, `DEC_KEY` in the `CFG` table at the top of `Scripts/main.lua`. The helper currently knows these key names: `1`–`0`, `pgup`, `pgdn`; to use others add their scancodes to `$keys` in `helper/keyhelper.ps1`.

Other `CFG` options: `MIN_SAVE_KMH` (minimum speed to remember, 15), `BURST` (max presses per round, 15), `TAP_MS`, `SETTLE_MS`, `MAX_ROUNDS`.

## Usage notes

- Drive with the game's cruise control on; the mod remembers the HUD target speed automatically.
- Cancel cruise, then press F7. If cruise is already on, nothing happens.
- Remembered speed resets when you change vehicle.
- The first F7 after a fresh start may only start the helper; press F7 again after a couple of seconds.

## Troubleshooting

- `ue4ss\UE4SS.log` — look for `[CruiseResume]` lines (F8 prints status).
- `CruiseResume\helper.log` and `helper_stdout.log` — helper output and errors.
- Nothing happens: check the game window is focused, `helper.log` shows `tap ...`, and your key bindings match `CFG`.
- Some other mod binds F7/F9? Change `RESUME_KEY` / `DISABLE_KEY` in `CFG`.

## ⚠️ Disclaimer

This mod uses UE4SS code injection and simulated key presses. **Check the rules of the server you play on** — some servers forbid mods/macros or may run anti-cheat. Use at your own risk, on single-player or servers where it is allowed. Not affiliated with the game's developers.

## Tests

`python3 -I tests/sim_resume.py` runs the Lua logic against a simulated game (requires `pip install lupa`).

## License

MIT — see [LICENSE](LICENSE).
