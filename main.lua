-- ============================================================
--  SILENT ASSASSINS — AXIOM HUB
--  Attack Suppressor + Silent Kill Bot + AFK Coin Farm
--  Source confirmed: GameRemoteEvent multiplexed dispatcher
-- ============================================================

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local Workspace      = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- EVENTS (source confirmed path)
-- ============================================================
local Events            = require(ReplicatedStorage.Events)
local GameRemoteEvent   = Events.GameRemoteEvent
local GameBindableEvent = Events.GameBindableEvent

-- ============================================================
-- STATE
-- ============================================================
local State = {
    -- attack suppressor
    suppressReveal   = false,
    attackKey        = nil,   -- filled once we confirm from hook

    -- silent kill bot
    silentKillBot    = false,
    killDelay        = 0.5,
    kills            = 0,

    -- footstep suppressor
    suppressFootstep = false,

    -- AFK farm
    afkFarm          = false,

    -- esp
    espEnabled       = false,
    espObjects       = {},
    revealedPlayers  = {},   -- tracks who is currently revealed

    -- dodge
    autoDodge        = false,
    dodgeRadius      = 15,
    dodgeCooldown    = false,
    dodges           = 0,
}

-- ============================================================
-- NOTIFY
-- ============================================================
local function notify(title, content, duration)
    pcall(function()
        Rayfield:Notify({
            Title    = title,
            Content  = content,
            Duration = duration or 3,
            Image    = 4483362458,
        })
    end)
end

-- ============================================================
-- UTILITY
-- ============================================================
local function getRoot()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function isAlive()
    local h = getHum()
    return h and h.Health > 0
end
local function distTo(hrp)
    local root = getRoot()
    if not root or not hrp then return math.huge end
    return (root.Position - hrp.Position).Magnitude
end

-- ============================================================
-- HOOK 1 — SUPPRESS REVEAL ON ATTACK
-- Source: GameRemoteEvent dispatches string key to server
-- RevealPlayerEvent comes back via GameBindableEvent
-- We hook the BindableEvent to block RevealPlayerEvent for US
-- AND hook outgoing FireServer to intercept attack key
-- ============================================================
local attackKeyFound = nil

-- hook outgoing GameRemoteEvent to log attack key
local oldFireServer
pcall(function()
    oldFireServer = hookfunction(GameRemoteEvent.FireServer, function(self, key, ...)
        -- log every outgoing fire to find attack key
        if State.suppressReveal or State.silentKillBot then
            print("[Axiom OutHook] GameRemoteEvent key:", key)
        end

        -- if we found the attack key and suppressor is on,
        -- fire the attack but then immediately block the incoming reveal
        if attackKeyFound and key == attackKeyFound and State.suppressReveal then
            -- fire attack normally
            local result = oldFireServer(self, key, ...)
            -- schedule reveal block for next frame
            State._blockNextReveal = true
            task.delay(0.1, function()
                State._blockNextReveal = false
            end)
            return result
        end

        return oldFireServer(self, key, ...)
    end)
end)

-- hook incoming GameRemoteEvent to intercept RevealPlayerEvent for self
-- source: v_u_9["CloneRevealOthers"] and v_u_9["ReplicationEvent"]
-- reveal comes through GameBindableEvent as "RevealPlayerEvent"
for _, conn in getconnections(GameBindableEvent.Event) do
    local old; old = hookfunction(conn.Function, function(key, ...)
        -- suppress footstep events
        if key == "CreateFootstep" and State.suppressFootstep then
            return -- block footstep entirely
        end

        -- suppress reveal for local player
        if key == "RevealPlayerEvent" then
            local data = ...
            -- track revealed players for ESP
            if type(data) == "table" or type(data) == "string" then
                State.revealedPlayers[tostring(data)] = os.clock()
            end
            -- if suppressor on, block reveal for ourselves
            if State.suppressReveal and State._blockNextReveal then
                print("[Axiom] Reveal suppressed!")
                return
            end
        end

        return old(key, ...)
    end)
end

