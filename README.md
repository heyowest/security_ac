# security_ac

A lightweight, server-authoritative **speed / teleport anti-cheat** for QBox (`qbx_core`).
It watches how far each player moves per second and acts on anyone travelling faster than a
human possibly could — the classic signature of speed hacks and noclip.

No dependencies beyond `ox_lib`. No client code. No performance cost worth measuring
(one server thread that wakes once per second).

![Security AC Logo](security-ac-logo.png)

---

## How it works

Every second the server measures each player's distance travelled since the last check and
divides by the elapsed time (millisecond-precise, via `GetGameTimer`) to get a velocity in
**m/s**. If that exceeds `MaxLegalSpeed` (default `100.0` m/s — above the fastest supercar in
the game), the player earns a **strike**.

Strikes accumulate on each over-speed sample and **decay** on each clean one. A player is only
kicked once they reach `KickThreshold` strikes (default `3`). This is deliberate: server-side
position is itself synced from the client, so a single noisy reading or one stray teleport
should never boot a legitimate player — only *sustained* illegal movement does.

Because the check runs **on the server** using the player's real synced position, there is
nothing for a casual cheat to disable. The client is never trusted.

### Teleports don't false-flag

A legitimate teleport (spawning in, an admin TP, a job/property teleport) is a single huge
position jump. The script forgives **exactly one** such jump after each spawn:

- When QBox confirms a player spawned (`QBCore:Server:OnPlayerLoaded`), that player's next
  over-speed jump is treated as the expected spawn teleport and absorbed.
- This is **not** a timer, so it doesn't matter whether the player loaded in 3 seconds or 3
  minutes — the forgiveness waits for the actual jump.
- Only **one** jump is forgiven per spawn, so it can't be abused as a free noclip window.

### Death and respawn don't false-flag

When a player dies, their respawn at the hospital is a large teleport. The script detects the
dead state server-side (`GetEntityHealth`) and forgives the respawn jump automatically — no
dependency on any specific death event firing.

### Aircraft are exempt

Helicopters and planes legitimately exceed the ground speed cap. Players inside one (detected
via the server-side `GetVehicleType` native) skip the speed check entirely, so pilots are never
struck for flying fast.

### Admins are ignored

Players in the `god`, `admin`, or `mod` ACE groups are skipped entirely — staff legitimately
noclip and teleport while moderating. Edit `ExemptGroups` in the `CONFIG` block to change which
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

All settings live in the `CONFIG` block at the top of `server.lua` (server-only — nothing here
is ever sent to clients):

| Setting           | Default                      | Meaning                                                                 |
|-------------------|------------------------------|-------------------------------------------------------------------------|
| `MaxLegalSpeed`   | `100.0`                      | Max metres a player may travel per second before a strike is issued.    |
| `KickThreshold`   | `3`                          | Strikes required before the player is kicked.                           |
| `StrikeDecay`     | `1`                          | Strikes removed per clean (under-speed) sample.                         |
| `ExemptGroups`    | `{ 'god', 'admin', 'mod' }`  | ACE permission groups that are never tracked.                           |
| `DiscordWebhook`  | `''`                         | Webhook URL for audit logging. Empty = console only.                    |
| `LogStrikes`      | `false`                      | Also send a Discord log on each strike, not just the final kick.        |

> Tip: raise `MaxLegalSpeed` if you run high-speed custom ground vehicles and see false
> positives; lower `KickThreshold` for a stricter server, or raise it to be more forgiving.

---

## Audit logging

Every strike and kick is printed to the server console. If `DiscordWebhook` is set, the same
events are posted as a Discord embed (orange on a strike, red on a kick). A kick always logs;
individual strikes log to Discord only when `LogStrikes = true`.

Console output looks like:

```
[SECURITY] heyowest (ID: 12) over speed limit — 240 m/s — strike 1/3
[SECURITY] heyowest (ID: 12) over speed limit — 251 m/s — strike 2/3
[SECURITY] heyowest (ID: 12) over speed limit — 248 m/s — strike 3/3
[SECURITY] heyowest (ID: 12) KICKED — sustained illegal speed (248 m/s)
```

---

## Integrating with your own scripts

If **your** resource teleports a player (admin menu, job, property entry, jail, etc.), tell
`security_ac` it's a legitimate teleport so it doesn't earn a strike. Call the export **right
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
- Spawn, death/respawn, and aircraft are already handled for you — you only need this for
  teleports your own code performs.
- It's safe to call even if the player has no history yet; one will be created.
- With the strike system, forgetting to call it on a teleport now costs a single strike rather
  than an instant kick — but calling it keeps legitimate players' strike counts clean.

---

## License

Free to use and modify. Released as a community freebie — no attribution required (but
appreciated).
