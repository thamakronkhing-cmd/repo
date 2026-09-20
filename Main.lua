-- =================================================================
-- กูต้นดิว่ะ v9.5 (Rainbow ESP, Multi-Waypoint, Wall Check, Resizable)
-- =================================================================
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

-- แทนที่ SavedPosition เดิม
local SavedWaypoints = {}  -- { [ชื่อจุด] = CFrame }

-- ==================== SYSTEM CONFIGURATION ====================
local Settings = {
    Aimbot = {
        Enabled = false,
        TargetPart = "Head", 
        TargetBots = false,
        ClosestToPlayer = false,
        FOV = 150,
        ShowFOV = false,
        TeamCheck = false,
        ThroughWalls = false   -- false = ล็อคเฉพาะเป้าที่มองเห็น, true = ล็อคหลังกำแพงได้
    },
    ESP = {
        Enabled = false,
        Boxes = true,
        Tracers = true,
        Names = true,
        Health = true,
        TeamCheck = false,
        TeamColor = Color3.fromRGB(255, 255, 255),
        BotESP = false,
        XRay = false,
        Fullbright = false,
        BrightnessLevel = 2,
        ClockTimeLevel = 14,
        FPSBoost = false,
        RainbowHighlight = false   -- เพิ่มออร่ารุ้งรอบตัวผู้เล่น
    },
    Defense = {
        AntiDamage = false,
        GodMode = false,
        AutoHeal = false
    },
    Player = {
        WalkSpeed = 16,
        JumpPower = 50,
        FlySpeed = 1,
        Flying = false,
        Noclip = false,
        InfJump = false,
        Invisible = false,
        ClickDelete = false,
        CtrlClickTP = false,
        AutoLoot = false,
        AutoLootRadius = 20
    },
    Item = {
        TeleportToolActive = false,
        SpeedToolActive = false,
        KillAuraToolActive = false,
        BlinkToolActive = false,
        MorphToolActive = false
    }
}

-- ==================== FOV CIRCLE SETUP ====================
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 2
FOVCircle.Color = Color3.fromRGB(255, 255, 255)
FOVCircle.Filled = false
FOVCircle.Transparency = 0.9
FOVCircle.Visible = false

local FOVRainbowActive = true
task.spawn(function()
    local hue = 0
    while FOVRainbowActive do
        hue = (hue + 0.01) % 1
        FOVCircle.Color = Color3.fromHSV(hue, 1, 1)
        task.wait(0.03)
    end
end)

-- ==================== INTERNAL CHEATS IMPLEMENTATION ====================
local noclipConn, infJumpConn, flyConn, clickDelConn, ctrlClickConn, autoHealConn

-- Lighting System
local Lighting = game:GetService("Lighting")
local originalBrightness = Lighting.Brightness
local originalClockTime = Lighting.ClockTime
local originalGlobalShadows = Lighting.GlobalShadows

local function SetFullbright(state)
    if state then
        Lighting.Brightness = Settings.ESP.BrightnessLevel
        Lighting.ClockTime = Settings.ESP.ClockTimeLevel
        Lighting.GlobalShadows = false
    else
        Lighting.Brightness = originalBrightness
        Lighting.ClockTime = originalClockTime
        Lighting.GlobalShadows = originalGlobalShadows
    end
end

-- Auto Heal / God HP System
autoHealConn = RunService.RenderStepped:Connect(function()
    if Settings.Defense.AutoHeal and LocalPlayer.Character then
        local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
            humanoid.Health = humanoid.MaxHealth
        end
    end
end)

-- ==================== MORPH FUNCTION ====================
local function MorphToPlayer(targetPlayer)
    -- (ไม่มีการเปลี่ยนแปลง)
    local myChar = LocalPlayer.Character
    local targetChar = targetPlayer and targetPlayer.Character
    if not myChar or not targetChar then return end

    local myHumanoidDesc = myChar:FindFirstChildOfClass("Humanoid") and myChar:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("HumanoidDescription")
    local targetHumanoidDesc = targetChar:FindFirstChildOfClass("Humanoid") and targetChar:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("HumanoidDescription")

    if targetHumanoidDesc and myChar:FindFirstChildOfClass("Humanoid") then
        local hum = myChar:FindFirstChildOfClass("Humanoid")
        local success = pcall(function()
            hum:ApplyDescriptionReset(targetHumanoidDesc)
        end)
        if success then return end
    end

    for _, item in pairs(myChar:GetChildren()) do
        if item:IsA("Accessory") or item:IsA("Clothing") or item:IsA("ShirtGraphic") or item:IsA("CharacterMesh") then
            item:Destroy()
        end
    end

    for _, item in pairs(targetChar:GetChildren()) do
        if item:IsA("Accessory") or item:IsA("Clothing") or item:IsA("ShirtGraphic") or item:IsA("CharacterMesh") then
            local cloned = item:Clone()
            cloned.Parent = myChar
        end
    end

    local myHead = myChar:FindFirstChild("Head")
    local targetHead = targetChar:FindFirstChild("Head")
    if myHead and targetHead then
        for _, mesh in pairs(targetHead:GetChildren()) do
            if mesh:IsA("SpecialMesh") or mesh:IsA("DataModelMesh") then
                local existing = myHead:FindFirstChildOfClass("SpecialMesh")
                if existing then existing:Destroy() end
                mesh:Clone().Parent = myHead
            end
        end
    end
end

-- ==================== CUSTOM ITEMS SYSTEM ====================
-- (ไม่มีการเปลี่ยนแปลง)
local tpTool, speedTool, killAuraTool, blinkTool, morphTool
local tpConn, speedConn, killConn, blinkConn, morphConn

-- 1. คทาวาร์ป
local function ToggleTeleportTool(state)
    Settings.Item.TeleportToolActive = state
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    
    if state then
        if not tpTool then
            tpTool = Instance.new("Tool")
            tpTool.Name = "⚡ [Item] คทาวาร์ปล่องหน"
            tpTool.RequiresHandle = true
            tpTool.CanBeDropped = false

            local handle = Instance.new("Part", tpTool)
            handle.Name = "Handle"
            handle.Size = Vector3.new(0.1, 0.1, 0.1)
            handle.Transparency = 1
            handle.CanCollide = false
            handle.Massless = true

            tpConn = tpTool.Activated:Connect(function()
                if Mouse.Hit and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(Mouse.Hit.Position + Vector3.new(0, 3, 0))
                end
            end)
        end
        if backpack and not tpTool.Parent then
            tpTool.Parent = backpack
        end
    else
        if tpTool then tpTool.Parent = nil end
    end
end

-- 2. รองเท้าพุ่งความเร็ว
local function ToggleSpeedTool(state)
    Settings.Item.SpeedToolActive = state
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    
    if state then
        if not speedTool then
            speedTool = Instance.new("Tool")
            speedTool.Name = "👟 [Item] รองเท้าบูทความเร็ว"
            speedTool.RequiresHandle = true
            speedTool.CanBeDropped = false

            local handle = Instance.new("Part", speedTool)
            handle.Name = "Handle"
            handle.Size = Vector3.new(0.1, 0.1, 0.1)
            handle.Transparency = 1
            handle.CanCollide = false
            handle.Massless = true

            speedConn = speedTool.Activated:Connect(function()
                local char = LocalPlayer.Character
                if char and char:FindFirstChild("HumanoidRootPart") then
                    char.HumanoidRootPart.CFrame = char.HumanoidRootPart.CFrame + (char.HumanoidRootPart.CFrame.LookVector * 15)
                end
            end)
        end
        if backpack and not speedTool.Parent then
            speedTool.Parent = backpack
        end
    else
        if speedTool then speedTool.Parent = nil end
    end