-- also hook GameRemoteEvent incoming for CloneRevealOthers
for _, conn in getconnections(GameRemoteEvent.OnClientEvent) do
    local old; old = hookfunction(conn.Function, function(key, ...)
        if key == "CloneRevealOthers" and State.suppressReveal then
            print("[Axiom] CloneRevealOthers suppressed")
            return
        end
        return old(key, ...)
    end)
end

-- ============================================================
-- ATTACK KEY FINDER
-- hooks left click and logs what GameRemoteEvent fires
-- ============================================================
local function startAttackKeyFinder()
    print("[Axiom] Attack key finder active — left click to attack")
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            -- monitor next outgoing fire
            task.spawn(function()
                task.wait(0.05)
                -- the hook above will print it
                -- we also try to find it via tool activation
                local char = LocalPlayer.Character
                if char then
                    local tool = char:FindFirstChildOfClass("Tool")
                    if tool then
                        print("[Axiom] Tool active:", tool.Name)
                    end
                end
            end)
        end
    end)
end
startAttackKeyFinder()

-- ============================================================
-- HOOK 2 — FOOTSTEP SUPPRESSOR
-- Source: GameBindableEvent "CreateFootstep" →
--         FootstepController:spawnFootstep(p12, false)
-- We already block it in the BindableEvent hook above
-- ============================================================

-- ============================================================
-- SILENT KILL BOT
-- Finds closest player, teleports behind them,
-- fires attack remote, teleports away before reveal lands
-- ============================================================
local function getClosestEnemy()
    local root = getRoot()
    if not root then return nil end
    local closest, closestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local char = p.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 then
            local d = distTo(hrp)
            if d < closestDist then
                closestDist = d
                closest = { player=p, hrp=hrp, hum=hum, dist=d }
            end
        end
    end
    return closest
end

local function silentKill(target)
    local root = getRoot()
    if not root or not target then return end

    -- step 1: teleport directly behind target silently
    local behindPos = target.hrp.CFrame * CFrame.new(0, 0, 3)
    root.CFrame = behindPos

    task.wait(0.05)

    -- step 2: suppress next reveal
    State._blockNextReveal = true

    -- step 3: fire attack via tool activation (left click simulation)
    -- try tool :Activate() first
    local char = LocalPlayer.Character
    if char then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then
            -- fire tool activate
            pcall(function()
                tool:Activate()
            end)
            -- also try remote directly if we know the key
            if attackKeyFound then
                pcall(function()
                    GameRemoteEvent:FireServer(attackKeyFound, target.player)
                end)
            end
        end
    end

    -- step 4: immediately teleport away to break reveal association
    task.wait(0.08)
    local awayPos = root.CFrame * CFrame.new(math.random(-20, 20), 0, math.random(-20, 20))
    root.CFrame = awayPos

    -- step 5: unblock reveal after escape window
    task.delay(0.3, function()
        State._blockNextReveal = false
    end)

    State.kills = State.kills + 1
    print(string.format("[Axiom] Silent kill on %s | total: %d", target.player.Name, State.kills))
end

local function silentKillLoop()
    while State.silentKillBot do
        if isAlive() then
            local target = getClosestEnemy()
            if target and target.dist < 60 then
                silentKill(target)
                task.wait(State.killDelay)
            end
        end
        task.wait(0.5)
    end
end

-- ============================================================
-- AFK COIN FARM
-- Source: game auto-rejoins after 18min of inactivity
-- We spoof activity by moving slightly every few seconds
-- AND suppress footsteps so nobody sees us moving
-- Also follows closest player to rack up proximity time
-- ============================================================
local function afkFarmLoop()
    print("[Axiom] AFK Farm started")
    local lastJiggle = os.clock()

    while State.afkFarm do
        local root = getRoot()
        if root then
            -- micro-jiggle to prevent AFK kick (every 10s)
            if os.clock() - lastJiggle > 10 then
                -- tiny movement that won't be noticed
                root.CFrame = root.CFrame * CFrame.new(0.1, 0, 0)
                task.wait(0.1)
                root.CFrame = root.CFrame * CFrame.new(-0.1, 0, 0)
                lastJiggle = os.clock()
            end

            -- follow closest player silently
            local target = getClosestEnemy()
            if target and target.dist > 8 and target.dist < 50 then
                -- walk toward them via humanoid (not teleport — more natural)
                local hum = getHum()
                if hum then
                    hum:MoveTo(target.hrp.Position)
                end
            end
        end
        task.wait(3)
    end
    print("[Axiom] AFK Farm stopped")
