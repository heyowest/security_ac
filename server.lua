-- security_ac — server-side speed/teleport tripwire.
--
-- PlayerHistory[source] = {
--   coords     = vector3,   -- last known position
--   timestamp  = number,    -- GetGameTimer() ms at last sample (NOT os.time — see below)
--   rebaseline = boolean,   -- next over-speed jump is an expected/legit teleport, absorb it once
--   strikes    = number,    -- accumulated violations; kicks at CONFIG.KickThreshold
-- }
local PlayerHistory = {}

-- ============================ CONFIG (server-only) ============================
-- This whole resource is server_scripts, so nothing here is readable by clients.
local CONFIG = {
    -- Max meters a player may legally travel per second on foot / in a ground
    -- vehicle (~360 km/h — above the fastest supercar). Aircraft are exempted
    -- separately because they routinely exceed this.
    MaxLegalSpeed = 100.0,

    -- How many strikes before a kick. Strikes accrue on each over-speed sample
    -- and decay on each clean one, so transient spikes fade instead of booting.
    KickThreshold = 3,

    -- Strikes removed per clean (under-speed) sample.
    StrikeDecay = 1,

    -- ACE groups exempt from tracking (they noclip / teleport for moderation).
    -- IsPlayerAceAllowed is server-side and trustworthy.
    ExemptGroups = { 'god', 'admin', 'mod' },

    -- Discord webhook for audit logging of kicks (and optionally warnings).
    -- Leave '' to disable webhook logging (console print still happens).
    DiscordWebhook = '',

    -- Also send a Discord log on each individual strike (not just the final kick).
    LogStrikes = false,
}
-- =============================================================================

local function IsExempt(src)
    for i = 1, #CONFIG.ExemptGroups do
        if IsPlayerAceAllowed(src --[[@as string]], CONFIG.ExemptGroups[i]) then return true end
    end
    return false
end

-- Aircraft legitimately exceed MaxLegalSpeed, so we skip players inside one.
-- GetVehicleType is a server-side native returning a type string.
local function IsInAircraft(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return false end
    local vtype = GetVehicleType(veh)
    return vtype == 'heli' or vtype == 'plane'
end

-- Mark a player so their next over-speed jump is treated as a legitimate teleport.
-- Call this whenever YOUR code performs a server-authorised teleport too.
local function ForgiveNextTeleport(src)
    if PlayerHistory[src] then
        PlayerHistory[src].rebaseline = true
    else
        PlayerHistory[src] = {
            coords = GetEntityCoords(GetPlayerPed(src)),
            timestamp = GetGameTimer(),
            rebaseline = true,
            strikes = 0,
        }
    end
end

-- Audit log: always print, optionally fire a Discord webhook embed.
-- `colour` is a Discord embed decimal colour (red = 15158332, orange = 15105570).
local function AuditLog(message, colour, force)
    print(message)
    if CONFIG.DiscordWebhook == '' then return end
    if not force and not CONFIG.LogStrikes then return end
    PerformHttpRequest(CONFIG.DiscordWebhook, function() end, 'POST', json.encode({
        username = 'security_ac',
        embeds = { {
            title = 'Anti-Cheat',
            description = message:gsub('%^%d', ''), -- strip console colour codes
            color = colour,
        } },
    }), { ['Content-Type'] = 'application/json' })
end

CreateThread(function()
    while true do
        Wait(1000) -- sample every second

        for _, playerId in ipairs(GetPlayers()) do
            local src = tonumber(playerId)
            local ped = GetPlayerPed(src)

            -- Only track fully-spawned, non-admin players that exist in the world.
            if DoesEntityExist(ped) and Player(src).state.isLoggedIn and not IsExempt(src) then
                local currentCoords = GetEntityCoords(ped)
                local hist = PlayerHistory[src]

                -- DEATH/RESPAWN: a dead ped is about to be teleported to the hospital
                -- on respawn. Forgive that jump and rebaseline here, framework-agnostic
                -- (no dependency on a specific death event firing server-side).
                local isDead = GetEntityHealth(ped) <= 0

                -- AIRCRAFT: legitimately faster than the ground speed cap — skip the
                -- check but keep the baseline fresh so leaving the aircraft is clean.
                local inAircraft = IsInAircraft(ped)

                if not hist then
                    -- First sighting: init and forgive the first jump (spawn teleport).
                    PlayerHistory[src] = {
                        coords = currentCoords,
                        timestamp = GetGameTimer(),
                        rebaseline = true,
                        strikes = 0,
                    }
                elseif isDead or inAircraft then
                    -- Absorb: just move the baseline forward, no velocity check.
                    hist.coords = currentCoords
                    hist.timestamp = GetGameTimer()
                    if isDead then hist.rebaseline = true end
                else
                    local now = GetGameTimer()
                    local distance = #(currentCoords - hist.coords)
                    local timeDeltaMs = now - hist.timestamp
                    if timeDeltaMs <= 0 then timeDeltaMs = 1 end       -- div-by-zero guard
                    local velocity = distance / (timeDeltaMs / 1000.0) -- meters per second

                    if velocity > CONFIG.MaxLegalSpeed then
                        if hist.rebaseline then
                            -- Expected teleport (spawn / legal tp): absorb one jump.
                            hist.rebaseline = false
                        else
                            hist.strikes = hist.strikes + 1
                            AuditLog(('^1[SECURITY] %s (ID: %s) over speed limit — %s m/s — strike %s/%s^0')
                                :format(GetPlayerName(src), src, math.floor(velocity), hist.strikes, CONFIG.KickThreshold),
                                15105570, false)

                            if hist.strikes >= CONFIG.KickThreshold then
                                AuditLog(('^1[SECURITY] %s (ID: %s) KICKED — sustained illegal speed (%s m/s)^0')
                                    :format(GetPlayerName(src), src, math.floor(velocity)), 15158332, true)
                                local player = exports.qbx_core:GetPlayer(src)
                                if player then
                                    player.Functions.Kick('[security_ac] Anormal hareket tespit edildi.')
                                end
                                PlayerHistory[src] = nil
                            end
                        end
                    else
                        -- Clean sample: decay accumulated strikes toward zero.
                        if hist.strikes > 0 then
                            hist.strikes = math.max(0, hist.strikes - CONFIG.StrikeDecay)
                        end
                    end

                    -- Only update baseline if the entry still exists (a kick clears it).
                    if PlayerHistory[src] then
                        PlayerHistory[src].coords = currentCoords
                        PlayerHistory[src].timestamp = now
                    end
                end
            end
        end
    end
end)

-- Confirmed server-side spawn: player teleported to their chosen/last location.
-- Forgive that one teleport no matter how long loading took.
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    ForgiveNextTeleport(source)
end)

-- Public export: call before/after any legitimate teleport your scripts perform.
exports('ResetGracePeriod', function(targetSrc)
    ForgiveNextTeleport(targetSrc)
    print(('^3[INFO] Next teleport forgiven for Player %s (legal teleport)^0'):format(targetSrc))
end)

-- Free memory when a player leaves.
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    PlayerHistory[src] = nil
end)