end

-- 3. มีดออร่าสังหาร
local function ToggleKillAuraTool(state)
    Settings.Item.KillAuraToolActive = state
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    
    if state then
        if not killAuraTool then
            killAuraTool = Instance.new("Tool")
            killAuraTool.Name = "🗡️ [Item] มีดออร่าสังหาร"
            killAuraTool.RequiresHandle = true
            killAuraTool.CanBeDropped = false

            local handle = Instance.new("Part", killAuraTool)
            handle.Name = "Handle"
            handle.Size = Vector3.new(0.1, 0.1, 0.1)
            handle.Transparency = 1
            handle.CanCollide = false
            handle.Massless = true

            killConn = killAuraTool.Activated:Connect(function()
                local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not myHRP then return end
                for _, p in pairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                        local hrp = p.Character.HumanoidRootPart
                        if (hrp.Position - myHRP.Position).Magnitude <= 12 then
                            local hum = p.Character:FindFirstChildOfClass("Humanoid")
                            if hum then hum.Health = 0 end
                        end
                    end
                end
            end)
        end
        if backpack and not killAuraTool.Parent then
            killAuraTool.Parent = backpack
        end
    else
        if killAuraTool then killAuraTool.Parent = nil end
    end
end

-- 4. คทาลบเป้าหมายฉับพลัน
local function ToggleBlinkTool(state)
    Settings.Item.BlinkToolActive = state
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    
    if state then
        if not blinkTool then
            blinkTool = Instance.new("Tool")
            blinkTool.Name = "💥 [Item] คทาลบเป้าหมายฉับพลัน"
            blinkTool.RequiresHandle = true
            blinkTool.CanBeDropped = false

            local handle = Instance.new("Part", blinkTool)
            handle.Name = "Handle"
            handle.Size = Vector3.new(0.1, 0.1, 0.1)
            handle.Transparency = 1
            handle.CanCollide = false
            handle.Massless = true

            blinkConn = blinkTool.Activated:Connect(function()
                if Mouse.Target then
                    Mouse.Target:Destroy()
                end
            end)
        end
        if backpack and not blinkTool.Parent then
            blinkTool.Parent = backpack
        end
    else
        if blinkTool then blinkTool.Parent = nil end
    end
end

-- 5. คทาก๊อปปี้ร่างคนอื่น
local function ToggleMorphTool(state)
    Settings.Item.MorphToolActive = state
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    
    if state then
        if not morphTool then
            morphTool = Instance.new("Tool")
            morphTool.Name = "🎭 [Item] คทาก๊อปปี้ร่างแปลง"
            morphTool.RequiresHandle = true
            morphTool.CanBeDropped = false

            local handle = Instance.new("Part", morphTool)
            handle.Name = "Handle"
            handle.Size = Vector3.new(0.1, 0.1, 0.1)
            handle.Transparency = 1
            handle.CanCollide = false
            handle.Massless = true

            morphConn = morphTool.Activated:Connect(function()
                if Mouse.Target and Mouse.Target.Parent then
                    local targetChar = Mouse.Target.Parent
                    local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
                    if targetPlayer and targetPlayer ~= LocalPlayer then
                        MorphToPlayer(targetPlayer)
                    end
                end
            end)
        end
        if backpack and not morphTool.Parent then
            morphTool.Parent = backpack
        end
    else
        if morphTool then morphTool.Parent = nil end
    end
end

-- Fly System (Q = Down, E = Up, W/A/S/D = Direction)
local flyBodyGyro, flyBodyVelocity
local function ToggleFly(state)
    Settings.Player.Flying = state
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    local hrp = char.HumanoidRootPart
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    
    if state then
        flyBodyGyro = Instance.new("BodyGyro", hrp)
        flyBodyGyro.P = 9e4
        flyBodyGyro.MaxTorque = Vector3.new(9e4, 9e4, 9e4)
        
        flyBodyVelocity = Instance.new("BodyVelocity", hrp)
        flyBodyVelocity.Velocity = Vector3.new(0, 0, 0)
        flyBodyVelocity.MaxForce = Vector3.new(9e4, 9e4, 9e4)
        
        if humanoid then humanoid.PlatformStand = true end
        
        flyConn = RunService.RenderStepped:Connect(function()
            if not Settings.Player.Flying or not hrp.Parent then 
                if flyBodyGyro then flyBodyGyro:Destroy() end
                if flyBodyVelocity then flyBodyVelocity:Destroy() end
                if humanoid then humanoid.PlatformStand = false end
                if flyConn then flyConn:Disconnect() end
                return 
            end
            
            local camCF = Camera.CFrame
            local moveDir = Vector3.new(0,0,0)
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.E) then moveDir = moveDir + Vector3.new(0,1,0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.Q) then moveDir = moveDir - Vector3.new(0,1,0) end
            
            flyBodyVelocity.Velocity = moveDir * (Settings.Player.FlySpeed * 50)
            flyBodyGyro.CFrame = camCF
        end)
    else
        if flyBodyGyro then flyBodyGyro:Destroy() end
        if flyBodyVelocity then flyBodyVelocity:Destroy() end
        if humanoid then humanoid.PlatformStand = false end
        if flyConn then flyConn:Disconnect() end
    end
end

-- Noclip System
noclipConn = RunService.Stepped:Connect(function()
    if Settings.Player.Noclip and LocalPlayer.Character then
        for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end
end)

