-- ============================================================
--  MOG OR DIE — AXIOM HUB v2.2
--  FIX: Auto Collect now teleports CFrame directly to items
--  Server detects proximity on its own heartbeat — no remote needed
-- ============================================================

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- REMOTES
-- ============================================================
local MogOrDie            = ReplicatedStorage:WaitForChild("MogOrDie", 15)
local Config              = require(MogOrDie:WaitForChild("Config"))
local CollectibleStream   = MogOrDie:WaitForChild("CollectibleStream", 10)
local WorldTravelRequest  = MogOrDie:WaitForChild("WorldTravelRequest", 10)
local ClaimPlaytimeReward = MogOrDie:WaitForChild("ClaimPlaytimeReward", 10)
local PlaytimeRewardEvent = MogOrDie:WaitForChild("PlaytimeRewardEvent", 10)
local MogBattleEvent      = MogOrDie:WaitForChild("MogBattleEvent", 10)
local PrestigeRequest     = MogOrDie:WaitForChild("PrestigeRequest", 10)

-- ============================================================
-- SORTED TYPE ARRAY
-- ============================================================
local SortedTypes = {}
for typeName in Config.Collectibles do
    table.insert(SortedTypes, typeName)
end
table.sort(SortedTypes)

-- ============================================================
-- DISTRICTS
-- ============================================================
local Districts = {
    { Id = "StarterDistrict", Name = "Starter District" },
    { Id = "Downtown",        Name = "Downtown"         },
    { Id = "MogDistrict",     Name = "Mog District"     },
    { Id = "Heaven",          Name = "Heaven"           },
    { Id = "Hell",            Name = "Hell"             },
    { Id = "Agartha",         Name = "Agartha"          },
}

