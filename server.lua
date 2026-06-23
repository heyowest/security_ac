-- Format: PlayerHistory[source] = { coords = vector3(x, y, z), timestamp = os.time(), rebaseline = true }
-- `rebaseline` = true means "the next big position jump for this player is an expected,
-- legitimate teleport (e.g. the spawn teleport to their last location). Absorb it once
-- instead of flagging it." It is set when the server confirms the player has spawned,
-- so it is immune to how long the client took to load.
local PlayerHistory = {}
local MAX_LEGAL_SPEED = 100.0 -- The maximum meters a player can legally travel in 1 second (roughly the speed of the fastest supercar)

-- Admins are exempt from speed tracking (they legitimately noclip / teleport for moderation).
-- IsPlayerAceAllowed is server-side and trustworthy — the same check qbx_core uses for admin gating.
local EXEMPT_GROUPS = { 'god', 'admin', 'mod' }

local function IsExempt(src)
    for i = 1, #EXEMPT_GROUPS do
        if IsPlayerAceAllowed(src --[[@as string]], EXEMPT_GROUPS[i]) then return true end
    end
    return false
end

-- Mark a player so their next over-speed jump is treated as a legitimate teleport.
-- Call this whenever YOUR code performs a server-authorised teleport too.
local function ForgiveNextTeleport(src)
    if PlayerHistory[src] then
        PlayerHistory[src].rebaseline = true
    else
        PlayerHistory[src] = {
            coords = GetEntityCoords(GetPlayerPed(src)),
            timestamp = os.time(),
            rebaseline = true
        }
    end
end

CreateThread(function()
    while true do
        Wait(1000) -- Every 1 Second

        -- Loop through every player
        for _, playerId in ipairs(GetPlayers()) do
            local src = tonumber(playerId)
            local ped = GetPlayerPed(src)

            -- Don't track players who haven't fully spawned yet (still in character
            -- select / loading). qbx sets this once the player is actually in the world.
            -- Admins are skipped entirely so they never flag and never accumulate history.
            if DoesEntityExist(ped) and Player(src).state.isLoggedIn and not IsExempt(src) then
                local currentCoords = GetEntityCoords(ped)

                -- Check if we have the history for the player
                if PlayerHistory[src] then
                    local lastCoords = PlayerHistory[src].coords
                    local lastTime = PlayerHistory[src].timestamp

                    local distance = #(currentCoords - lastCoords)
                    local timeDelta = os.time() - lastTime

                    -- Prevent division by zero if the loop runs too fast
                    if timeDelta <= 0 then timeDelta = 1 end
                    local velocity = distance / timeDelta

                    if velocity > MAX_LEGAL_SPEED then
                        if PlayerHistory[src].rebaseline then
                            -- Expected teleport (spawn / legal tp): absorb this one jump.
                            PlayerHistory[src].rebaseline = false
                        else
                            print(('^1[SECURITY] Player %s (ID: %s) is going faster than the speed limit! (Speed: %s m/s)^0'):format(GetPlayerName(src), src, math.floor(velocity)))
                        end
                    end

                    -- Always update the baseline to the current position.
                    PlayerHistory[src].coords = currentCoords
                    PlayerHistory[src].timestamp = os.time()
                else
                    -- FIRST TIME SEEING PLAYER: initialise, and forgive their first jump
                    -- (this catches the spawn teleport even if it lands before login state syncs).
                    PlayerHistory[src] = {
                        coords = currentCoords,
                        timestamp = os.time(),
                        rebaseline = true
                    }
                end
            end
        end
    end
end)

-- Confirmed server-side spawn signal: the player has been teleported to their
-- chosen/last location. Forgive that one teleport, no matter how long loading took.
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    ForgiveNextTeleport(source)
end)

-- Public export: call before/after any legitimate teleport your scripts perform.
exports('ResetGracePeriod', function(targetSrc)
    ForgiveNextTeleport(targetSrc)
    print(('^3[INFO] Next teleport forgiven for Player %s (Legal Teleport)^0'):format(targetSrc))
end)

-- Clean up memory when a user leaves the server
AddEventHandler('playerDropped', function(reason)
    local src = tonumber(source)
    PlayerHistory[src] = nil
end)