-- Infinite Jump
infJumpConn = UserInputService.JumpRequest:Connect(function()
    if Settings.Player.InfJump and LocalPlayer.Character then
        local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- Click to Delete
clickDelConn = Mouse.Button1Down:Connect(function()
    if Settings.Player.ClickDelete and Mouse.Target then
        Mouse.Target:Destroy()
    end
end)

-- Ctrl + Click TP
ctrlClickConn = Mouse.Button1Down:Connect(function()
    if Settings.Player.CtrlClickTP and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        if Mouse.Hit and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(Mouse.Hit.Position + Vector3.new(0, 3, 0))
        end
    end
end)

-- Invisible
local function ToggleInvisible(state)
    Settings.Player.Invisible = state
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in pairs(char:GetDescendants()) do
        if part:IsA("BasePart") or part:IsA("Decal") then
            part.Transparency = state and 1 or (part.Name == "HumanoidRootPart" and 1 or 0)
        end
    end
end

-- X-Ray Map System
local xrayParts = {}
local function ToggleXRay(state)
    Settings.ESP.XRay = state
    if state then
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and not obj.Parent:FindFirstChildOfClass("Humanoid") and obj ~= LocalPlayer.Character then
                if obj.Transparency < 0.5 then
                    xrayParts[obj] = obj.Transparency
                    obj.Transparency = 0.65
                end
            end
        end
    else
        for obj, originalTrans in pairs(xrayParts) do
            if obj and obj.Parent then
                obj.Transparency = originalTrans
            end
        end
        xrayParts = {}
    end
end

-- ==================== FPS BOOST & TEXTURE REMOVE ====================
local boostedObjects = {}
local function ToggleFPSBoost(state)
    Settings.ESP.FPSBoost = state
    if state then
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("Texture") or obj:IsA("Decal") or obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
                table.insert(boostedObjects, {Obj = obj, Parent = obj.Parent})
                obj.Parent = nil
            elseif obj:IsA("BasePart") then
                if obj.Material ~= Enum.Material.SmoothPlastic then
                    table.insert(boostedObjects, {Part = obj, Material = obj.Material})
                    obj.Material = Enum.Material.SmoothPlastic
                end
            end
        end
    else
        for _, data in pairs(boostedObjects) do
            if data.Obj and data.Parent then
                data.Obj.Parent = data.Parent
            elseif data.Part and data.Material then
                data.Part.Material = data.Material
            end
        end
        boostedObjects = {}
    end
end

-- ==================== FULL RESET SYSTEM ====================
local function ResetAllScriptsAndStates()
    Settings.Aimbot.Enabled = false
    Settings.Aimbot.ShowFOV = false
    Settings.Aimbot.ThroughWalls = false
    Settings.ESP.Enabled = false
    Settings.ESP.BotESP = false
    Settings.ESP.RainbowHighlight = false
    Settings.Defense.GodMode = false
    Settings.Defense.AutoHeal = false
    Settings.Player.Flying = false
    Settings.Player.Noclip = false
    Settings.Player.InfJump = false
    Settings.Player.Invisible = false
    Settings.Player.ClickDelete = false
    Settings.Player.CtrlClickTP = false
    Settings.ESP.Fullbright = false
    Settings.ESP.FPSBoost = false

    SetFullbright(false)
    ToggleXRay(false)
    ToggleFPSBoost(false)

    if tpTool then tpTool:Destroy(); tpTool = nil end
    if speedTool then speedTool:Destroy(); speedTool = nil end
    if killAuraTool then killAuraTool:Destroy(); killAuraTool = nil end
    if blinkTool then blinkTool:Destroy(); blinkTool = nil end
    if morphTool then morphTool:Destroy(); morphTool = nil end

    if flyConn then flyConn:Disconnect() end
    if flyBodyGyro then flyBodyGyro:Destroy() end
    if flyBodyVelocity then flyBodyVelocity:Destroy() end

    LocalPlayer:LoadCharacter()
end

-- ==================== SERVER HOPS (FIXED) ====================
local function GetServerList()
    local success, data = pcall(function()
        return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
    end)
    if success and data and data.data then
        return data.data
    end
    return {}
end

local function ServerHop()
    local servers = GetServerList()
    local available = {}
    for _, s in pairs(servers) do
        if type(s) == "table" and s.playing < s.maxPlayers and s.id ~= game.JobId then
            table.insert(available, s.id)
        end
    end
    if #available > 0 then
        TeleportService:TeleportToPlaceInstance(game.PlaceId, available[math.random(1, #available)], LocalPlayer)
    end
end

local function LowServer()
    local servers = GetServerList()
    local lowest = nil
    for _, s in pairs(servers) do
        if type(s) == "table" and s.playing < s.maxPlayers and s.id ~= game.JobId then
            if not lowest or s.playing < lowest.playing then
                lowest = s
            end
        end
    end
    if lowest then
        TeleportService:TeleportToPlaceInstance(game.PlaceId, lowest.id, LocalPlayer)
    end
end

local function IsEnemy(player)
    if not Settings.Aimbot.TeamCheck then return true end
    if player.Team ~= nil and LocalPlayer.Team ~= nil then
        return player.Team ~= LocalPlayer.Team
    end
    return true
end

-- ==================== AIMBOT VISIBILITY CHECK ====================
local function IsTargetVisible(targetPart)
    if Settings.Aimbot.ThroughWalls then return true end  -- ถ้าเปิดล็อคหลังกำแพง ก็ไม่ต้องเช็ค
    local myChar = LocalPlayer.Character
    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin
    local distance = direction.Magnitude
    if distance <= 0.5 then return true end
    direction = direction / distance * (distance - 0.5) -- ลดระยะเล็กน้อยกันยิงหัวตัวเอง

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    if myChar then
        raycastParams.FilterDescendantsInstances = {myChar}
    end

    local result = workspace:Raycast(origin, direction, raycastParams)
    if result then
        local targetChar = targetPart:FindFirstAncestorOfClass("Model")
        if targetChar and result.Instance:IsDescendantOf(targetChar) then
            return true -- ชนเป้าหมายเอง
        else
            return false -- มีสิ่งกีดขวาง
        end
    end
    return true -- ไม่ชนอะไร = มองเห็น
end

-- ==================== MAIN LOOP (AIMBOT & FOV) ====================
RunService.RenderStepped:Connect(function()
    local mousePos = UserInputService:GetMouseLocation()
    FOVCircle.Position = Vector2.new(mousePos.X, mousePos.Y)
    FOVCircle.Radius = Settings.Aimbot.FOV
    FOVCircle.Visible = Settings.Aimbot.ShowFOV

    if Settings.Aimbot.Enabled then
        local ClosestTarget = nil
        local targetPartName = Settings.Aimbot.TargetPart
        local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

        if Settings.Aimbot.ClosestToPlayer and myHRP then
            local shortestDist = math.huge
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character and IsEnemy(player) then
                    local char = player.Character
                    local humanoid = char:FindFirstChildOfClass("Humanoid")
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    if humanoid and humanoid.Health > 0 and hrp then
                        local dist = (hrp.Position - myHRP.Position).Magnitude
                        if dist < shortestDist then
                            local targetPart = nil
                            if targetPartName == "Both" then
                                local head = char:FindFirstChild("Head")
                                targetPart = head or hrp
                            else
                                targetPart = char:FindFirstChild(targetPartName) or hrp
                            end
                            if targetPart and IsTargetVisible(targetPart) then
                                shortestDist = dist
                                ClosestTarget = targetPart
                            end
                        end
                    end
                end
            end
            if Settings.Aimbot.TargetBots then
                for _, obj in pairs(workspace:GetDescendants()) do
                    if obj:IsA("Model") and obj ~= LocalPlayer.Character then
                        local humanoid = obj:FindFirstChildOfClass("Humanoid")
                        local hrp = obj:FindFirstChild("HumanoidRootPart")
                        if humanoid and humanoid.Health > 0 and hrp and not Players:GetPlayerFromCharacter(obj) then
                            local dist = (hrp.Position - myHRP.Position).Magnitude
                            if dist < shortestDist then
                                local targetPart = obj:FindFirstChild(targetPartName) or hrp
                                if IsTargetVisible(targetPart) then
                                    shortestDist = dist
                                    ClosestTarget = targetPart
                                end
                            end
                        end
                    end
                end
            end
        else
            local ShortestDistance = Settings.Aimbot.FOV
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character and IsEnemy(player) then
                    local char = player.Character
                    local humanoid = char:FindFirstChildOfClass("Humanoid")
                    if humanoid and humanoid.Health > 0 then
                        local partToLock = nil
                        if targetPartName == "Both" then
                            local head = char:FindFirstChild("Head")
                            local hrp = char:FindFirstChild("HumanoidRootPart")
                            if head and hrp then
                                local hDist = (Camera:WorldToViewportPoint(head.Position) - Vector2.new(mousePos.X, mousePos.Y)).Magnitude
                                local rDist = (Camera:WorldToViewportPoint(hrp.Position) - Vector2.new(mousePos.X, mousePos.Y)).Magnitude
                                partToLock = (hDist < rDist) and head or hrp
                            end
                        else
                            partToLock = char:FindFirstChild(targetPartName)
                        end
                        if partToLock and IsTargetVisible(partToLock) then
                            local pos, onScreen = Camera:WorldToViewportPoint(partToLock.Position)
                            if onScreen then
                                local distance = (Vector2.new(pos.X, pos.Y) - Vector2.new(mousePos.X, mousePos.Y)).Magnitude
                                if distance < ShortestDistance then
                                    ShortestDistance = distance
                                    ClosestTarget = partToLock
                                end
                            end
                        end
                    end
                end
            end
            if Settings.Aimbot.TargetBots then
                for _, obj in pairs(workspace:GetDescendants()) do
                    if obj:IsA("Model") and obj ~= LocalPlayer.Character then
                        local humanoid = obj:FindFirstChildOfClass("Humanoid")
                        if humanoid and humanoid.Health > 0 and not Players:GetPlayerFromCharacter(obj) then
                            local partToLock = obj:FindFirstChild(targetPartName)
                            if partToLock and IsTargetVisible(partToLock) then
                                local pos, onScreen = Camera:WorldToViewportPoint(partToLock.Position)
                                if onScreen then
                                    local distance = (Vector2.new(pos.X, pos.Y) - Vector2.new(mousePos.X, mousePos.Y)).Magnitude
                                    if distance < ShortestDistance then
                                        ShortestDistance = distance
                                        ClosestTarget = partToLock
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if ClosestTarget then
            Camera.CFrame = CFrame.new(Camera.CFrame.Position, ClosestTarget.Position)
        end
    end
end)

-- ==================== ESP SYSTEM ====================
local ESPObjects = {}
local BotESPObjects = {}

-- เพิ่มตารางเก็บ Highlight ออร่ารุ้ง
local ESP_Highlights = {}

local function CreateESP(player)
    local box = Drawing.new("Square")
    box.Thickness = 1.5
    box.Filled = false
    box.Visible = false

    local tracer = Drawing.new("Line")
    tracer.Thickness = 1.5
    tracer.Visible = false

    local nameText = Drawing.new("Text")
    nameText.Size = 14
    nameText.Center = true
    nameText.Outline = true
    nameText.Visible = false

    local healthText = Drawing.new("Text")
    healthText.Size = 12
    healthText.Center = true
    healthText.Outline = true
    healthText.Visible = false

    ESPObjects[player] = {Box = box, Tracer = tracer, Name = nameText, Health = healthText}

    local connection
    connection = RunService.RenderStepped:Connect(function()
        if player and player.Parent and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChildOfClass("Humanoid").Health > 0 then
            local hrp = player.Character.HumanoidRootPart
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)

            if onScreen and Settings.ESP.Enabled then
                local hue = (tick() * 0.2) % 1
                local playerColor = Color3.fromHSV(hue, 1, 1)

                local head = player.Character:FindFirstChild("Head")
                if head then
                    local headPos = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                    local legPos = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                    local height = math.abs(headPos.Y - legPos.Y)
                    local width = height / 1.5

                    if Settings.ESP.Boxes then
                        box.Size = Vector2.new(width, height)
                        box.Position = Vector2.new(pos.X - width / 2, pos.Y - height / 2)
                        box.Color = playerColor
                        box.Visible = true
                    else
                        box.Visible = false
                    end

                    if Settings.ESP.Names then
                        nameText.Text = "[Player] " .. player.Name
                        nameText.Position = Vector2.new(pos.X, headPos.Y - 20)
                        nameText.Color = playerColor
                        nameText.Visible = true
                    else
                        nameText.Visible = false
                    end

                    if Settings.ESP.Health then
                        healthText.Text = "HP: " .. math.floor(humanoid.Health) .. "/" .. math.floor(humanoid.MaxHealth)
                        healthText.Position = Vector2.new(pos.X, legPos.Y + 5)
                        healthText.Color = Color3.fromRGB(0, 255, 100)
                        healthText.Visible = true
                    else
                        healthText.Visible = false
                    end
                else
                    box.Visible = false
                    nameText.Visible = false
                    healthText.Visible = false
                end

                if Settings.ESP.Tracers then
                    tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                    tracer.To = Vector2.new(pos.X, pos.Y)
                    tracer.Color = playerColor
                    tracer.Visible = true
                else
                    tracer.Visible = false
                end
            else
                box.Visible = false
                tracer.Visible = false
                nameText.Visible = false
                healthText.Visible = false
            end
        else
            box.Visible = false
            tracer.Visible = false
            nameText.Visible = false
            healthText.Visible = false
            if not Players:FindFirstChild(player.Name) then
                box:Remove()
                tracer:Remove()
                nameText:Remove()
                healthText:Remove()
                ESPObjects[player] = nil
                connection:Disconnect()
            end
        end
    end)
end

for _, p in pairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then CreateESP(p) end
end
Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer then CreateESP(p) end
end)

-- Bot ESP Loop
RunService.RenderStepped:Connect(function()
    if not Settings.ESP.Enabled or not Settings.ESP.BotESP then
        for _, botData in pairs(BotESPObjects) do
            if botData.Box then botData.Box.Visible = false end
            if botData.Name then botData.Name.Visible = false end
        end
        return
    end

    local activeBots = {}
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj ~= LocalPlayer.Character then
            local humanoid = obj:FindFirstChildOfClass("Humanoid")
            local hrp = obj:FindFirstChild("HumanoidRootPart")
            if humanoid and humanoid.Health > 0 and hrp and not Players:GetPlayerFromCharacter(obj) then
                activeBots[obj] = true

                if not BotESPObjects[obj] then
                    local box = Drawing.new("Square")
                    box.Thickness = 1.5
                    box.Filled = false
                    box.Color = Color3.fromRGB(255, 140, 0)

                    local nameText = Drawing.new("Text")
                    nameText.Size = 13
                    nameText.Center = true
                    nameText.Outline = true
                    nameText.Color = Color3.fromRGB(255, 200, 0)

                    BotESPObjects[obj] = {Box = box, Name = nameText}
                end

                local botData = BotESPObjects[obj]
                local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    local head = obj:FindFirstChild("Head") or hrp
                    local headPos = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                    local legPos = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                    local height = math.abs(headPos.Y - legPos.Y)
                    local width = height / 1.5

                    botData.Box.Size = Vector2.new(width, height)
                    botData.Box.Position = Vector2.new(pos.X - width / 2, pos.Y - height / 2)
                    botData.Box.Visible = Settings.ESP.Boxes

                    botData.Name.Text = "[Bot] " .. obj.Name
                    botData.Name.Position = Vector2.new(pos.X, headPos.Y - 20)
                    botData.Name.Visible = Settings.ESP.Names
                else
                    botData.Box.Visible = false
                    botData.Name.Visible = false
                end
            end
        end
    end

    for obj, botData in pairs(BotESPObjects) do
        if not activeBots[obj] then
            if botData.Box then botData.Box:Remove() end
            if botData.Name then botData.Name:Remove() end
            BotESPObjects[obj] = nil
        end
    end
end)

-- ==================== RAINBOW HIGHLIGHT ESP (ออร่ารุ้ง) ====================
RunService.RenderStepped:Connect(function()
    if Settings.ESP.Enabled and Settings.ESP.RainbowHighlight then
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local highlight = ESP_Highlights[player]
                if not highlight or not highlight.Parent then
                    if highlight then highlight:Destroy() end
                    highlight = Instance.new("Highlight")
                    highlight.Name = "RainbowESP"
                    highlight.FillTransparency = 0.6 -- กึ่งโปร่ง
                    highlight.OutlineTransparency = 0
                    highlight.Parent = player.Character
                    ESP_Highlights[player] = highlight
                end
                local hue = (tick() * 0.3) % 1
                highlight.OutlineColor = Color3.fromHSV(hue, 1, 1)
                highlight.FillColor = Color3.fromHSV(hue, 1, 1)
            end
        end
        -- ลบ highlight ของคนที่ออกหรือตาย
        for player, hl in pairs(ESP_Highlights) do
            if not player.Parent or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChildOfClass("Humanoid").Health <= 0 then
                hl:Destroy()
                ESP_Highlights[player] = nil
            end
        end
    else
        for _, hl in pairs(ESP_Highlights) do
            hl:Destroy()
        end
        ESP_Highlights = {}
    end
end)

-- ==================== GUI INTERFACE ====================
local OldGui = CoreGui:FindFirstChild("KutonHub")
if OldGui then OldGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui", CoreGui)
ScreenGui.Name = "KutonHub"

-- หน้าต่างหลัก (เพิ่มระบบปรับขนาด)
local RainbowBorder = Instance.new("Frame", ScreenGui)
RainbowBorder.Size = UDim2.new(0, 310, 0, 460)
RainbowBorder.Position = UDim2.new(0.05, 0, 0.15, 0)
RainbowBorder.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
RainbowBorder.BorderSizePixel = 0
RainbowBorder.Active = true
RainbowBorder.Draggable = true  -- ย้ายตำแหน่งได้
RainbowBorder.ClipsDescendants = false -- ให้ resize handle อยู่มุมได้
Instance.new("UICorner", RainbowBorder).CornerRadius = UDim.new(0, 12)

-- เพิ่มปุ่มปรับขนาด (Resize Handle)
local ResizeHandle = Instance.new("TextButton", RainbowBorder)
ResizeHandle.Size = UDim2.new(0, 20, 0, 20)
ResizeHandle.Position = UDim2.new(1, -20, 1, -20)
ResizeHandle.Text = "◢"
ResizeHandle.TextColor3 = Color3.fromRGB(255, 255, 255)
ResizeHandle.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
ResizeHandle.BorderSizePixel = 0
ResizeHandle.ZIndex = 10
ResizeHandle.AutoButtonColor = false
Instance.new("UICorner", ResizeHandle).CornerRadius = UDim.new(0, 5)

local resizing = false
local startMousePos = nil
local startSize = nil

ResizeHandle.MouseButton1Down:Connect(function()
    resizing = true
    startMousePos = UserInputService:GetMouseLocation()
    startSize = RainbowBorder.AbsoluteSize
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        resizing = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
        local currentPos = UserInputService:GetMouseLocation()
        local delta = currentPos - startMousePos
        local newSize = startSize + Vector2.new(delta.X, delta.Y)
        newSize = Vector2.new(math.max(200, newSize.X), math.max(300, newSize.Y))
        RainbowBorder.Size = UDim2.new(0, newSize.X, 0, newSize.Y)
    end
end)

-- เส้นขอบรุ้งวน
task.spawn(function()
    local hue = 0
    while RainbowBorder and RainbowBorder.Parent do
        hue = (hue + 0.005) % 1
        RainbowBorder.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
        task.wait(0.03)
    end
end)

local MainFrame = Instance.new("Frame", RainbowBorder)
MainFrame.Size = UDim2.new(1, -4, 1, -4)
MainFrame.Position = UDim2.new(0, 2, 0, 2)
MainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
MainFrame.BorderSizePixel = 0
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local BgGradient = Instance.new("UIGradient", MainFrame)
BgGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 10, 35)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 10, 14)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 25, 35))
})
BgGradient.Rotation = 90