-- ============================================================
-- STATE
-- ============================================================
local State = {
    autoCollect      = false,
    totalCollected   = 0,
    collectRadius    = Config.Spawning and Config.Spawning.CollectRadius or 8,
    farmDelay        = 0.15,
    priorityDiamond  = true,
    interceptedItems = {},
    autoBoss         = false,
    bossESP          = false,
    espObjects       = {},
    bossMarkers      = {},
    autoPrestige     = false,
    prestigeCount    = 0,
    autoRewards      = false,
    rewardsClaimed   = 0,
    autoTravel       = false,
    targetDistrict   = "StarterDistrict",
    battleCooldown   = false,
    cooldownEndsAt   = 0,
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
local function distTo(pos)
    local r = getRoot()
    return r and (r.Position - pos).Magnitude or math.huge
end
local function nameMatch(name, frags)
    local low = name:lower()
    for _, f in ipairs(frags) do
        if low:find(f, 1, true) then return true end
    end
    return false
end

-- ============================================================
-- STREAM INTERCEPTOR
-- ============================================================
local function installInterceptor()
    for _, conn in getconnections(CollectibleStream.OnClientEvent) do
        local old; old = hookfunction(conn.Function, function(...)
            local raw    = { ... }
            local action = raw[1]
            if action == "add" or action == "collected" then
                local p = raw[2]
                if type(p) == "table" then
                    State.interceptedItems[p[1]] = {
                        id       = p[1],
                        typeName = SortedTypes[p[2]],
                        position = Vector3.new(p[3], p[4], p[5]),
                        golden   = p[6] == 1,
                        diamond  = p[7] == 1,
                        t        = os.clock(),
                    }
                end
            elseif action == "remove" then
                State.interceptedItems[raw[2]] = nil
            elseif action == "batch" then
                local batch = raw[2]
                if type(batch) == "table" then
                    for _, items in pairs(batch) do
                        if type(items) == "table" then
                            for _, p in ipairs(items) do
                                if type(p) == "table" then
                                    State.interceptedItems[p[1]] = {
                                        id       = p[1],
                                        typeName = SortedTypes[p[2]],
                                        position = Vector3.new(p[3] or 0, p[4] or 0, p[5] or 0),
                                        golden   = p[6] == 1,
                                        diamond  = p[7] == 1,
                                        t        = os.clock(),
                                    }
                                end
                            end
                        end
                    end
                end
            end
            return old(...)
        end)
    end
    print("[Axiom] Stream interceptor installed")
end
installInterceptor()

-- ============================================================
-- AUTO COLLECT — CFrame teleport method
-- source confirmed: server checks character proximity on heartbeat
-- no remote needed — just get within CollectRadius studs
-- ============================================================
local function prioritySort(a, b)
    if State.priorityDiamond then
        if a.diamond ~= b.diamond then return a.diamond end
        if a.golden  ~= b.golden  then return a.golden  end
    end
    return distTo(a.position) < distTo(b.position)
end

local function autoCollectLoop()
    while State.autoCollect do
        if isAlive() then
            local root = getRoot()
            if root then
                -- build sorted list
                local list = {}
                for _, item in pairs(State.interceptedItems) do
                    table.insert(list, item)
                end
                table.sort(list, prioritySort)

                for _, item in ipairs(list) do
                    if not State.autoCollect then break end
                    if not isAlive() then break end

                    root = getRoot()
                    if not root then break end

                    -- teleport directly onto item
                    -- server heartbeat detects we're within CollectRadius
                    root.CFrame = CFrame.new(item.position)

                    -- wait 2 server ticks for collection to register
                    task.wait(0.1)

                    -- also fire any touch triggers on nearby ClientCollectibles parts
                    local cc = Workspace:FindFirstChild("ClientCollectibles")
                    if cc then
                        for _, child in ipairs(cc:GetChildren()) do
                            local part = child:IsA("BasePart") and child
                                or child:FindFirstChildOfClass("BasePart")
                            if part and (root.Position - part.Position).Magnitude < (State.collectRadius + 4) then
                                pcall(firetouchinterest, root, part, 0)
                                pcall(firetouchinterest, root, part, 1)
                                local prompt = child:FindFirstChildOfClass("ProximityPrompt")
                                    or child:FindFirstChild("ProximityPrompt", true)
                                if prompt then pcall(fireproximityprompt, prompt) end
                            end
                        end
                    end

                    State.totalCollected = State.totalCollected + 1
                    State.interceptedItems[item.id] = nil
                    task.wait(State.farmDelay)
                end
            end
        end
        task.wait(0.3)
    end
end

-- ============================================================
-- PRESTIGE
-- ============================================================
local function checkPrestige()
    if not PrestigeRequest then return false, 0 end
    local ok, result = pcall(function()
        return PrestigeRequest:InvokeServer("Status")
    end)
    if ok and type(result) == "table" then
        return result.Eligible == true, tonumber(result.Requirement) or 0
    end
    return false, 0
end

local function doPrestige()
    if not PrestigeRequest then return false end
    local ok, result = pcall(function()
        return PrestigeRequest:InvokeServer("Ascend")
    end)
    if ok and result then return true end
    ok, result = pcall(function() return PrestigeRequest:InvokeServer() end)
    return ok and result == true
end

local function autoPrestigeLoop()
    while State.autoPrestige do
        if checkPrestige() then
            if doPrestige() then
                State.prestigeCount = State.prestigeCount + 1
                notify("⚡ Prestiged!", "Prestige #"..State.prestigeCount, 4)
                print("[Axiom] Prestige #"..State.prestigeCount)
            end
        end
        task.wait(5)
    end
end

for _, attr in ipairs({"Face","Frame","HeightInches","BodyfatPercentage","PrestigeLevel","StatsLoaded"}) do
    LocalPlayer:GetAttributeChangedSignal(attr):Connect(function()
        if State.autoPrestige and checkPrestige() then
            if doPrestige() then
                State.prestigeCount = State.prestigeCount + 1
                notify("⚡ Prestiged!", "Prestige #"..State.prestigeCount, 4)
            end
        end
    end)
end

-- ============================================================
-- PLAYTIME REWARDS
-- ============================================================
local function claimReward(i)
    if not ClaimPlaytimeReward then return false end
    return pcall(function()
        if ClaimPlaytimeReward:IsA("RemoteFunction") then
            ClaimPlaytimeReward:InvokeServer(i)
        else
            ClaimPlaytimeReward:FireServer(i)
        end
    end)
end

local function autoRewardsLoop()
    while State.autoRewards do
        for i = 1, 8 do
            if not State.autoRewards then break end
            claimReward(i)
            task.wait(0.5)
        end
        task.wait(15)
    end
end

if PlaytimeRewardEvent then
    PlaytimeRewardEvent.OnClientEvent:Connect(function()
        if State.autoRewards then
            for i = 1, 8 do pcall(function() claimReward(i) end) end
        end
    end)
end

-- ============================================================
-- WORLD TRAVEL
-- ============================================================
local function travelToDistrict(id)
    if not WorldTravelRequest then return false end
    return pcall(function()
        if WorldTravelRequest:IsA("RemoteFunction") then
            WorldTravelRequest:InvokeServer(id)
        else
            WorldTravelRequest:FireServer(id)
        end
    end)
end

local function autoTravelLoop()
    while State.autoTravel do
        if not State.battleCooldown then
            travelToDistrict(State.targetDistrict)
        end
        task.wait(30)
    end
end

-- ============================================================
-- BATTLE COOLDOWN
-- ============================================================
if MogBattleEvent then
    MogBattleEvent.OnClientEvent:Connect(function(data)
        if type(data) == "table" and data.Phase == "BattleCooldown" then
            local remaining = tonumber(data.Remaining) or 0
            State.battleCooldown = remaining > 0
            State.cooldownEndsAt = tonumber(data.EndsAt)
                or (Workspace:GetServerTimeNow() + remaining)
            if remaining > 0 then
                task.delay(remaining + 0.5, function()
                    State.battleCooldown = false
                end)
            end
        end
    end)
end

-- ============================================================
-- BOSS
-- ============================================================
local BOSS_FRAGS = {"boss","mogking","king","elite","alpha","giant","champion","titan","mogger"}

local function scanBosses()
    local found, root = {}, getRoot()
    if not root then return found end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj ~= LocalPlayer.Character then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            local hrp = obj:FindFirstChild("HumanoidRootPart")
            if hum and hrp and nameMatch(obj.Name, BOSS_FRAGS) then
                table.insert(found, {
                    model=obj, hrp=hrp, humanoid=hum, name=obj.Name,
                    position=hrp.Position,
                    distance=(root.Position - hrp.Position).Magnitude,
                    health=hum.Health, maxHealth=hum.MaxHealth,
                })
            end
        end
    end
    table.sort(found, function(a,b) return a.distance < b.distance end)
    return found
end

local function clearESP()
    for _, obj in ipairs(State.espObjects) do pcall(function() obj:Destroy() end) end
    State.espObjects  = {}
    State.bossMarkers = {}
end

local function buildESP(bosses)
    clearESP()
    for _, boss in ipairs(bosses) do
        local bb = Instance.new("BillboardGui")
        bb.AlwaysOnTop=true; bb.Size=UDim2.new(0,220,0,65)
        bb.StudsOffset=Vector3.new(0,5,0); bb.Adornee=boss.hrp; bb.Parent=game.CoreGui
        local nL = Instance.new("TextLabel",bb)
        nL.Size=UDim2.new(1,0,0.5,0); nL.BackgroundTransparency=1
        nL.TextColor3=Color3.fromRGB(255,220,50); nL.TextStrokeTransparency=0
        nL.Font=Enum.Font.GothamBold; nL.TextScaled=true; nL.Text="⚠ "..boss.name
        local hL = Instance.new("TextLabel",bb)
        hL.Size=UDim2.new(1,0,0.5,0); hL.Position=UDim2.new(0,0,0.5,0)
        hL.BackgroundTransparency=1; hL.TextColor3=Color3.fromRGB(100,255,100)
        hL.TextStrokeTransparency=0; hL.Font=Enum.Font.Gotham; hL.TextScaled=true
        hL.Text=string.format("HP %.0f/%.0f | %.0fst",boss.health,boss.maxHealth,boss.distance)
        local sel = Instance.new("SelectionBox")
        sel.Color3=Color3.fromRGB(255,50,50); sel.LineThickness=0.07
        sel.SurfaceTransparency=0.75; sel.SurfaceColor3=Color3.fromRGB(255,50,50)
        sel.Adornee=boss.model; sel.Parent=game.CoreGui
        table.insert(State.espObjects, bb)
        table.insert(State.espObjects, sel)
        table.insert(State.bossMarkers, {boss=boss, hpLabel=hL})
    end
end

RunService.Heartbeat:Connect(function()
    if not State.bossESP then return end
    for _, e in ipairs(State.bossMarkers) do
        local b = e.boss
        if b.humanoid and b.hrp then
            e.hpLabel.Text = string.format("HP %.0f/%.0f | %.0fst",
                b.humanoid.Health, b.humanoid.MaxHealth, distTo(b.hrp.Position))
        end
    end
end)

local function autoBossLoop()
    while State.autoBoss do
        if isAlive() and not State.battleCooldown then
            local bosses = scanBosses()
            if #bosses > 0 then
                local target = bosses[1]
                local root   = getRoot()
                while State.autoBoss and isAlive() and target.humanoid.Health > 0 do
                    if distTo(target.hrp.Position) > 8 then
                        local hum = getHum()
                        if hum then hum:MoveTo(target.hrp.Position) end
                    else
                        pcall(firetouchinterest, root, target.hrp, 0)
                        pcall(firetouchinterest, root, target.hrp, 1)
                        local prompt = target.model:FindFirstChildOfClass("ProximityPrompt")
                            or target.model:FindFirstChild("ProximityPrompt", true)
                        if prompt then pcall(fireproximityprompt, prompt) end
                        local cd = target.model:FindFirstChildOfClass("ClickDetector")
                            or target.model:FindFirstChild("ClickDetector", true)
                        if cd then pcall(fireclickdetector, cd) end
                        task.wait(1)
                    end
                    task.wait(0.05)
                end
            end
        end
        task.wait(1)
    end
end

-- ============================================================
-- RAYFIELD WINDOW
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name                   = "Axiom Hub  |  Mog or Die",
    LoadingTitle           = "Axiom Hub",
    LoadingSubtitle        = "v2.2 — Collect Fixed",
    Theme                  = "Default",
    DisableRayfieldPrompts = false,
    ConfigurationSaving    = { Enabled = false },
    Discord                = { Enabled = false },
    KeySystem              = false,
})

