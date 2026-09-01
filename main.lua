-- ============================================================
--  SILENT ASSASSINS — AXIOM HUB
--  ESP + Auto Dodge
-- ============================================================

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local Workspace      = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- STATE
-- ============================================================
local State = {
    espEnabled      = false,
    autoDodge       = false,
    dodgeRadius     = 20,
    espObjects      = {},
    showDistance    = true,
    showName        = true,
    showHealth      = true,
    showWeapon      = true,
    espTeamCheck    = false,
    dodgeCooldown   = false,
    totalDodges     = 0,
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

local function getWeapon(char)
    for _, obj in ipairs(char:GetChildren()) do
        if obj:IsA("Tool") then return obj.Name end
    end
    return "None"
end

local function getTeam(player)
    return player.Team and tostring(player.Team.Name) or "None"
end

local function isSameTeam(player)
    if not State.espTeamCheck then return false end
    return LocalPlayer.Team and player.Team == LocalPlayer.Team
end

-- ============================================================
-- ESP COLORS
-- ============================================================
local function getESPColor(player)
    if isSameTeam(player) then
        return Color3.fromRGB(50, 200, 50)   -- green = teammate
    end
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        local hp = hum.Health / hum.MaxHealth
        if hp > 0.6 then
            return Color3.fromRGB(255, 50, 50)   -- red = healthy enemy
        elseif hp > 0.3 then
            return Color3.fromRGB(255, 165, 0)   -- orange = damaged
        else
            return Color3.fromRGB(255, 255, 50)  -- yellow = low hp
        end
    end
    return Color3.fromRGB(255, 50, 50)
end

-- ============================================================
-- ESP BUILD
-- ============================================================
local function clearESP()
    for _, obj in ipairs(State.espObjects) do
        pcall(function() obj:Destroy() end)
    end
    State.espObjects = {}
end

local function buildPlayerESP(player)
    if player == LocalPlayer then return end
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    -- BillboardGui
    local bb = Instance.new("BillboardGui")
    bb.Name         = "AxiomESP_"..player.Name
    bb.AlwaysOnTop  = true
    bb.Size         = UDim2.new(0, 200, 0, 80)
    bb.StudsOffset  = Vector3.new(0, 3, 0)
    bb.Adornee      = hrp
    bb.Parent       = game.CoreGui

    -- Name label
    local nameL = Instance.new("TextLabel", bb)
    nameL.Name                   = "NameLabel"
    nameL.Size                   = UDim2.new(1, 0, 0.35, 0)
    nameL.BackgroundTransparency = 1
    nameL.TextColor3             = getESPColor(player)
    nameL.TextStrokeTransparency = 0
    nameL.TextStrokeColor3       = Color3.new(0, 0, 0)
    nameL.Font                   = Enum.Font.GothamBold
    nameL.TextScaled             = true
    nameL.Text                   = State.showName and player.Name or ""

    -- HP label
    local hpL = Instance.new("TextLabel", bb)
    hpL.Name                   = "HPLabel"
    hpL.Size                   = UDim2.new(1, 0, 0.3, 0)
    hpL.Position               = UDim2.new(0, 0, 0.35, 0)
    hpL.BackgroundTransparency = 1
    hpL.TextColor3             = Color3.fromRGB(100, 255, 100)
    hpL.TextStrokeTransparency = 0
    hpL.TextStrokeColor3       = Color3.new(0, 0, 0)
    hpL.Font                   = Enum.Font.Gotham
    hpL.TextScaled             = true
    hpL.Text                   = State.showHealth
        and string.format("HP: %.0f/%.0f", hum.Health, hum.MaxHealth) or ""

    -- Weapon + Distance label
    local infoL = Instance.new("TextLabel", bb)
    infoL.Name                   = "InfoLabel"
    infoL.Size                   = UDim2.new(1, 0, 0.3, 0)
    infoL.Position               = UDim2.new(0, 0, 0.65, 0)
    infoL.BackgroundTransparency = 1
    infoL.TextColor3             = Color3.fromRGB(200, 200, 255)
    infoL.TextStrokeTransparency = 0
    infoL.TextStrokeColor3       = Color3.new(0, 0, 0)
    infoL.Font                   = Enum.Font.Gotham
    infoL.TextScaled             = true
    infoL.Text                   = ""

    -- SelectionBox highlight
    local highlight = Instance.new("SelectionBox")
    highlight.Name              = "AxiomHighlight_"..player.Name
    highlight.Color3            = getESPColor(player)
    highlight.LineThickness     = 0.06
    highlight.SurfaceTransparency = 0.8
    highlight.SurfaceColor3    = getESPColor(player)
    highlight.Adornee          = char
    highlight.Parent           = game.CoreGui

    table.insert(State.espObjects, bb)
    table.insert(State.espObjects, highlight)
end

local function refreshESP()
    clearESP()
    if not State.espEnabled then return end
    for _, player in ipairs(Players:GetPlayers()) do
        pcall(function() buildPlayerESP(player) end)
    end
end

-- ============================================================
-- ESP UPDATE LOOP (Heartbeat)
-- ============================================================
RunService.Heartbeat:Connect(function()
    if not State.espEnabled then return end

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then continue end

        -- find this player's billboard
        local bb = game.CoreGui:FindFirstChild("AxiomESP_"..player.Name)
        if not bb then
            -- player joined mid-session, build their ESP
            pcall(function() buildPlayerESP(player) end)
            continue
        end

        local dist = distTo(hrp)
        local col  = getESPColor(player)
        local weapon = getWeapon(char)

        local nameL = bb:FindFirstChild("NameLabel")
        local hpL   = bb:FindFirstChild("HPLabel")
        local infoL = bb:FindFirstChild("InfoLabel")

        if nameL then
            nameL.Text       = State.showName and player.Name or ""
            nameL.TextColor3 = col
        end
        if hpL then
            hpL.Text = State.showHealth
                and string.format("HP: %.0f/%.0f", hum.Health, hum.MaxHealth) or ""
            -- color shifts red as hp drops
            local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
            hpL.TextColor3 = Color3.fromRGB(
                math.floor((1 - ratio) * 255),
                math.floor(ratio * 220),
                50
            )
        end
        if infoL then
            local parts = {}
            if State.showWeapon   then table.insert(parts, "🗡 "..weapon) end
            if State.showDistance then table.insert(parts, string.format("%.0fst", dist)) end
            infoL.Text = table.concat(parts, "  |  ")
        end

        -- update highlight color
        local hl = game.CoreGui:FindFirstChild("AxiomHighlight_"..player.Name)
        if hl then
            hl.Color3        = col
            hl.SurfaceColor3 = col
        end
    end
end)

-- clean up when players leave
Players.PlayerRemoving:Connect(function(player)
    local bb = game.CoreGui:FindFirstChild("AxiomESP_"..player.Name)
    local hl = game.CoreGui:FindFirstChild("AxiomHighlight_"..player.Name)
    if bb then bb:Destroy() end
    if hl then hl:Destroy() end
end)

-- build ESP for players who join mid-session
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        task.wait(1)
        if State.espEnabled then
            pcall(function() buildPlayerESP(player) end)
        end
    end)