end

-- ============================================================
-- ESP
-- color: red = revealed (attacked recently), white = silent
-- ============================================================
local function clearESP()
    for _, obj in ipairs(State.espObjects) do
        pcall(function() obj:Destroy() end)
    end
    State.espObjects = {}
end

local function buildESP()
    clearESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then continue end

        local bb = Instance.new("BillboardGui")
        bb.Name        = "AxiomESP_"..player.Name
        bb.AlwaysOnTop = true
        bb.Size        = UDim2.new(0, 180, 0, 70)
        bb.StudsOffset = Vector3.new(0, 3.5, 0)
        bb.Adornee     = hrp
        bb.Parent      = game.CoreGui

        local nameL = Instance.new("TextLabel", bb)
        nameL.Name                   = "Name"
        nameL.Size                   = UDim2.new(1, 0, 0.4, 0)
        nameL.BackgroundTransparency = 1
        nameL.TextStrokeTransparency = 0
        nameL.Font                   = Enum.Font.GothamBold
        nameL.TextScaled             = true
        nameL.Text                   = player.Name

        local hpL = Instance.new("TextLabel", bb)
        hpL.Name                   = "HP"
        hpL.Size                   = UDim2.new(1, 0, 0.3, 0)
        hpL.Position               = UDim2.new(0, 0, 0.4, 0)
        hpL.BackgroundTransparency = 1
        hpL.TextStrokeTransparency = 0
        hpL.Font                   = Enum.Font.Gotham
        hpL.TextScaled             = true

        local distL = Instance.new("TextLabel", bb)
        distL.Name                   = "Dist"
        distL.Size                   = UDim2.new(1, 0, 0.3, 0)
        distL.Position               = UDim2.new(0, 0, 0.7, 0)
        distL.BackgroundTransparency = 1
        distL.TextColor3             = Color3.fromRGB(200, 200, 200)
        distL.TextStrokeTransparency = 0
        distL.Font                   = Enum.Font.Gotham
        distL.TextScaled             = true

        local hl = Instance.new("SelectionBox")
        hl.Name             = "AxiomHL_"..player.Name
        hl.LineThickness    = 0.06
        hl.SurfaceTransparency = 0.8
        hl.Adornee          = char
        hl.Parent           = game.CoreGui

        table.insert(State.espObjects, bb)
        table.insert(State.espObjects, hl)
    end
end

-- ESP heartbeat update
RunService.Heartbeat:Connect(function()
    if not State.espEnabled then return end
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local bb   = game.CoreGui:FindFirstChild("AxiomESP_"..player.Name)
        local hl   = game.CoreGui:FindFirstChild("AxiomHL_"..player.Name)

        if not bb then
            if hrp and hum then pcall(function() buildESP() end) end
            continue
        end

        if not hrp or not hum then continue end

        -- is this player recently revealed?
        local revealed = State.revealedPlayers[player.Name]
            and (os.clock() - State.revealedPlayers[player.Name]) < 3

        -- color: orange/red = revealed, white = silent
        local col = revealed
            and Color3.fromRGB(255, 80, 50)
            or  Color3.fromRGB(255, 255, 255)

        local hpRatio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
        local hpCol   = Color3.fromRGB(
            math.floor((1 - hpRatio) * 255),
            math.floor(hpRatio * 220),
            50
        )

        local nameL = bb:FindFirstChild("Name")
        local hpL   = bb:FindFirstChild("HP")
        local distL = bb:FindFirstChild("Dist")

        if nameL then
            nameL.TextColor3 = col
            nameL.Text = (revealed and "👁 " or "🥷 ") .. player.Name
            nameL.TextStrokeColor3 = Color3.new(0,0,0)
        end
        if hpL then
            hpL.TextColor3 = hpCol
            hpL.Text = string.format("HP %.0f/%.0f", hum.Health, hum.MaxHealth)
            hpL.TextStrokeColor3 = Color3.new(0,0,0)
        end
        if distL then
            distL.Text = string.format("%.0f studs", distTo(hrp))
        end
        if hl then
            hl.Color3        = col
            hl.SurfaceColor3 = col
        end
    end
end)