-- TAB 1 — COLLECT
local CollectTab = Window:CreateTab("Collect", 6031071057)

CollectTab:CreateToggle({
    Name = "Auto Collect", CurrentValue = false, Flag = "AutoCollect",
    Callback = function(val)
        State.autoCollect = val
        if val then task.spawn(autoCollectLoop) end
        notify("Auto Collect", val and "Teleporting to items" or "Stopped", 2)
    end,
})

CollectTab:CreateToggle({
    Name = "Priority Diamond > Golden", CurrentValue = true, Flag = "PriorityDiamond",
    Callback = function(val) State.priorityDiamond = val end,
})

CollectTab:CreateSlider({
    Name = "Farm Delay (ms)", Range = {50, 800}, Increment = 10,
    CurrentValue = 150, Flag = "FarmDelay",
    Callback = function(val) State.farmDelay = val / 1000 end,
})

CollectTab:CreateButton({
    Name = "Dump Tracked Items",
    Callback = function()
        local count = 0
        for _, item in pairs(State.interceptedItems) do
            count = count + 1
            print(string.format("[Axiom] %s | %s | gold=%s dia=%s | pos=(%.1f,%.1f,%.1f)",
                tostring(item.id), tostring(item.typeName),
                tostring(item.golden), tostring(item.diamond),
                item.position.X, item.position.Y, item.position.Z))
        end
        notify("Item Dump", count.." items logged", 3)
    end,
})