local TitleBar = Instance.new("Frame", MainFrame)
TitleBar.Size = UDim2.new(1, 0, 0, 40)
TitleBar.BackgroundTransparency = 1

local TitleText = Instance.new("TextLabel", TitleBar)
TitleText.Size = UDim2.new(1, -85, 1, 0)
TitleText.Position = UDim2.new(0, 12, 0, 0)
TitleText.Text = "⚡ กูต้นดิว่ะ v9.5 [Resize+Rainbow]"
TitleText.TextColor3 = Color3.fromRGB(255, 215, 0)
TitleText.Font = Enum.Font.GothamBold
TitleText.TextSize = 11
TitleText.TextXAlignment = Enum.TextXAlignment.Left
TitleText.BackgroundTransparency = 1

local MinimizeBtn = Instance.new("TextButton", TitleBar)
MinimizeBtn.Size = UDim2.new(0, 25, 0, 25)
MinimizeBtn.Position = UDim2.new(1, -60, 0, 7)
MinimizeBtn.Text = "-"
MinimizeBtn.TextColor3 = Color3.fromRGB(255, 215, 0)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.TextSize = 12
Instance.new("UICorner", MinimizeBtn).CornerRadius = UDim.new(0, 5)

local CloseBtn = Instance.new("TextButton", TitleBar)
CloseBtn.Size = UDim2.new(0, 25, 0, 25)
CloseBtn.Position = UDim2.new(1, -30, 0, 7)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
CloseBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 10
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5)