-- ============================================================
-- AUTO DODGE
-- watches for players approaching fast and teleports away
-- ============================================================
local lastPositions = {}

RunService.Heartbeat:Connect(function()
    if not State.autoDodge then return end
    if not isAlive() then return end
    if State.dodgeCooldown then return end

    local root = getRoot()
    if not root then return end

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local char = p.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        local dist = distTo(hrp)
        if dist > State.dodgeRadius then
            lastPositions[p.Name] = hrp.Position
            continue
        end

        local lastPos = lastPositions[p.Name]
        lastPositions[p.Name] = hrp.Position
        if not lastPos then continue end

        local velocity   = hrp.Position - lastPos
        local toUs       = root.Position - hrp.Position
        local approaching = velocity:Dot(toUs.Unit)

        if approaching > 0.8 then
            State.dodgeCooldown = true
            State.dodges = State.dodges + 1

            local right    = root.CFrame.RightVector
            local dir      = math.random(0,1) == 0 and right or -right
            root.CFrame    = CFrame.new(root.Position + dir * 15 + Vector3.new(0, 0.5, 0))

            print(string.format("[Axiom] Dodged %s | #%d", p.Name, State.dodges))
            task.delay(0.5, function() State.dodgeCooldown = false end)
            break
        end
    end
end)

-- ============================================================
-- RAYFIELD WINDOW
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name                   = "Axiom Hub  |  Silent Assassins",
    LoadingTitle           = "Axiom Hub",
    LoadingSubtitle        = "Attack Suppressor + Kill Bot + AFK",
    Theme                  = "Default",
    DisableRayfieldPrompts = false,
    ConfigurationSaving    = { Enabled = false },
    Discord                = { Enabled = false },
    KeySystem              = false,
})

-- ============================================================
-- TAB 1 — ATTACK SUPPRESSOR
-- ============================================================
local SuppressTab = Window:CreateTab("Suppress", 6031071057)

SuppressTab:CreateToggle({
    Name = "Suppress Reveal on Attack", CurrentValue = false, Flag = "SuppressReveal",
    Callback = function(val)
        State.suppressReveal = val
        notify("Suppress", val and "Reveal blocked on attack" or "Off", 2)
    end,
})

SuppressTab:CreateToggle({
    Name = "Suppress Footsteps", CurrentValue = false, Flag = "SuppressFootstep",
    Callback = function(val)
        State.suppressFootstep = val
        notify("Footsteps", val and "Hidden" or "Visible", 2)
    end,
})

SuppressTab:CreateButton({
    Name = "Print Attack Key",
    Callback = function()
        notify("Attack Key", attackKeyFound and ("Found: "..tostring(attackKeyFound)) or "Left click in game — check console", 4)
        print("[Axiom] Current attack key:", tostring(attackKeyFound))
    end,
})

SuppressTab:CreateButton({
    Name = "Set Attack Key Manually",
    Callback = function()
        -- common attack key patterns to try
        local candidates = {"Attack", "Hit", "Swing", "Use", "Action", "Fire", "Strike", "Slash"}
        print("[Axiom] Try these attack key candidates:")
        for _, k in ipairs(candidates) do print("  "..k) end
        notify("Attack Key", "Check console for candidates", 3)
    end,
})

-- ============================================================
-- TAB 2 — SILENT KILL BOT
-- ============================================================
local KillTab = Window:CreateTab("Kill Bot", 6031068421)

KillTab:CreateToggle({
    Name = "Silent Kill Bot", CurrentValue = false, Flag = "SilentKillBot",
    Callback = function(val)
        State.silentKillBot = val
        if val then task.spawn(silentKillLoop) end
        notify("Kill Bot", val and "Hunting silently" or "Off", 2)
    end,
})