CollectTab:CreateButton({
    Name = "Reinstall Stream Hook",
    Callback = function()
        installInterceptor()
        notify("Hook", "Reinstalled", 2)
    end,
})

-- TAB 2 — PRESTIGE
local PrestigeTab = Window:CreateTab("Prestige", 6031075938)

PrestigeTab:CreateToggle({
    Name = "Auto Prestige", CurrentValue = false, Flag = "AutoPrestige",
    Callback = function(val)
        State.autoPrestige = val
        if val then task.spawn(autoPrestigeLoop) end
        notify("Auto Prestige", val and "Watching" or "Stopped", 2)
    end,
})

PrestigeTab:CreateButton({
    Name = "Check Status",
    Callback = function()
        local eligible, progress = checkPrestige()
        local p = LocalPlayer
        local msg = string.format(
            "Eligible:%s Progress:%.0f%%\nFace:%.1f Frame:%.1f\nHeight:%.1f BF:%.1f",
            tostring(eligible), progress * 100,
            tonumber(p:GetAttribute("Face"))              or 0,
            tonumber(p:GetAttribute("Frame"))             or 0,
            tonumber(p:GetAttribute("HeightInches"))      or 0,
            tonumber(p:GetAttribute("BodyfatPercentage")) or 100
        )
        print("[Axiom Prestige]\n"..msg)
        notify("Prestige", msg, 6)
    end,
})

PrestigeTab:CreateButton({
    Name = "Force Prestige Now",
    Callback = function()
        if checkPrestige() then
            if doPrestige() then
                State.prestigeCount = State.prestigeCount + 1
                notify("Prestiged!", "#"..State.prestigeCount, 4)
            else
                notify("Prestige", "Server rejected", 3)
            end
        else
            notify("Prestige", "Not eligible", 3)
        end
    end,
})

-- TAB 3 — BOSS
local BossTab = Window:CreateTab("Boss", 6031068421)