end)

-- ============================================================
-- AUTO DODGE
-- logic: scan all players every heartbeat
-- if any enemy is within dodgeRadius AND moving toward us fast,
-- teleport perpendicular to their velocity to dodge
-- ============================================================
local lastPositions = {}

RunService.Heartbeat:Connect(function()
    if not State.autoDodge then return end
    if not isAlive() then return end
    if State.dodgeCooldown then return end

    local root = getRoot()
    if not root then return end

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if isSameTeam(player) then continue end

        local char = player.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        local dist = distTo(hrp)
        if dist > State.dodgeRadius then continue end

        -- track velocity toward us
        local lastPos = lastPositions[player.Name]
        lastPositions[player.Name] = hrp.Position

        if not lastPos then continue end

        local enemyVelocity = hrp.Position - lastPos
        local toUs          = root.Position - hrp.Position
        local approaching   = enemyVelocity:Dot(toUs.Unit)

        -- if enemy is moving toward us at speed > 1 stud/frame
        if approaching > 1 and dist < State.dodgeRadius then
            State.dodgeCooldown = true
            State.totalDodges   = State.totalDodges + 1

            -- calculate perpendicular dodge direction
            local right     = root.CFrame.RightVector
            local dodgeDir  = math.random(0, 1) == 0 and right or -right
            local dodgePos  = root.Position + (dodgeDir * 18) + Vector3.new(0, 0.5, 0)

            -- teleport dodge
            root.CFrame = CFrame.new(dodgePos)

            print(string.format("[Axiom] Dodged %s | total dodges: %d", player.Name, State.totalDodges))

            -- cooldown between dodges
            task.delay(0.6, function()
                State.dodgeCooldown = false
            end)
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
    LoadingSubtitle        = "ESP + Auto Dodge",
    Theme                  = "Default",
    DisableRayfieldPrompts = false,
    ConfigurationSaving    = { Enabled = false },
    Discord                = { Enabled = false },
    KeySystem              = false,
})