-- ==================== TAB SYSTEM ====================
local TabContainer = Instance.new("Frame", MainFrame)
TabContainer.Size = UDim2.new(1, -12, 0, 32)
TabContainer.Position = UDim2.new(0, 6, 0, 42)
TabContainer.BackgroundTransparency = 1

local TabListLayout = Instance.new("UIListLayout", TabContainer)
TabListLayout.FillDirection = Enum.FillDirection.Horizontal
TabListLayout.Padding = UDim.new(0, 3)
TabListLayout.SortOrder = Enum.SortOrder.LayoutOrder

local PagesContainer = Instance.new("Frame", MainFrame)
PagesContainer.Size = UDim2.new(1, -12, 1, -84)
PagesContainer.Position = UDim2.new(0, 6, 0, 80)
PagesContainer.BackgroundTransparency = 1

local Pages = {}

local function createTab(name, index, totalTabs)
    local tabBtn = Instance.new("TextButton", TabContainer)
    tabBtn.Size = UDim2.new(1 / totalTabs, -2, 1, 0)
    tabBtn.Text = name
    tabBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    tabBtn.BackgroundColor3 = Color3.fromRGB(18, 18, 25)
    tabBtn.Font = Enum.Font.GothamBold
    tabBtn.TextSize = 9
    Instance.new("UICorner", tabBtn).CornerRadius = UDim.new(0, 6)

    local pageScroll = Instance.new("ScrollingFrame", PagesContainer)
    pageScroll.Size = UDim2.new(1, 0, 1, 0)
    pageScroll.BackgroundTransparency = 1
    pageScroll.ScrollBarThickness = 4
    pageScroll.ScrollBarImageColor3 = Color3.fromRGB(0, 255, 200)
    pageScroll.CanvasSize = UDim2.new(0, 0, 0, 1800) -- เผื่อไว้
    pageScroll.Visible = (index == 1)

    local pageLayout = Instance.new("UIListLayout", pageScroll)
    pageLayout.Padding = UDim.new(0, 6)
    pageLayout.SortOrder = Enum.SortOrder.LayoutOrder

    Pages[index] = {Button = tabBtn, Scroll = pageScroll}

    tabBtn.MouseButton1Click:Connect(function()
        for idx, p in pairs(Pages) do
            p.Scroll.Visible = (idx == index)
            p.Button.BackgroundColor3 = (idx == index) and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
            p.Button.TextColor3 = (idx == index) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
        end
    end)

    if index == 1 then
        tabBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 120)
        tabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    end

    return pageScroll
end

local Tab1Scroll = createTab("⚔️ ต่อสู้", 1, 5)
local Tab2Scroll = createTab("👀 มองทะลุ", 2, 5)  -- Tab ESP
local Tab3Scroll = createTab("⚙️ ผู้เล่น", 3, 5)
local Tab4Scroll = createTab("🎁 ไอเทม", 4, 5)
local Tab5Scroll = createTab("🌐 เซิร์ฟ", 5, 5)