BossTab:CreateToggle({
    Name = "Boss ESP", CurrentValue = false, Flag = "BossESP",
    Callback = function(val)
        State.bossESP = val
        if val then buildESP(scanBosses()) else clearESP() end
    end,
})

BossTab:CreateToggle({
    Name = "Auto Boss Fight", CurrentValue = false, Flag = "AutoBoss",
    Callback = function(val)
        State.autoBoss = val
        if val then task.spawn(autoBossLoop) end
        notify("Auto Boss", val and "Hunting" or "Stopped", 2)
    end,
})

BossTab:CreateButton({
    Name = "Scan Bosses Now",
    Callback = function()
        local bosses = scanBosses()
        if State.bossESP then buildESP(bosses) end
        for i,b in ipairs(bosses) do
            print(string.format("[Axiom] Boss[%d] %s | %.0fHP | %.1fst",
                i, b.name, b.health, b.distance))
        end
        notify("Boss Scan", #bosses.." found", 3)
    end,
})

BossTab:CreateButton({
    Name = "Clear ESP",
    Callback = function()
        clearESP(); State.bossESP = false
        notify("ESP", "Cleared", 2)
    end,
})

-- TAB 4 — TRAVEL
local TravelTab = Window:CreateTab("Travel", 6031080504)

local districtNames = {}
for _, d in ipairs(Districts) do table.insert(districtNames, d.Name) end

TravelTab:CreateDropdown({
    Name = "Target District", Options = districtNames,
    CurrentOption = "Starter District", Flag = "TargetDistrict",
    Callback = function(val)
        for _, d in ipairs(Districts) do
            if d.Name == val then State.targetDistrict = d.Id break end
        end
    end,
})

TravelTab:CreateButton({
    Name = "Travel Now",
    Callback = function()
        local ok = travelToDistrict(State.targetDistrict)
        notify("Travel", ok and ("→ "..State.targetDistrict) or "Failed", 3)
    end,
})

TravelTab:CreateToggle({
    Name = "Auto Travel", CurrentValue = false, Flag = "AutoTravel",
    Callback = function(val)
        State.autoTravel = val
        if val then task.spawn(autoTravelLoop) end
        notify("Auto Travel", val and "Active" or "Stopped", 2)
    end,
})

-- TAB 5 — REWARDS
local RewardsTab = Window:CreateTab("Rewards", 6031071057)

RewardsTab:CreateToggle({
    Name = "Auto Claim Rewards", CurrentValue = false, Flag = "AutoRewards",
    Callback = function(val)
        State.autoRewards = val
        if val then task.spawn(autoRewardsLoop) end
        notify("Auto Rewards", val and "Claiming" or "Stopped", 2)
    end,
})

RewardsTab:CreateButton({
    Name = "Claim All Now",
    Callback = function()
        local claimed = 0
        for i = 1, 8 do
            if claimReward(i) then claimed = claimed + 1 end
            task.wait(0.3)
        end
        State.rewardsClaimed = State.rewardsClaimed + claimed
        notify("Rewards", claimed.." claimed", 3)
    end,
})

-- TAB 6 — SETTINGS
local SettingsTab = Window:CreateTab("Settings", 6031080504)

SettingsTab:CreateButton({
    Name = "Session Report",
    Callback = function()
        local tracked = 0
        for _ in pairs(State.interceptedItems) do tracked = tracked + 1 end
        local msg = string.format(
            "Collected:%d Tracked:%d\nPrestige:%d Rewards:%d\nFarm:%s Boss:%s",
            State.totalCollected, tracked,
            State.prestigeCount, State.rewardsClaimed,
            State.autoCollect and "ON" or "OFF",
            State.autoBoss    and "ON" or "OFF"
        )
        print("[Axiom]\n"..msg)
        notify("Session", msg, 6)
    end,
})

SettingsTab:CreateButton({
    Name = "Cooldown Status",
    Callback = function()
        local rem = math.max(State.cooldownEndsAt - Workspace:GetServerTimeNow(), 0)
        notify("Cooldown",
            State.battleCooldown and string.format("%.1fs left", rem) or "Clear",
            3)
    end,
})

-- ============================================================
-- RESPAWN
-- ============================================================
LocalPlayer.CharacterAdded:Connect(function()
    State.autoCollect = false
    State.autoBoss    = false
    clearESP()
    notify("Respawned", "Re-enable toggles", 3)
end)

print("[AxiomHub v2.2] Loaded — CFrame collect active")