KillTab:CreateSlider({
    Name = "Kill Delay (ms)", Range = {100, 2000}, Increment = 50,
    CurrentValue = 500, Flag = "KillDelay",
    Callback = function(val) State.killDelay = val / 1000 end,
})

KillTab:CreateButton({
    Name = "Manual Kill Closest",
    Callback = function()
        local target = getClosestEnemy()
        if target then
            silentKill(target)
            notify("Kill", "Killed "..target.player.Name, 3)
        else
            notify("Kill Bot", "No target found", 2)
        end
    end,
})

KillTab:CreateButton({
    Name = "Kill Stats",
    Callback = function()
        notify("Kill Stats", "Silent kills: "..State.kills, 3)
    end,
})

-- ============================================================
-- TAB 3 — AFK FARM
-- ============================================================
local AFKTab = Window:CreateTab("AFK Farm", 6031075938)

AFKTab:CreateToggle({
    Name = "AFK Coin Farm", CurrentValue = false, Flag = "AFKFarm",
    Callback = function(val)
        State.afkFarm = val
        -- auto enable footstep suppressor when farming
        State.suppressFootstep = val
        if val then task.spawn(afkFarmLoop) end
        notify("AFK Farm", val and "Farming — footsteps hidden" or "Stopped", 3)
    end,
})

AFKTab:CreateLabel({
    Text = "Auto follows nearest player silently. Footsteps suppressed automatically."
})

-- ============================================================
-- TAB 4 — ESP
-- ============================================================
local ESPTab = Window:CreateTab("ESP", 6031080504)

ESPTab:CreateToggle({
    Name = "Player ESP", CurrentValue = false, Flag = "ESP",
    Callback = function(val)
        State.espEnabled = val
        if val then buildESP() else clearESP() end
        notify("ESP", val and "Active" or "Off", 2)
    end,
})

ESPTab:CreateButton({
    Name = "Refresh ESP",
    Callback = function()
        if State.espEnabled then buildESP() end
        notify("ESP", "Refreshed", 2)
    end,
})

-- ============================================================
-- TAB 5 — DODGE
-- ============================================================
local DodgeTab = Window:CreateTab("Dodge", 6031068421)

DodgeTab:CreateToggle({
    Name = "Auto Dodge", CurrentValue = false, Flag = "AutoDodge",
    Callback = function(val)
        State.autoDodge = val
        notify("Dodge", val and "Active" or "Off", 2)
    end,
})

DodgeTab:CreateSlider({
    Name = "Dodge Radius (studs)", Range = {5, 40}, Increment = 1,
    CurrentValue = 15, Flag = "DodgeRadius",
    Callback = function(val) State.dodgeRadius = val end,
})

-- ============================================================
-- TAB 6 — SETTINGS
-- ============================================================
local SettingsTab = Window:CreateTab("Settings", 6031080504)

SettingsTab:CreateButton({
    Name = "Session Report",
    Callback = function()
        local msg = string.format(
            "Kills: %d | Dodges: %d\nSuppress: %s | Bot: %s\nAFK: %s | ESP: %s",
            State.kills, State.dodges,
            State.suppressReveal and "ON" or "OFF",
            State.silentKillBot  and "ON" or "OFF",
            State.afkFarm        and "ON" or "OFF",
            State.espEnabled     and "ON" or "OFF"
        )
        notify("Session", msg, 5)
        print("[Axiom]\n"..msg)
    end,
})

-- respawn
LocalPlayer.CharacterAdded:Connect(function()
    State.silentKillBot = false
    State.afkFarm       = false
    State.dodgeCooldown = false
    if State.espEnabled then
        task.wait(1)
        buildESP()
    end
    notify("Respawned", "Re-enable toggles", 2)
end)

-- players joining/leaving refresh ESP
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function()
        task.wait(1)
        if State.espEnabled then buildESP() end
    end)
end)
Players.PlayerRemoving:Connect(function(p)
    local bb = game.CoreGui:FindFirstChild("AxiomESP_"..p.Name)
    local hl = game.CoreGui:FindFirstChild("AxiomHL_"..p.Name)
    if bb then bb:Destroy() end
    if hl then hl:Destroy() end
end)

print("[AxiomHub] Silent Assassins loaded — all systems armed")