local isMinimized = false
MinimizeBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    TabContainer.Visible = not isMinimized
    PagesContainer.Visible = not isMinimized
    RainbowBorder.Size = isMinimized and UDim2.new(0, 310, 0, 42) or UDim2.new(0, 310, 0, 460)
end)

CloseBtn.MouseButton1Click:Connect(function() 
    FOVRainbowActive = false
    FOVCircle:Remove()
    for _, obj in pairs(ESPObjects) do
        if obj.Box then obj.Box:Remove() end
        if obj.Tracer then obj.Tracer:Remove() end
        if obj.Name then obj.Name:Remove() end
        if obj.Health then obj.Health:Remove() end
    end
    for _, botData in pairs(BotESPObjects) do
        if botData.Box then botData.Box:Remove() end
        if botData.Name then botData.Name:Remove() end
    end
    for _, hl in pairs(ESP_Highlights) do
        hl:Destroy()
    end
    ToggleXRay(false)
    ToggleFPSBoost(false)
    if tpTool then tpTool:Destroy() end
    if speedTool then speedTool:Destroy() end
    if killAuraTool then killAuraTool:Destroy() end
    if blinkTool then blinkTool:Destroy() end
    if morphTool then morphTool:Destroy() end
    if noclipConn then noclipConn:Disconnect() end
    if infJumpConn then infJumpConn:Disconnect() end
    if clickDelConn then clickDelConn:Disconnect() end
    if ctrlClickConn then ctrlClickConn:Disconnect() end
    if autoHealConn then autoHealConn:Disconnect() end
    ScreenGui:Destroy() 
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.RightShift then
        RainbowBorder.Visible = not RainbowBorder.Visible
    end
end)

local function createButtonInParent(parent, text, callback)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0.96, 0, 0, 34)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(240, 240, 240)
    btn.BackgroundColor3 = Color3.fromRGB(18, 18, 25)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 11
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    
    local state = false
    btn.MouseButton1Click:Connect(function()
        state = not state
        callback(state, btn)
    end)
    return btn
end

local function addActionInParent(parent, name, callback)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0.96, 0, 0, 34)
    btn.Text = name
    btn.TextColor3 = Color3.fromRGB(0, 255, 200)
    btn.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    btn.MouseButton1Click:Connect(callback)
end

local function createSliderInParent(parent, titleText, min, max, default, callback)
    -- (เหมือนเดิม)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(0.96, 0, 0, 48)
    container.BackgroundColor3 = Color3.fromRGB(18, 18, 25)
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 6)

    local label = Instance.new("TextLabel", container)
    label.Size = UDim2.new(1, -10, 0, 20)
    label.Position = UDim2.new(0, 10, 0, 4)
    label.Text = titleText .. ": " .. tostring(default)
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left

    local bar = Instance.new("TextButton", container)
    bar.Size = UDim2.new(0.92, 0, 0, 8)
    bar.Position = UDim2.new(0.04, 0, 0.65, 0)
    bar.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    bar.Text = ""
    bar.AutoButtonColor = false
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame", bar)
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 255, 200)
    fill.BorderSizePixel = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local dragging = false
    local function update(input)
        local pos = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        fill.Size = UDim2.new(pos, 0, 1, 0)
        local val = math.floor(min + (pos * (max - min)))
        label.Text = titleText .. ": " .. tostring(val)
        callback(val)
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(input)
        end
    end)

    bar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input)
        end
    end)
end