-- ============================================================
-- TAB 1 — ESP
-- ============================================================
local ESPTab = Window:CreateTab("ESP", 6031071057)

ESPTab:CreateToggle({
    Name = "Enable ESP", CurrentValue = false, Flag = "ESPEnabled",
    Callback = function(val)
        State.espEnabled = val
        if val then refreshESP() else clearESP() end
        notify("ESP", val and "Active" or "Off", 2)
    end,
})

ESPTab:CreateToggle({
    Name = "Show Name", CurrentValue = true, Flag = "ShowName",
    Callback = function(val) State.showName = val end,
})

ESPTab:CreateToggle({
    Name = "Show Health", CurrentValue = true, Flag = "ShowHealth",
    Callback = function(val) State.showHealth = val end,
})

ESPTab:CreateToggle({
    Name = "Show Weapon", CurrentValue = true, Flag = "ShowWeapon",
    Callback = function(val) State.showWeapon = val end,
})

ESPTab:CreateToggle({
    Name = "Show Distance", CurrentValue = true, Flag = "ShowDist",
    Callback = function(val) State.showDistance = val end,
})

ESPTab:CreateToggle({
    Name = "Team Check (skip teammates)", CurrentValue = false, Flag = "TeamCheck",
    Callback = function(val)
        State.espTeamCheck = val
        if State.espEnabled then refreshESP() end
    end,
})

ESPTab:CreateButton({
    Name = "Refresh ESP",
    Callback = function()
        refreshESP()
        notify("ESP", "Refreshed", 2)
    end,
})

ESPTab:CreateButton({
    Name = "List All Players",
    Callback = function()
        local root = getRoot()
        print("=== PLAYER LIST ===")
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local char = p.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                local dist = hrp and root and (root.Position - hrp.Position).Magnitude or -1
                print(string.format("  %s | Team:%s | HP:%.0f | %.0fst",
                    p.Name, getTeam(p),
                    hum and hum.Health or 0,
                    dist))
            end
        end
        notify("Players", #Players:GetPlayers()-1 .." enemies listed", 3)
    end,
})

-- ============================================================
-- TAB 2 — DODGE
-- ============================================================
local DodgeTab = Window:CreateTab("Auto Dodge", 6031068421)

DodgeTab:CreateToggle({
    Name = "Auto Dodge", CurrentValue = false, Flag = "AutoDodge",
    Callback = function(val)
        State.autoDodge = val
        notify("Auto Dodge", val and "Active — watching enemies" or "Off", 2)
    end,
})

DodgeTab:CreateSlider({
    Name = "Dodge Trigger Radius (studs)",
    Range = {8, 60}, Increment = 1, CurrentValue = 20,
    Flag = "DodgeRadius",
    Callback = function(val) State.dodgeRadius = val end,
})

DodgeTab:CreateButton({
    Name = "Dodge Stats",
    Callback = function()
        notify("Dodge Stats", "Total dodges: "..State.totalDodges, 3)
        print("[Axiom] Total dodges:", State.totalDodges)
    end,
})

-- ============================================================
-- TAB 3 — SETTINGS
-- ============================================================
local SettingsTab = Window:CreateTab("Settings", 6031080504)

SettingsTab:CreateButton({
    Name = "Clear All ESP",
    Callback = function()
        clearESP()
        State.espEnabled = false
        notify("ESP", "Cleared", 2)
    end,
})

SettingsTab:CreateButton({
    Name = "Session Report",
    Callback = function()
        local msg = string.format(
            "ESP:%s Dodge:%s\nTotal Dodges:%d\nPlayers in server:%d",
            State.espEnabled and "ON" or "OFF",
            State.autoDodge  and "ON" or "OFF",
            State.totalDodges,
            #Players:GetPlayers() - 1
        )
        notify("Session", msg, 5)
        print("[Axiom]\n"..msg)
    end,
})

-- ============================================================
-- RESPAWN
-- ============================================================
LocalPlayer.CharacterAdded:Connect(function()
    State.autoDodge   = false
    State.dodgeCooldown = false
    task.wait(1)
    if State.espEnabled then refreshESP() end
    notify("Respawned", "Dodge reset — re-enable", 3)
end)

print("[AxiomHub] Silent Assassins loaded — ESP + Auto Dodge active")