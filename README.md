# security_ac

A lightweight, server-authoritative **speed / teleport anti-cheat** for QBox (`qbx_core`).
It watches how far each player moves per second and logs anyone travelling faster than a
human possibly could — the classic signature of speed hacks and noclip.

No dependencies beyond `ox_lib`. No client code. No performance cost worth measuring
(one server thread that wakes once per second).

---

## How it works

Every second the server measures each player's distance travelled since the last check and
divides by the elapsed time to get a velocity in **m/s**. If that exceeds `MAX_LEGAL_SPEED`
(default `100.0` m/s — roughly the fastest supercar in the game), it logs a `[SECURITY]`
warning to the server console with the player's name and ID.

Because all of this runs **on the server** using the player's real synced position, there is
nothing for a cheat to disable or spoof. The client is never trusted.

### Teleports don't false-flag

A legitimate teleport (spawning in, an admin TP, a job/property teleport) is a single huge
position jump. The script forgives **exactly one** such jump after each spawn:

- When QBox confirms a player spawned (`QBCore:Server:OnPlayerLoaded`), that player's next
  over-speed jump is treated as the expected spawn teleport and absorbed.
- This is **not** a timer, so it doesn't matter whether the player loaded in 3 seconds or 3
  minutes — the forgiveness waits for the actual jump.
- Only **one** jump is forgiven per spawn, so it can't be abused as a free noclip window.
  Continuous noclip trips on the very next tick.

### Admins are ignored

Players in the `god`, `admin`, or `mod` ACE groups are skipped entirely — staff legitimately
noclip and teleport while moderating. Edit `EXEMPT_GROUPS` in `server.lua` to change which
groups are exempt.

---

## Installation

1. Drop the `security_ac` folder into your resources.
2. Ensure it **after** `qbx_core` in your `server.cfg`:

   ```cfg
   ensure ox_lib
   ensure qbx_core
   # ...
   ensure security_ac
   ```

3. Restart the server (or `ensure security_ac`). That's it.

---

## Configuration

Open `server.lua`:

| Setting              | Default                      | Meaning                                                        |
|----------------------|------------------------------|----------------------------------------------------------------|
| `MAX_LEGAL_SPEED`    | `100.0`                      | Max metres a player may travel per second before it's flagged. |
| `EXEMPT_GROUPS`      | `{ 'god', 'admin', 'mod' }`  | ACE permission groups that are never tracked.                  |

> Tip: raise `MAX_LEGAL_SPEED` if you run high-speed custom vehicles or aircraft mods and see
> false positives; lower it for a stricter ground-only server.

---

## Integrating with your own scripts

If **your** resource teleports a player (admin menu, job, property entry, jail, etc.), tell
`security_ac` it's a legitimate teleport so it doesn't get flagged. Call the export **right
before you move the player**, server-side, passing the player's `source`:

```lua
-- server side, just before you teleport the player
exports.security_ac:ResetGracePeriod(src)

-- then do your teleport as usual...
SetEntityCoords(GetPlayerPed(src), x, y, z)
```

That marks the player's next big position jump as expected and absorbs it once. Everything
after that tick is checked normally.

**Notes**
- `ResetGracePeriod(src)` takes the player **server id** (`source`), not a citizenid.
- The spawn teleport is already handled for you — you only need this for teleports your own
  code performs.
- It's safe to call even if the player has no history yet; one will be created.

---

## Reading the logs

A flag looks like this in the server console:

```
[SECURITY] Player heyowest (ID: 12) is going faster than the speed limit! (Speed: 240 m/s)
```

This script **logs only** — it does not kick or ban, so a few false positives can't hurt
anyone. Use the logs to identify suspects, then act with your own admin tools. Wiring the
flag up to a Discord webhook or an auto-kick is a one-line change in `server.lua` if you want it.

---

## License

Free to use and modify. Released as a community freebie — no attribution required (but
appreciated).