local function addInputInParent(parent, name, defaultVal, callback)
    -- (เหมือนเดิม)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(0.96, 0, 0, 40)
    container.BackgroundColor3 = Color3.fromRGB(18, 18, 25)
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 6)
    
    local label = Instance.new("TextLabel", container)
    label.Size = UDim2.new(0.55, 0, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Text = name
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    
    local textBox = Instance.new("TextBox", container)
    textBox.Size = UDim2.new(0.35, 0, 0.65, 0)
    textBox.Position = UDim2.new(0.60, 0, 0.17, 0)
    textBox.Text = tostring(defaultVal)
    textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    textBox.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    textBox.Font = Enum.Font.Gotham
    textBox.TextSize = 11
    Instance.new("UICorner", textBox).CornerRadius = UDim.new(0, 4)
    
    textBox.FocusLost:Connect(function()
        if textBox.Text ~= "" then
            callback(textBox.Text)
        end
    end)
end

-- ==================== TAB 1: COMBAT ====================
createButtonInParent(Tab1Scroll, "ระบบล็อคเป้า (Aimbot) : ปิด", function(st, btn)
    Settings.Aimbot.Enabled = st
    btn.Text = "ระบบล็อคเป้า (Aimbot) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab1Scroll, "ล็อคเป้าตัวที่ใกล้ที่สุด : ปิด", function(st, btn)
    Settings.Aimbot.ClosestToPlayer = st
    btn.Text = "ล็อคเป้าตัวที่ใกล้ที่สุด : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab1Scroll, "ล็อคเป้าหมายบอท (Target Bots) : ปิด", function(st, btn)
    Settings.Aimbot.TargetBots = st
    btn.Text = "ล็อคเป้าหมายบอท (Target Bots) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab1Scroll, "แสดงวงกลม FOV : ปิด", function(st, btn)
    Settings.Aimbot.ShowFOV = st
    btn.Text = "แสดงวงกลม FOV : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab1Scroll, "เป้าหมาย : ล็อคหัว (Head)", function(st, btn)
    if Settings.Aimbot.TargetPart == "Head" then
        Settings.Aimbot.TargetPart = "HumanoidRootPart"
        btn.Text = "เป้าหมาย : ล็อคลำตัว (Torso)"
    elseif Settings.Aimbot.TargetPart == "HumanoidRootPart" then
        Settings.Aimbot.TargetPart = "Both"
        btn.Text = "เป้าหมาย : ล็อคหัว/ตัว (Both)"
    else
        Settings.Aimbot.TargetPart = "Head"
        btn.Text = "เป้าหมาย : ล็อคหัว (Head)"
    end
end)

createButtonInParent(Tab1Scroll, "เช็คทีมผู้เล่น (Team Check) : ปิด", function(st, btn)
    Settings.Aimbot.TeamCheck = st
    btn.Text = "เช็คทีมผู้เล่น (Team Check) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

-- เพิ่มปุ่มล็อคหลังกำแพง
createButtonInParent(Tab1Scroll, "ล็อคหลังกำแพง (Through Walls) : ปิด", function(st, btn)
    Settings.Aimbot.ThroughWalls = st
    btn.Text = "ล็อคหลังกำแพง (Through Walls) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createSliderInParent(Tab1Scroll, "ขนาดวงกลม FOV", 20, 500, 150, function(val)
    Settings.Aimbot.FOV = val
end)

createButtonInParent(Tab1Scroll, "โหมดอมตะ (God) : ปิด", function(st, btn)
    Settings.Defense.GodMode = st
    btn.Text = "โหมดอมตะ (God) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
    if st and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
        LocalPlayer.Character:FindFirstChildOfClass("Humanoid").Health = LocalPlayer.Character:FindFirstChildOfClass("Humanoid").MaxHealth
    end
end)

-- ==================== TAB 2: ESP ====================
createButtonInParent(Tab2Scroll, "เปิด/ปิด ESP ทั้งหมด : ปิด", function(st, btn)
    Settings.ESP.Enabled = st
    btn.Text = "เปิด/ปิด ESP ทั้งหมด : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab2Scroll, "กล่อง (Box) : ปิด", function(st, btn)
    Settings.ESP.Boxes = st
    btn.Text = "กล่อง (Box) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab2Scroll, "เส้นชี้เป้า (Tracer) : ปิด", function(st, btn)
    Settings.ESP.Tracers = st
    btn.Text = "เส้นชี้เป้า (Tracer) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab2Scroll, "ชื่อผู้เล่น (Name) : ปิด", function(st, btn)
    Settings.ESP.Names = st
    btn.Text = "ชื่อผู้เล่น (Name) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab2Scroll, "หลอดเลือด (Health) : ปิด", function(st, btn)
    Settings.ESP.Health = st
    btn.Text = "หลอดเลือด (Health) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab2Scroll, "ESP บอท (Bot ESP) : ปิด", function(st, btn)
    Settings.ESP.BotESP = st
    btn.Text = "ESP บอท (Bot ESP) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

-- เพิ่มปุ่มออร่ารุ้ง
createButtonInParent(Tab2Scroll, "ออร่ารุ้งรอบตัวผู้เล่น (Rainbow) : ปิด", function(st, btn)
    Settings.ESP.RainbowHighlight = st
    btn.Text = "ออร่ารุ้งรอบตัวผู้เล่น (Rainbow) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab2Scroll, "มองทะลุกำแพง (XRay) : ปิด", function(st, btn)
    ToggleXRay(st)
    btn.Text = "มองทะลุกำแพง (XRay) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab2Scroll, "แสงสว่างทั่วแมพ (Fullbright) : ปิด", function(st, btn)
    Settings.ESP.Fullbright = st
    SetFullbright(st)
    btn.Text = "แสงสว่างทั่วแมพ (Fullbright) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab2Scroll, "ลบเทกซ์เจอร์เพิ่ม FPS : ปิด", function(st, btn)
    ToggleFPSBoost(st)
    btn.Text = "ลบเทกซ์เจอร์เพิ่ม FPS : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

-- ==================== TAB 3: PLAYER ====================
addInputInParent(Tab3Scroll, "ความเร็วเดิน (WalkSpeed)", "16", function(val)
    local num = tonumber(val)
    if num then
        Settings.Player.WalkSpeed = num
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
            LocalPlayer.Character:FindFirstChildOfClass("Humanoid").WalkSpeed = num
        end
    end
end)

addInputInParent(Tab3Scroll, "ความสูงกระโดด (JumpPower)", "50", function(val)
    local num = tonumber(val)
    if num then
        Settings.Player.JumpPower = num
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
            LocalPlayer.Character:FindFirstChildOfClass("Humanoid").JumpPower = num
        end
    end
end)

addInputInParent(Tab3Scroll, "ความเร็วการบิน (FlySpeed)", "1", function(val)
    local num = tonumber(val)
    if num then Settings.Player.FlySpeed = num end
end)

createButtonInParent(Tab3Scroll, "เปิด/ปิด บิน (Fly Q/E) : ปิด", function(st, btn)
    ToggleFly(st)
    btn.Text = "เปิด/ปิด บิน (Fly Q/E) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab3Scroll, "รีเลือดตัวเองให้เต็มตลอด (Auto Heal) : ปิด", function(st, btn)
    Settings.Defense.AutoHeal = st
    btn.Text = "รีเลือดตัวเองให้เต็มตลอด (Auto Heal) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab3Scroll, "เดินทะลุกำแพง (Noclip) : ปิด", function(st, btn)
    Settings.Player.Noclip = st
    btn.Text = "เดินทะลุกำแพง (Noclip) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab3Scroll, "กระโดดไม่จำกัด (InfJump) : ปิด", function(st, btn)
    Settings.Player.InfJump = st
    btn.Text = "กระโดดไม่จำกัด (InfJump) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab3Scroll, "โหมดล่องหน (Invisible) : ปิด", function(st, btn)
    ToggleInvisible(st)
    btn.Text = "โหมดล่องหน (Invisible) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab3Scroll, "คลิกที่วัตถุเพื่อลบ (ClickDelete) : ปิด", function(st, btn)
    Settings.Player.ClickDelete = st
    btn.Text = "คลิกที่วัตถุเพื่อลบ (ClickDelete) : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab3Scroll, "กด Ctrl+คลิก เพื่อวาร์ป : ปิด", function(st, btn)
    Settings.Player.CtrlClickTP = st
    btn.Text = "กด Ctrl+คลิก เพื่อวาร์ป : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

-- *** ส่วนจัดการวาปหลายจุด ***
local wpHeaderLabel = Instance.new("TextLabel", Tab3Scroll)
wpHeaderLabel.Size = UDim2.new(0.96, 0, 0, 25)
wpHeaderLabel.Text = "📌 บันทึกจุดวาปหลายจุด (ใส่ชื่อแล้วกด Save):"
wpHeaderLabel.TextColor3 = Color3.fromRGB(0, 255, 200)
wpHeaderLabel.BackgroundTransparency = 1
wpHeaderLabel.Font = Enum.Font.GothamBold
wpHeaderLabel.TextSize = 11
wpHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left

-- ช่องกรอกชื่อจุด
local wpNameBox = Instance.new("TextBox", Tab3Scroll)
wpNameBox.Size = UDim2.new(0.96, 0, 0, 30)
wpNameBox.PlaceholderText = "ชื่อจุด (เว้นว่าง = auto)"
wpNameBox.Text = ""
wpNameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
wpNameBox.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
wpNameBox.Font = Enum.Font.Gotham
wpNameBox.TextSize = 11
Instance.new("UICorner", wpNameBox).CornerRadius = UDim.new(0, 4)

-- ปุ่มบันทึกจุด
addActionInParent(Tab3Scroll, "💾 บันทึกจุดปัจจุบัน (Save Pos)", function()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local name = wpNameBox.Text
        if name == "" then
            name = "จุดที่ " .. tostring(#SavedWaypoints + 1)
        end
        SavedWaypoints[name] = hrp.CFrame
        wpNameBox.Text = ""
        RefreshWaypointList()
    end
end)

-- ส่วนแสดงรายการจุดวาป
local wpListContainer = Instance.new("Frame", Tab3Scroll)
wpListContainer.Size = UDim2.new(0.96, 0, 0, 200)
wpListContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
Instance.new("UICorner", wpListContainer).CornerRadius = UDim.new(0, 6)

local wpListScroll = Instance.new("ScrollingFrame", wpListContainer)
wpListScroll.Size = UDim2.new(1, -4, 1, -4)
wpListScroll.Position = UDim2.new(0, 2, 0, 2)
wpListScroll.BackgroundTransparency = 1
wpListScroll.ScrollBarThickness = 4
wpListScroll.ScrollBarImageColor3 = Color3.fromRGB(0, 255, 200)
wpListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)

local wpListLayout = Instance.new("UIListLayout", wpListScroll)
wpListLayout.Padding = UDim.new(0, 4)
wpListLayout.SortOrder = Enum.SortOrder.LayoutOrder

function RefreshWaypointList()
    -- เคลียร์ปุ่มเดิม
    for _, child in pairs(wpListScroll:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("Frame") then
            child:Destroy()
        end
    end
    
    local count = 0
    for name, pos in pairs(SavedWaypoints) do
        count = count + 1
        -- สร้างแถว
        local row = Instance.new("Frame", wpListScroll)
        row.Size = UDim2.new(1, 0, 0, 30)
        row.BackgroundTransparency = 1
        
        local teleBtn = Instance.new("TextButton", row)
        teleBtn.Size = UDim2.new(0.75, 0, 0, 28)
        teleBtn.Position = UDim2.new(0, 0, 0, 0)
        teleBtn.Text = " 🚀 " .. name
        teleBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
        teleBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
        teleBtn.Font = Enum.Font.Gotham
        teleBtn.TextSize = 11
        teleBtn.TextXAlignment = Enum.TextXAlignment.Left
        Instance.new("UICorner", teleBtn).CornerRadius = UDim.new(0, 4)
        teleBtn.MouseButton1Click:Connect(function()
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and SavedWaypoints[name] then
                hrp.CFrame = SavedWaypoints[name]
            end
        end)
        
        local delBtn = Instance.new("TextButton", row)
        delBtn.Size = UDim2.new(0, 20, 0, 28)
        delBtn.Position = UDim2.new(0.80, 0, 0, 0)
        delBtn.Text = "✕"
        delBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
        delBtn.BackgroundColor3 = Color3.fromRGB(40, 10, 10)
        delBtn.Font = Enum.Font.GothamBold
        delBtn.TextSize = 12
        Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 4)
        delBtn.MouseButton1Click:Connect(function()
            SavedWaypoints[name] = nil
            RefreshWaypointList()
        end)
    end
    wpListScroll.CanvasSize = UDim2.new(0, 0, 0, count * 34)
end

-- ปุ่มรีเฟรช
addActionInParent(Tab3Scroll, "🔄 รีเฟรชรายการจุดวาป", RefreshWaypointList)

-- เรียกครั้งแรก
RefreshWaypointList()

-- ==================== TAB 4: ITEM ====================
-- (เหมือนเดิม)
createButtonInParent(Tab4Scroll, "⚡ [Item] คทาวาร์ปล่องหน : ปิด", function(st, btn)
    ToggleTeleportTool(st)
    btn.Text = "⚡ [Item] คทาวาร์ปล่องหน : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab4Scroll, "👟 [Item] รองเท้าพุ่งความเร็ว : ปิด", function(st, btn)
    ToggleSpeedTool(st)
    btn.Text = "👟 [Item] รองเท้าพุ่งความเร็ว : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab4Scroll, "🗡️ [Item] มีดออร่าสังหารรอบตัว : ปิด", function(st, btn)
    ToggleKillAuraTool(st)
    btn.Text = "🗡️ [Item] มีดออร่าสังหารรอบตัว : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab4Scroll, "💥 [Item] คทาลบเป้าหมายฉับพลัน : ปิด", function(st, btn)
    ToggleBlinkTool(st)
    btn.Text = "💥 [Item] คทาลบเป้าหมายฉับพลัน : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

createButtonInParent(Tab4Scroll, "🎭 [Item] คทาก๊อปปี้ร่างแปลง : ปิด", function(st, btn)
    ToggleMorphTool(st)
    btn.Text = "🎭 [Item] คทาก๊อปปี้ร่างแปลง : " .. (st and "เปิด" or "ปิด")
    btn.BackgroundColor3 = st and Color3.fromRGB(0, 140, 120) or Color3.fromRGB(18, 18, 25)
end)

-- ระบบแปลงร่าง (เหมือนเดิม)
local morphHeaderLabel = Instance.new("TextLabel", Tab4Scroll)
morphHeaderLabel.Size = UDim2.new(0.96, 0, 0, 25)
morphHeaderLabel.Text = "👥 เลือกแปลงร่างเป็นผู้เล่น (คลิกชื่อเพื่อน):"
morphHeaderLabel.TextColor3 = Color3.fromRGB(0, 255, 200)
morphHeaderLabel.BackgroundTransparency = 1
morphHeaderLabel.Font = Enum.Font.GothamBold
morphHeaderLabel.TextSize = 11
morphHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left

local morphListContainer = Instance.new("Frame", Tab4Scroll)
morphListContainer.Size = UDim2.new(0.96, 0, 0, 120)
morphListContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
Instance.new("UICorner", morphListContainer).CornerRadius = UDim.new(0, 6)

local morphListScroll = Instance.new("ScrollingFrame", morphListContainer)
morphListScroll.Size = UDim2.new(1, -4, 1, -4)
morphListScroll.Position = UDim2.new(0, 2, 0, 2)
morphListScroll.BackgroundTransparency = 1
morphListScroll.ScrollBarThickness = 4
morphListScroll.ScrollBarImageColor3 = Color3.fromRGB(0, 255, 200)
morphListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)

local morphListLayout = Instance.new("UIListLayout", morphListScroll)
morphListLayout.Padding = UDim.new(0, 4)
morphListLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function RefreshMorphList()
    for _, child in pairs(morphListScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    
    local count = 0
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            count = count + 1
            local pBtn = Instance.new("TextButton", morphListScroll)
            pBtn.Size = UDim2.new(1, 0, 0, 28)
            pBtn.Text = " 🎭 แปลงเป็น: " .. p.Name
            pBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
            pBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
            pBtn.Font = Enum.Font.Gotham
            pBtn.TextSize = 11
            pBtn.TextXAlignment = Enum.TextXAlignment.Left
            Instance.new("UICorner", pBtn).CornerRadius = UDim.new(0, 4)
            
            pBtn.MouseButton1Click:Connect(function()
                MorphToPlayer(p)
            end)
        end
    end
    morphListScroll.CanvasSize = UDim2.new(0, 0, 0, count * 32)
end

RefreshMorphList()
Players.PlayerAdded:Connect(RefreshMorphList)
Players.PlayerRemoving:Connect(RefreshMorphList)

addActionInParent(Tab4Scroll, "🔄 รีเฟรชรายชื่อแปลงร่าง", RefreshMorphList)

-- ==================== TAB 5: SERVER ====================
addActionInParent(Tab5Scroll, "🔄 รีเซ็ตสคริปทั้งหมดคืนค่าเดิม", ResetAllScriptsAndStates)
addActionInParent(Tab5Scroll, "ย้ายไปเซิร์ฟคนน้อย (Low Server)", LowServer)
addActionInParent(Tab5Scroll, "ย้ายสุ่มเซิร์ฟเวอร์ (ServerHop)", ServerHop)
addActionInParent(Tab5Scroll, "เข้าเซิร์ฟเวอร์เดิมใหม่ (Rejoin)", function()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end)
addActionInParent(Tab5Scroll, "รีเซ็ตตัวละคร (Reset)", function()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
        LocalPlayer.Character:FindFirstChildOfClass("Humanoid").Health = 0
    end
end)

-- ==================== CUSTOM TOGGLE BUTTON ====================
local ToggleBtn = Instance.new("TextButton", ScreenGui)
ToggleBtn.Size = UDim2.new(0, 115, 0, 32)
ToggleBtn.Position = UDim2.new(0, 15, 0.4, 0)
ToggleBtn.Text = "⚡ กูต้นดิว่ะ"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 215, 0)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 10
ToggleBtn.Active = true
ToggleBtn.Draggable = true
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 6)

local BtnBorder = Instance.new("UIStroke", ToggleBtn)
BtnBorder.Thickness = 2
task.spawn(function()
    local hue = 0
    while ToggleBtn and ToggleBtn.Parent do
        hue = (hue + 0.005) % 1
        BtnBorder.Color = Color3.fromHSV(hue, 1, 1)
        task.wait(0.03)
    end
end)

ToggleBtn.MouseButton1Click:Connect(function()
    RainbowBorder.Visible = not RainbowBorder.Visible
end)
