--[[
    Yenrenuton [OUT OF ALPHA]  (v4)
    UI: WindUI | Key: WELLCOME | Mobile / PC / Laptop

    v4.1 ADDITIONS
    - Aimbot: Camera Lock / Non-Camera Lock, NPC targets, draggable ON/OFF switch
    - Bundle pack + Emote animations (with saved lists), Noclip, No Fog / No Darkness / Full Brightness,
      First/Third person, stronger RTX, Teleport Points (+ESP, ordered routes), Fake Lag,
      NPC list: Aimbot / Fling / Delete / Drain

    CHANGES
    - AIMBOT: prediction (leads moving targets, leads along their movement when they back away,
      aims normally when they run toward you), projectile-speed mode, vertical toggle,
      on-screen KILL BUTTON + kill key so you can turn it off any time.
    - FLY / SPEED / JUMP POWER: now the Infinite Yield method
        Fly   = BodyGyro + BodyVelocity + PlatformStand, ControlModule move vector (mobile + PC)
        Speed = WalkSpeed property loop  |  TPWalk (TranslateBy)
        Jump  = JumpPower / JumpHeight (UseJumpPower aware) loop  |  Infinite Jump
    - ESP: Aura (Highlight) / Box (SelectionBox) / Both, plus HP | Distance | Team label.
    - Removed the custom reopen icon (WindUI's own open button is used).
    - Every numeric setting is a TEXT BOX (no sliders).

    NEW
    R6->R15, R15->R6 | Invisible | Ragdoll | TP Tool | Weather (local) | RTX (local)
    Headsit | Cape | Hang on back | Platform Tool | Freeze
]]

------------------------------------------------------------
-- Single-instance guard
------------------------------------------------------------
local genv = (getgenv and getgenv()) or _G
if genv.__YenrenutonUnload then pcall(genv.__YenrenutonUnload) end

------------------------------------------------------------
-- Services
------------------------------------------------------------
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local TweenService        = game:GetService("TweenService")
local Workspace           = game:GetService("Workspace")
local CoreGui             = game:GetService("CoreGui")
local Lighting            = game:GetService("Lighting")
local MaterialService     = game:GetService("MaterialService")
local AvatarEditorService = game:GetService("AvatarEditorService")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

------------------------------------------------------------
-- Platform detection
------------------------------------------------------------
local Platform = {}
Platform.Touch    = UserInputService.TouchEnabled
Platform.Keyboard = UserInputService.KeyboardEnabled
Platform.Mobile   = Platform.Touch and not Platform.Keyboard
Platform.Laptop   = Platform.Keyboard and (Camera.ViewportSize.X < 1500)
Platform.PC       = Platform.Keyboard and not Platform.Laptop

function Y.getWindowSize()
    local vp = Camera.ViewportSize
    local w = math.clamp(vp.X - 40, 300, Platform.Mobile and 500 or 580)
    local h = math.clamp(vp.Y - 70, 220, Platform.Mobile and 320 or 460)
    return UDim2.fromOffset(w, h)
end

function Y.guiParent()
    local ok, h = pcall(function() return (gethui and gethui()) end)
    if ok and h then return h end
    local ok2 = pcall(function() return CoreGui.Name end)
    if ok2 then return CoreGui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

------------------------------------------------------------
-- Load WindUI
------------------------------------------------------------
local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

------------------------------------------------------------
-- Maid
------------------------------------------------------------
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({ _tasks = {} }, Maid) end
function Y.disposeTask(t)
    local ty = typeof(t)
    if ty == "RBXScriptConnection" then t:Disconnect()
    elseif ty == "Instance" then t:Destroy()
    elseif ty == "function" then pcall(t)
    elseif ty == "table" and t.Remove then pcall(function() t:Remove() end)
    elseif ty == "table" and t.Destroy then pcall(function() t:Destroy() end) end
end
function Maid:Give(task_, key)
    if key then self:Clear(key) end
    self._tasks[key or (#self._tasks + 1)] = task_
    return task_
end
function Maid:Clear(key)
    local t = self._tasks[key]
    if t ~= nil then self._tasks[key] = nil; Y.disposeTask(t) end
end
function Maid:Destroy()
    for k, t in pairs(self._tasks) do self._tasks[k] = nil; Y.disposeTask(t) end
end

local MainMaid = Maid.new()
local Feature  = {}
local Y = {} -- namespace for top-level helper functions (keeps main-chunk local count under Luau's 200 limit)
function Y.fmaid(name)
    if not Feature[name] then Feature[name] = Maid.new() end
    return Feature[name]
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
function Y.getChar() return LocalPlayer.Character end
function Y.getHum()
    local c = Y.getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
function Y.getRoot()
    local c = Y.getChar()
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end
function Y.isAlive(plr)
    local c = plr.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    return h ~= nil and h.Health > 0 and c:FindFirstChild("HumanoidRootPart") ~= nil
end
function Y.sameTeam(plr)
    return LocalPlayer.Team ~= nil and plr.Team == LocalPlayer.Team
end
function Y.isCharacterPart(part)
    local mdl = part:FindFirstAncestorOfClass("Model")
    return mdl ~= nil and mdl:FindFirstChildOfClass("Humanoid") ~= nil
end
function Y.notify(title, content, dur)
    pcall(function()
        WindUI:Notify({ Title = title, Content = content, Duration = dur or 3 })
    end)
end
function Y.playerNames()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then list[#list + 1] = p.Name end
    end
    table.sort(list)
    return list
end
function Y.esc(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
-- Every mover/constraint we create is tagged so the watchdog can sweep leftovers
function Y.tag(inst, owner)
    inst.Name = "Yen_" .. owner .. inst.ClassName
    inst:SetAttribute("YenOwner", owner)
    return inst
end
function Y.digitsOnly(s)
    local d = tostring(s):gsub("%D", "")
    return d
end

local UI = { Toggles = {}, Dropdowns = {} }
function Y.setToggle(key, v)
    local el = UI.Toggles[key]
    if el then pcall(function() el:Set(v) end) end
end

------------------------------------------------------------
-- Noclip manager (shared: Fling, Attach)
------------------------------------------------------------
local Noclip = { keys = {}, orig = setmetatable({}, { __mode = "k" }), conn = nil }
function Noclip.Acquire(key)
    Noclip.keys[key] = true
    if Noclip.conn then return end
    Noclip.conn = RunService.Stepped:Connect(function()
        local c = Y.getChar()
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                if Noclip.orig[p] == nil then Noclip.orig[p] = p.CanCollide end
                p.CanCollide = false
            end
        end
    end)
end
function Noclip.Release(key)
    Noclip.keys[key] = nil
    if next(Noclip.keys) ~= nil then return end
    if Noclip.conn then Noclip.conn:Disconnect(); Noclip.conn = nil end
    for p, orig in pairs(Noclip.orig) do
        if p and p.Parent then p.CanCollide = orig end
        Noclip.orig[p] = nil
    end
end

------------------------------------------------------------
-- State
------------------------------------------------------------
local State = {
    Target = nil, -- shared "selected player"

    Fly   = { Enabled = false, Speed = 50 },
    Speed = { Enabled = false, Value = 32, Mode = "WalkSpeed (Yield)", TP = 2 },
    Jump  = { Enabled = false, Power = 50, Inf = false },

    ESP   = { Enabled = false, Mode = "Aura", HP = true, Distance = true, Team = true,
              TeamCheck = false, MaxDist = 2000, Fill = 60 },
    Xray  = { Enabled = false, Transparency = 70 },

    Aim   = { Enabled = false, FOV = 150, Smooth = 25, Part = "Head", TeamCheck = true,
              WallCheck = true, ShowFOV = true, HoldRMB = not Platform.Mobile,
              Predict = true, PredictTime = 0.12, ProjSpeed = 0, PredictVertical = false,
              KillKey = "K", Mode = "Camera Lock", Active = true, Players = true, Npcs = false },

    Ultra = { Enabled = false, Delay = 0, Range = 22, Cooldown = 0.35, MinTP = 10, MaxTP = 22,
              DashSpeed = 45, Dash = true, Projectiles = true, Strict = false, Ghost = true,
              TeamCheck = true, AnimId = "", Adapt = 1 },

    Orbit = { Enabled = false, Speed = 3, Radius = 8, Height = 0 },
    Fling = { Enabled = false, All = false },
    Spin  = { Enabled = false, Speed = 20 },
    Anim  = { Id = "", Speed = 1, Looped = true, Track = nil },

    Anti  = { Freeze = true, Tolerance = 0.5, Rubber = true },

    Invis   = { Enabled = false },
    Ragdoll = { Enabled = false },
    Freeze  = { Enabled = false, Pose = true },

    TPTool   = { Given = false, Height = 3 },
    PlatTool = { Given = false, Size = 12, Thick = 1, Trans = 0.3, Follow = true },

    Attach  = { HeadOffset = 1.4, HangDist = 1.15, CapeDist = 0.85 },

    Weather = { Name = "Clear", Intensity = 60 },
    RTX     = { Enabled = false, Quality = "Medium" },

    Bundle  = { Id = "", Parts = { "All" }, Keep = true, Slots = nil },
    NoclipU = { Enabled = false },
    Cam     = { Mode = "Default", Distance = 12 },
    FakeLag = { Enabled = false, Interval = 0.7, Duration = 0.35 },
    Points  = { Esp = false, Delay = 0.8, Loop = false, Route = {}, Selected = nil },
    Npc     = { List = {}, Partial = false, Drain = false, DrainRate = 25, LoopDelete = false, Fling = false },
    NoFog   = { Enabled = false },
    NoDark  = { Enabled = false },
    FullBright = { Enabled = false },
}

local defaultWalkSpeed, defaultJumpPower, defaultJumpHeight = 16, 50, 7.2
do
    local h = Y.getHum()
    if h then
        if h.WalkSpeed >= 1 then defaultWalkSpeed = h.WalkSpeed end
        if h.JumpPower >= 1 then defaultJumpPower = h.JumpPower end
        if h.JumpHeight >= 0.5 then defaultJumpHeight = h.JumpHeight end
    end
end

-- Text-box helper (replaces every slider)
function Y.NumBox(tab, title, default, lo, hi, apply, isInt)
    return tab:Input({
        Title = title,
        Desc = "Type a number (" .. tostring(lo) .. " to " .. tostring(hi) .. ")",
        Value = tostring(default),
        Placeholder = tostring(default),
        Callback = function(txt)
            local n = tonumber(txt)
            if not n then Y.notify(title, "Please type a number.", 2); return end
            if isInt then n = math.floor(n + 0.5) end
            local c = math.clamp(n, lo, hi)
            if c ~= n then Y.notify(title, "Clamped to " .. tostring(c), 2) end
            apply(c)
        end,
    })
end

function Y.Toggle(tab, key, title, initial, cb, desc)
    local el = tab:Toggle({ Title = title, Desc = desc, Value = initial, Callback = cb })
    if key then UI.Toggles[key] = el end
    return el
end

------------------------------------------------------------
-- PERSISTENCE (saved IDs + saved teleport points)
------------------------------------------------------------
local HttpService = game:GetService("HttpService")
local SAVE_DIR  = "Yenrenuton"
local SAVE_FILE = SAVE_DIR .. "/saved.json"
local Saved = { bundle = {}, emote = {}, dodge = {}, points = {} }

function Y.loadSaved()
    if not (isfile and readfile) then return end
    pcall(function()
        if isfile(SAVE_FILE) then
            local data = HttpService:JSONDecode(readfile(SAVE_FILE))
            if type(data) == "table" then
                for k in pairs(Saved) do
                    if type(data[k]) == "table" then Saved[k] = data[k] end
                end
            end
        end
    end)
end

function Y.writeSaved()
    if not writefile then return false end
    local ok = pcall(function()
        if makefolder and isfolder and not isfolder(SAVE_DIR) then makefolder(SAVE_DIR) end
        writefile(SAVE_FILE, HttpService:JSONEncode(Saved))
    end)
    return ok
end
Y.loadSaved()

function Y.savedLabel(e) return tostring(e.name) .. " [" .. tostring(e.id) .. "]" end
function Y.savedLabels(kind)
    local out = {}
    for _, e in ipairs(Saved[kind]) do out[#out + 1] = Y.savedLabel(e) end
    return out
end

-- Reusable "save the ID so I don't have to type it again" UI
function Y.SavedListUI(tab, kind, title, getId, onUse)
    local selected, nameDraft, dd = nil, "", nil
    tab:Input({ Title = title .. " save name (optional)", Placeholder = "label for the save",
        Callback = function(v) nameDraft = v or "" end })
    tab:Button({ Title = "Save " .. title .. " ID", Callback = function()
        local id = Y.digitsOnly(getId() or "")
        if id == "" then return Y.notify(title, "Type an ID first.", 3) end
        for _, e in ipairs(Saved[kind]) do
            if tostring(e.id) == id then return Y.notify(title, "That ID is already saved.", 2) end
        end
        local name = (nameDraft ~= "") and nameDraft or ("ID " .. id)
        Saved[kind][#Saved[kind] + 1] = { name = name, id = id }
        local ok = Y.writeSaved()
        pcall(function() dd:Refresh(Y.savedLabels(kind)) end)
        Y.notify(title, ok and "Saved." or "Saved for this session (executor can't write files).", 3)
    end })
    dd = tab:Dropdown({ Title = title .. " saved list", Values = Y.savedLabels(kind),
        Callback = function(v) selected = v end })
    tab:Button({ Title = "Use selected " .. title, Callback = function()
        for _, e in ipairs(Saved[kind]) do
            if Y.savedLabel(e) == selected then return onUse(tostring(e.id), e) end
        end
        Y.notify(title, "Pick a saved entry first.", 3)
    end })
    tab:Button({ Title = "Delete selected " .. title, Callback = function()
        for i, e in ipairs(Saved[kind]) do
            if Y.savedLabel(e) == selected then
                table.remove(Saved[kind], i)
                Y.writeSaved()
                selected = nil
                pcall(function() dd:Refresh(Y.savedLabels(kind)) end)
                return Y.notify(title, "Deleted.", 2)
            end
        end
        Y.notify(title, "Pick a saved entry first.", 3)
    end })
end

------------------------------------------------------------
-- Control vector (same source Infinite Yield uses for mobile fly)
------------------------------------------------------------
local ControlModule
function Y.getMoveVector()
    if not ControlModule then
        pcall(function()
            local pm = LocalPlayer:WaitForChild("PlayerScripts", 2):WaitForChild("PlayerModule", 2)
            ControlModule = require(pm:WaitForChild("ControlModule", 2))
        end)
    end
    if ControlModule then
        local ok, v = pcall(function() return ControlModule:GetMoveVector() end)
        if ok and typeof(v) == "Vector3" then return v end
    end
    local x = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
    local z = (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
    return Vector3.new(x, 0, z)
end

------------------------------------------------------------
-- MOBILE FLY PAD (up / down)
------------------------------------------------------------
local MobileFly = { Up = false, Down = false, Gui = nil }

function Y.makeFlyPad()
    if MobileFly.Gui then return end
    local sg = Instance.new("ScreenGui")
    sg.Name = "YenFlyPad"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 999
    sg.Enabled = false
    sg.Parent = Y.guiParent()

    local function mk(text, yScale, flag)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(62, 62)
        b.AnchorPoint = Vector2.new(1, 0.5)
        b.Position = UDim2.new(1, -24, yScale, 0)
        b.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
        b.BackgroundTransparency = 0.25
        b.Text = text
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 26
        b.AutoButtonColor = true
        b.Parent = sg
        Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
        local st = Instance.new("UIStroke", b)
        st.Color = Color3.fromRGB(120, 140, 255); st.Thickness = 2
        b.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                MobileFly[flag] = true
            end
        end)
        b.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                MobileFly[flag] = false
            end
        end)
    end
    mk("▲", 0.50, "Up")
    mk("▼", 0.64, "Down")
    MobileFly.Gui = sg
    MainMaid:Give(sg)
end

function Y.setFlyPad(visible)
    if not Platform.Touch then return end
    Y.makeFlyPad()
    MobileFly.Gui.Enabled = visible
    if not visible then MobileFly.Up, MobileFly.Down = false, false end
end

------------------------------------------------------------
-- FLY  (Infinite Yield method: BodyGyro + BodyVelocity + PlatformStand)
------------------------------------------------------------
function Y.stopFly()
    Y.fmaid("Fly"):Destroy()
    Y.setFlyPad(false)
    local h = Y.getHum()
    if h then h.PlatformStand = false end
    pcall(function() Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
end

function Y.startFly()
    Y.stopFly()
    local root, hum = Y.getRoot(), Y.getHum()
    if not (root and hum) or hum.Health <= 0 then return end
    local m = Y.fmaid("Fly")

    local bg = Y.tag(Instance.new("BodyGyro"), "Fly")
    bg.P = 9e4
    bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bg.CFrame = root.CFrame
    bg.Parent = root
    m:Give(bg)

    local bv = Y.tag(Instance.new("BodyVelocity"), "Fly")
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bv.Velocity = Vector3.zero
    bv.Parent = root
    m:Give(bv)

    Y.setFlyPad(true)

    m:Give(RunService.RenderStepped:Connect(function()
        if not (root.Parent and hum.Parent) or hum.Health <= 0 then return Y.stopFly() end
        hum.PlatformStand = true
        local cam = Workspace.CurrentCamera
        local mv = Y.getMoveVector()
        local up = 0
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E)
            or MobileFly.Up then up = up + 1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q)
            or MobileFly.Down then up = up - 1 end
        local dir = cam.CFrame.RightVector * mv.X + cam.CFrame.LookVector * -mv.Z + Vector3.new(0, up, 0)
        if dir.Magnitude > 1 then dir = dir.Unit end
        bv.Velocity = dir * State.Fly.Speed
        bg.CFrame = cam.CFrame
    end))
end

------------------------------------------------------------
-- SPEED  (Yield: WalkSpeed property loop | TPWalk)
------------------------------------------------------------
function Y.stopSpeed()
    Y.fmaid("Speed"):Destroy()
    local h = Y.getHum()
    if h then h.WalkSpeed = defaultWalkSpeed end
end

function Y.startSpeed()
    Y.stopSpeed()
    local h0 = Y.getHum()
    if h0 and h0.WalkSpeed >= 1 then defaultWalkSpeed = h0.WalkSpeed end
    local m = Y.fmaid("Speed")

    if State.Speed.Mode == "WalkSpeed (Yield)" then
        local function apply()
            local h = Y.getHum()
            if h and h.WalkSpeed ~= State.Speed.Value then h.WalkSpeed = State.Speed.Value end
        end
        apply()
        m:Give(RunService.Heartbeat:Connect(apply))
        if h0 then m:Give(h0:GetPropertyChangedSignal("WalkSpeed"):Connect(apply)) end
    else
        -- TPWalk (Yield): translate the character along MoveDirection
        m:Give(RunService.Heartbeat:Connect(function(dt)
            local c, h = Y.getChar(), Y.getHum()
            if c and h and h.Health > 0 and h.MoveDirection.Magnitude > 0 and not State.Fly.Enabled then
                c:TranslateBy(h.MoveDirection * State.Speed.TP * dt * 10)
            end
        end))
    end
end

------------------------------------------------------------
-- JUMP POWER  (Yield: JumpPower / JumpHeight depending on UseJumpPower)
------------------------------------------------------------
function Y.jumpApply(h)
    if h.UseJumpPower then
        if h.JumpPower ~= State.Jump.Power then h.JumpPower = State.Jump.Power end
    else
        if h.JumpHeight ~= State.Jump.Power then h.JumpHeight = State.Jump.Power end
    end
end

function Y.stopJump()
    Y.fmaid("Jump"):Destroy()
    local h = Y.getHum()
    if h then
        if h.UseJumpPower then h.JumpPower = defaultJumpPower else h.JumpHeight = defaultJumpHeight end
    end
end

function Y.startJump()
    Y.stopJump()
    local h0 = Y.getHum()
    if h0 then
        if h0.JumpPower >= 1 then defaultJumpPower = h0.JumpPower end
        if h0.JumpHeight >= 0.5 then defaultJumpHeight = h0.JumpHeight end
    end
    local m = Y.fmaid("Jump")
    local function apply() local h = Y.getHum(); if h then Y.jumpApply(h) end end
    apply()
    m:Give(RunService.Heartbeat:Connect(apply))
    if h0 then
        m:Give(h0:GetPropertyChangedSignal("JumpPower"):Connect(apply))
        m:Give(h0:GetPropertyChangedSignal("JumpHeight"):Connect(apply))
        m:Give(h0:GetPropertyChangedSignal("UseJumpPower"):Connect(apply))
    end
end

function Y.setInfJump(on)
    State.Jump.Inf = on
    if not on then Y.fmaid("InfJump"):Destroy(); return end
    Y.fmaid("InfJump"):Give(UserInputService.JumpRequest:Connect(function()
        local h = Y.getHum()
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end))
end

------------------------------------------------------------
-- ESP  (Aura | Box | Both  +  HP | Distance | Team label)
------------------------------------------------------------
local ESPObjects = {}

function Y.clearESP(plr)
    local o = ESPObjects[plr]
    if o then
        if o.hl then o.hl:Destroy() end
        if o.box then o.box:Destroy() end
        if o.gui then o.gui:Destroy() end
        ESPObjects[plr] = nil
    end
end

function Y.buildESP(plr)
    Y.clearESP(plr)
    local char = plr.Character
    if not char then return end
    local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    if not head then return end

    local hl = Instance.new("Highlight")
    hl.Name = "YenESPAura"
    hl.FillTransparency = State.ESP.Fill / 100
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = char
    hl.Parent = char

    local box = Instance.new("SelectionBox")
    box.Name = "YenESPBox"
    box.Adornee = char
    box.LineThickness = 0.035
    box.SurfaceTransparency = 0.88
    box.Parent = char

    local gui = Instance.new("BillboardGui")
    gui.Name = "YenESPGui"
    gui.Adornee = head
    gui.AlwaysOnTop = true
    gui.Size = UDim2.fromOffset(160, 54)
    gui.StudsOffset = Vector3.new(0, 3.2, 0)
    gui.Parent = char

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = Platform.Mobile and 12 or 13
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.3
    label.RichText = true
    label.Text = ""
    label.Parent = gui

    ESPObjects[plr] = { hl = hl, box = box, gui = gui, label = label }
end

function Y.updateESP()
    local myRoot = Y.getRoot()
    local mode = State.ESP.Mode
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local o = ESPObjects[plr]
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")

            if not (hum and root and hum.Health > 0)
                or (State.ESP.TeamCheck and Y.sameTeam(plr)) then
                if o then Y.clearESP(plr) end
            else
                if not o or not o.hl.Parent then Y.buildESP(plr); o = ESPObjects[plr] end
                if o then
                    local dist = myRoot and (myRoot.Position - root.Position).Magnitude or 0
                    local visible = dist <= State.ESP.MaxDist
                    local color = plr.Team and plr.TeamColor.Color or Color3.fromRGB(255, 70, 70)

                    o.hl.Enabled = visible and (mode == "Aura" or mode == "Both")
                    o.hl.FillColor = color
                    o.hl.OutlineColor = color
                    o.hl.FillTransparency = State.ESP.Fill / 100

                    o.box.Visible = visible and (mode == "Box" or mode == "Both")
                    o.box.Color3 = color
                    o.box.SurfaceColor3 = color

                    local lines = { string.format("<b>%s</b>", Y.esc(plr.DisplayName)) }
                    if State.ESP.HP then
                        local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                        local c = Color3.fromHSV(pct * 0.33, 1, 1)
                        lines[#lines + 1] = string.format('<font color="#%s">HP: %d/%d</font>',
                            c:ToHex(), math.floor(hum.Health), math.floor(hum.MaxHealth))
                    end
                    if State.ESP.Distance then
                        lines[#lines + 1] = string.format("Dist: %dm", math.floor(dist))
                    end
                    if State.ESP.Team then
                        lines[#lines + 1] = string.format('<font color="#%s">Team: %s</font>',
                            color:ToHex(), Y.esc(plr.Team and plr.Team.Name or "None"))
                    end
                    o.gui.Enabled = visible
                    o.label.Text = table.concat(lines, "\n")
                    o.gui.Size = UDim2.fromOffset(160, 14 * #lines + 6)
                end
            end
        end
    end
end

function Y.startESP()
    local m = Y.fmaid("ESP")
    m:Give(RunService.Heartbeat:Connect(Y.updateESP))
    m:Give(Players.PlayerRemoving:Connect(Y.clearESP))
    m:Give(function() for p in pairs(ESPObjects) do Y.clearESP(p) end end)
end
function Y.stopESP() Y.fmaid("ESP"):Destroy() end

------------------------------------------------------------
-- X-RAY (1-100)
------------------------------------------------------------
local XrayOriginals = setmetatable({}, { __mode = "k" })

function Y.applyXray(part)
    if not part:IsA("BasePart") or Y.isCharacterPart(part) then return end
    if XrayOriginals[part] == nil then XrayOriginals[part] = part.Transparency end
    part.Transparency = math.max(XrayOriginals[part], State.Xray.Transparency / 100)
end

function Y.stopXray()
    Y.fmaid("Xray"):Destroy()
    for part, orig in pairs(XrayOriginals) do
        if part and part.Parent then part.Transparency = orig end
        XrayOriginals[part] = nil
    end
end

function Y.startXray()
    Y.stopXray()
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("BasePart") then Y.applyXray(d) end
    end
    Y.fmaid("Xray"):Give(Workspace.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then task.defer(Y.applyXray, d) end
    end))
end

------------------------------------------------------------
-- NPC SYSTEM  (name list -> aimbot target / fling / delete / drain)
-- NOTE: NPCs are simulated by the server. Kill / delete / fling only replicate
-- to other players when your client owns that NPC's physics. Otherwise the
-- effect is local to you.
------------------------------------------------------------
local NpcCache = { list = {}, last = 0 }

function Y.npcMatches(name)
    local n = tostring(name):lower()
    for _, entry in ipairs(State.Npc.List) do
        local e = tostring(entry):lower()
        if State.Npc.Partial then
            if n:find(e, 1, true) then return true end
        elseif n == e then
            return true
        end
    end
    return false
end

function Y.npcRoot(obj)
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
end

function Y.npcAlive(obj)
    local h = obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid")
    if h then return h.Health > 0 end
    return obj.Parent ~= nil
end

function Y.scanNpcs()
    local found = {}
    if #State.Npc.List > 0 then
        local myChar = Y.getChar()
        for _, d in ipairs(Workspace:GetDescendants()) do
            if (d:IsA("Model") or d:IsA("BasePart")) and Y.npcMatches(d.Name) then
                local par = d.Parent
                local pm = par and (par:IsA("Model") and par or par:FindFirstAncestorOfClass("Model"))
                local dupe = pm ~= nil and Y.npcMatches(pm.Name)
                local mine = myChar ~= nil and (d == myChar or d:IsDescendantOf(myChar))
                if not dupe and not mine and not (d:IsA("Model") and Players:GetPlayerFromCharacter(d)) and Y.npcRoot(d) then
                    found[#found + 1] = d
                end
            end
        end
    end
    NpcCache.list = found
    NpcCache.last = os.clock()
    return found
end

function Y.getNpcs(maxAge)
    if os.clock() - NpcCache.last > (maxAge or 1.5) then Y.scanNpcs() end
    return NpcCache.list
end

local lastClaim = 0
function Y.claimPhysics()
    if os.clock() - lastClaim < 1 then return end
    lastClaim = os.clock()
    pcall(function() sethiddenproperty(LocalPlayer, "SimulationRadius", 1e9) end)
    pcall(function() sethiddenproperty(LocalPlayer, "MaximumSimulationRadius", 1e9) end)
end

function Y.npcListRefresh()
    NpcCache.last = 0
    if UI.Dropdowns.Npc then pcall(function() UI.Dropdowns.Npc:Refresh(State.Npc.List) end) end
end

function Y.addNpcName(name)
    name = (tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if name == "" then return Y.notify("NPC", "Type a name first.", 3) end
    for _, e in ipairs(State.Npc.List) do
        if e:lower() == name:lower() then return Y.notify("NPC", "Already in the list.", 2) end
    end
    State.Npc.List[#State.Npc.List + 1] = name
    Y.npcListRefresh()
    Y.notify("NPC", "Added: " .. name, 2)
end

function Y.removeNpcName(name)
    for i, e in ipairs(State.Npc.List) do
        if e == name then
            table.remove(State.Npc.List, i)
            Y.npcListRefresh()
            return Y.notify("NPC", "Removed: " .. name, 2)
        end
    end
    Y.notify("NPC", "Pick a name from the list first.", 3)
end

function Y.scanNearbyNames(radius)
    local r = Y.getRoot()
    if not r then return Y.notify("NPC", "No character found.") end
    local added = 0
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Model") and d:FindFirstChildOfClass("Humanoid") and not Players:GetPlayerFromCharacter(d) then
            local rr = d:FindFirstChild("HumanoidRootPart") or d.PrimaryPart
            if rr and (rr.Position - r.Position).Magnitude <= radius then
                local known = false
                for _, e in ipairs(State.Npc.List) do if e:lower() == d.Name:lower() then known = true; break end end
                if not known then State.Npc.List[#State.Npc.List + 1] = d.Name; added = added + 1 end
            end
        end
    end
    Y.npcListRefresh()
    Y.notify("NPC", added > 0 and ("Added " .. added .. " nearby name(s).") or "No new NPC names within " .. radius .. " studs.", 4)
end

function Y.killNpcs()
    Y.claimPhysics()
    local n = 0
    for _, npc in ipairs(Y.scanNpcs()) do
        local h = npc:IsA("Model") and npc:FindFirstChildOfClass("Humanoid")
        if h then pcall(function() h.Health = 0 end) end
        pcall(function() npc:BreakJoints() end)
        n = n + 1
    end
    Y.notify("NPC", n > 0 and ("Killed " .. n .. " NPC(s).") or "No NPC from your list was found.", 4)
end

function Y.deleteNpcs(silent)
    Y.claimPhysics()
    local n = 0
    for _, npc in ipairs(Y.scanNpcs()) do
        pcall(function() npc:BreakJoints() end)
        pcall(function() npc:Destroy() end)
        n = n + 1
    end
    if not silent then
        Y.notify("NPC", n > 0 and ("Deleted " .. n .. " NPC(s).") or "No NPC from your list was found.", 4)
    end
    return n
end

function Y.setLoopDelete(on)
    State.Npc.LoopDelete = on
    Y.fmaid("NpcDelete"):Destroy()
    if not on then return end
    local acc = 0
    Y.fmaid("NpcDelete"):Give(RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        Y.deleteNpcs(true)
    end))
end

function Y.setDrain(on)
    State.Npc.Drain = on
    Y.fmaid("NpcDrain"):Destroy()
    if not on then return end
    Y.fmaid("NpcDrain"):Give(RunService.Heartbeat:Connect(function(dt)
        Y.claimPhysics()
        for _, npc in ipairs(Y.getNpcs(1)) do
            local h = npc:IsA("Model") and npc:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
                local nh = math.max(0, h.Health - State.Npc.DrainRate * dt)
                pcall(function() h.Health = nh end)
                if nh <= 0 then pcall(function() npc:BreakJoints() end) end
            end
        end
    end))
end

local npcFlingOrigin
function Y.stopFlingNpc()
    Y.fmaid("FlingNpc"):Destroy()
    Noclip.Release("FlingNpc")
    local r = Y.getRoot()
    if r then
        r.AssemblyAngularVelocity = Vector3.zero
        r.AssemblyLinearVelocity = Vector3.zero
        if npcFlingOrigin then r.CFrame = npcFlingOrigin end
    end
    npcFlingOrigin = nil
end

function Y.startFlingNpc()
    Y.stopFlingNpc()
    local r0 = Y.getRoot()
    if not r0 then return end
    npcFlingOrigin = r0.CFrame
    Noclip.Acquire("FlingNpc")
    Y.fmaid("FlingNpc"):Give(RunService.Heartbeat:Connect(function()
        local root = Y.getRoot()
        if not root then return end
        Y.claimPhysics()
        local alive = {}
        for _, n in ipairs(Y.getNpcs(1)) do
            if n.Parent and Y.npcAlive(n) and Y.npcRoot(n) then alive[#alive + 1] = n end
        end
        local npc = alive[(math.floor(os.clock() * 4) % math.max(#alive, 1)) + 1]
        if npc then
            root.CFrame = Y.npcRoot(npc).CFrame
            root.AssemblyLinearVelocity = Vector3.new(9e5, 9e5, 9e5)
            root.AssemblyAngularVelocity = Vector3.new(0, 9e5, 0)
        end
    end))
end

------------------------------------------------------------
-- AIMBOT (Camera Lock / Non-Camera Lock, prediction, NPC targets, draggable switch)
------------------------------------------------------------
local FOVCircle
pcall(function()
    FOVCircle = Drawing.new("Circle")
    FOVCircle.Thickness = 1.5
    FOVCircle.NumSides = 64
    FOVCircle.Filled = false
    FOVCircle.Transparency = 1
    FOVCircle.Color = Color3.fromRGB(255, 255, 255)
    FOVCircle.Visible = false
    MainMaid:Give(function() FOVCircle:Remove() end)
end)

local LocalMouse = LocalPlayer:GetMouse()

function Y.aimCenter()
    if Platform.Mobile then return Camera.ViewportSize / 2 end
    return UserInputService:GetMouseLocation()
end

function Y.hasLineOfSight(fromPos, part, owner)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { Y.getChar(), Camera }
    local result = Workspace:Raycast(fromPos, part.Position - fromPos, params)
    return result == nil or result.Instance == part or result.Instance:IsDescendantOf(owner)
end

-- smoothed velocity per target (players and NPCs)
local PredTrack = setmetatable({}, { __mode = "k" })
function Y.trackObj(key, r, dt)
    local t = PredTrack[key]
    if not t or t.root ~= r then
        PredTrack[key] = { root = r, last = r.Position, vel = Vector3.zero }
    else
        if dt > 0 then
            local inst = (r.Position - t.last) / dt
            if inst.Magnitude > 400 then inst = Vector3.zero end
            t.vel = t.vel:Lerp(inst, 0.35)
        end
        t.last = r.Position
    end
end

function Y.updateTracks(dt)
    if State.Aim.Players then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local c = plr.Character
                local r = c and c:FindFirstChild("HumanoidRootPart")
                if r then Y.trackObj(plr, r, dt) end
            end
        end
    end
    if State.Aim.Npcs then
        for _, npc in ipairs(Y.getNpcs(1)) do
            local r = npc.Parent and Y.npcRoot(npc)
            if r then Y.trackObj(npc, r, dt) end
        end
    end
end

-- Leads the target. Moving sideways / backing away -> aim ahead of their movement.
-- Running toward you -> normal aim (only sideways lead is kept).
function Y.aimPoint(key, part)
    local pos = part.Position
    if not State.Aim.Predict then return pos end
    local tr = PredTrack[key]
    if not tr then return pos end
    local vel = tr.vel
    if not State.Aim.PredictVertical then vel = Vector3.new(vel.X, 0, vel.Z) end

    local to = pos - Camera.CFrame.Position
    local dist = to.Magnitude
    if dist < 1 then return pos end
    local dir = to / dist

    local radial = vel:Dot(dir)            -- > 0: moving away from you
    local lateral = vel - dir * radial
    local t = (State.Aim.ProjSpeed > 0) and (dist / State.Aim.ProjSpeed) or State.Aim.PredictTime

    local lead
    if radial > 0 then lead = vel * t else lead = lateral * t end
    return pos + lead
end

function Y.getAimTarget()
    local center = Y.aimCenter()
    local best = { dist = nil, part = nil, point = nil }

    local function consider(key, part, owner)
        local pt = Y.aimPoint(key, part)
        local sp, on = Camera:WorldToViewportPoint(pt)
        if not on then return end
        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
        if d > State.Aim.FOV then return end
        if best.dist and d >= best.dist then return end
        if State.Aim.WallCheck and not Y.hasLineOfSight(Camera.CFrame.Position, part, owner) then return end
        best.dist, best.part, best.point = d, part, pt
    end

    if State.Aim.Players then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and Y.isAlive(plr) and not (State.Aim.TeamCheck and Y.sameTeam(plr)) then
                local part = plr.Character:FindFirstChild(State.Aim.Part)
                    or plr.Character:FindFirstChild("HumanoidRootPart")
                if part and part:IsA("BasePart") then consider(plr, part, plr.Character) end
            end
        end
    end
    if State.Aim.Npcs then
        for _, npc in ipairs(Y.getNpcs(1)) do
            if npc.Parent and Y.npcAlive(npc) then
                local part = npc:IsA("Model") and npc:FindFirstChild(State.Aim.Part) or nil
                if not (part and part:IsA("BasePart")) then part = Y.npcRoot(npc) end
                if part and part:IsA("BasePart") then consider(npc, part, npc) end
            end
        end
    end
    return best.part, best.point
end

-- Non-Camera Lock: the camera is never touched. Mouse.Hit / Mouse.Target and
-- the rays a game fires from your camera or character are redirected to the target.
local Hooks = { alive = true, installed = false }
local SilentPoint, SilentPart = nil, nil

function Y.silentSupported()
    return hookmetamethod ~= nil and getnamecallmethod ~= nil and newcclosure ~= nil and checkcaller ~= nil
end

function Y.silentActive()
    return Hooks.alive and SilentPoint ~= nil and State.Aim.Enabled and State.Aim.Active
        and State.Aim.Mode == "Non-Camera Lock"
end

function Y.installSilentHooks()
    if Hooks.installed then return true end
    if not Y.silentSupported() then return false end
    local ok = pcall(function()
        local oldIndex
        oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
            if (key == "Hit" or key == "Target") and self == LocalMouse and Y.silentActive() and not checkcaller() then
                if key == "Hit" then return CFrame.new(SilentPoint) end
                return SilentPart
            end
            return oldIndex(self, key)
        end))

        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if Y.silentActive() and not checkcaller() then
                local method = getnamecallmethod()
                if self == Workspace then
                    if method == "Raycast" then
                        local args = { ... }
                        local origin, dir = args[1], args[2]
                        if typeof(origin) == "Vector3" and typeof(dir) == "Vector3" then
                            args[2] = (SilentPoint - origin).Unit * dir.Magnitude
                            return oldNamecall(self, unpack(args))
                        end
                    elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList"
                        or method == "FindPartOnRayWithWhitelist" then
                        local args = { ... }
                        local ray = args[1]
                        if typeof(ray) == "Ray" then
                            args[1] = Ray.new(ray.Origin, (SilentPoint - ray.Origin).Unit * ray.Direction.Magnitude)
                            return oldNamecall(self, unpack(args))
                        end
                    end
                elseif self == Camera and (method == "ViewportPointToRay" or method == "ScreenPointToRay") then
                    local o = Camera.CFrame.Position
                    return Ray.new(o, (SilentPoint - o).Unit)
                end
            end
            return oldNamecall(self, ...)
        end))
    end)
    Hooks.installed = ok
    return ok
end

-- draggable on/off switch
local AimButton
function Y.refreshAimButton()
    if not AimButton then return end
    local on = State.Aim.Active
    AimButton.Button.Text = on and "AIMBOT: ON\ntap = off" or "AIMBOT: OFF\ntap = on"
    AimButton.Button.BackgroundColor3 = on and Color3.fromRGB(30, 140, 70) or Color3.fromRGB(150, 30, 40)
end

function Y.setAimActive(v)
    State.Aim.Active = v
    if not v then SilentPoint, SilentPart = nil, nil end
    if FOVCircle and not v then FOVCircle.Visible = false end
    Y.refreshAimButton()
end

function Y.ensureAimButton()
    if AimButton then return end
    local sg = Instance.new("ScreenGui")
    sg.Name = "YenAimSwitch"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 1001
    sg.Enabled = false
    sg.Parent = Y.guiParent()

    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(Platform.Mobile and 132 or 122, Platform.Mobile and 46 or 40)
    b.AnchorPoint = Vector2.new(1, 0)
    b.Position = UDim2.new(1, -16, 0, 70)
    b.BackgroundTransparency = 0.1
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.AutoButtonColor = false
    b.Parent = sg
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
    local st = Instance.new("UIStroke", b)
    st.Color = Color3.fromRGB(255, 255, 255); st.Thickness = 1.5; st.Transparency = 0.4

    AimButton = { Gui = sg, Button = b }
    MainMaid:Give(sg)
    Y.refreshAimButton()

    local dragging, dragStart, startPos, moved = false, nil, nil, false
    b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart, startPos = input.Position, b.Position
        end
    end)
    MainMaid:Give(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            if delta.Magnitude > 6 then moved = true end
            if moved then
                b.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                                       startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end))
    MainMaid:Give(UserInputService.InputEnded:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            if not moved then Y.setAimActive(not State.Aim.Active) end
        end
    end))
end

function Y.stopAimbot(fromUi)
    State.Aim.Enabled = false
    Y.fmaid("Aim"):Destroy()
    SilentPoint, SilentPart = nil, nil
    if AimButton then AimButton.Gui.Enabled = false end
    if fromUi then Y.setToggle("Aim", false) end
end

local warnedFallback = false
function Y.startAim()
    local m = Y.fmaid("Aim")
    Y.ensureAimButton()
    AimButton.Gui.Enabled = true
    Y.refreshAimButton()
    if State.Aim.Mode == "Non-Camera Lock" then Y.installSilentHooks() end

    m:Give(RunService.RenderStepped:Connect(function(dt)
        Camera = Workspace.CurrentCamera
        Y.updateTracks(dt)
        local active = State.Aim.Active
        if FOVCircle then
            FOVCircle.Visible = active and State.Aim.ShowFOV
            FOVCircle.Radius = State.Aim.FOV
            FOVCircle.Position = Y.aimCenter()
        end
        if not active then SilentPoint, SilentPart = nil, nil; return end

        if State.Aim.Mode == "Non-Camera Lock" and Hooks.installed then
            local part, point = Y.getAimTarget()
            SilentPart, SilentPoint = part, point
            return
        end
        SilentPoint, SilentPart = nil, nil
        if State.Aim.Mode == "Non-Camera Lock" and not warnedFallback then
            warnedFallback = true
            Y.notify("Aimbot", "Executor can't hook Mouse/Raycast. Using Camera Lock instead.", 5)
        end

        if State.Aim.HoldRMB and not Platform.Mobile
            and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            return
        end
        local part, point = Y.getAimTarget()
        if part then
            local alpha = 1 - (State.Aim.Smooth / 100) * 0.95
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, point), alpha)
        end
    end))
    m:Give(function()
        if FOVCircle then FOVCircle.Visible = false end
        SilentPoint, SilentPart = nil, nil
    end)
end

-- on/off key (PC)
MainMaid:Give(UserInputService.InputBegan:Connect(function(input, processed)
    if processed or not State.Aim.Enabled then return end
    if input.UserInputType == Enum.UserInputType.Keyboard
        and input.KeyCode.Name:lower() == tostring(State.Aim.KillKey):lower() then
        Y.setAimActive(not State.Aim.Active)
        Y.notify("Aimbot", State.Aim.Active and "Switched ON." or "Switched OFF.", 2)
    end
end))

------------------------------------------------------------
-- ULTRA INSTINCTS (instant teleport dodge)
------------------------------------------------------------
local lastDodge = 0
local lastAdaptNotify = 0
local dodgeTrack

local IgnoreAnimNames = {
    "idle", "walk", "run", "jump", "fall", "climb", "swim", "sit", "pose",
    "emote", "dance", "wave", "point", "cheer", "laugh", "toolnone", "equip",
}
local ActionPriorities = {
    [Enum.AnimationPriority.Action]  = true, [Enum.AnimationPriority.Action2] = true,
    [Enum.AnimationPriority.Action3] = true, [Enum.AnimationPriority.Action4] = true,
}

function Y.afterimage(char)
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            local ghost = Instance.new("Part")
            ghost.Anchored, ghost.CanCollide, ghost.CanQuery, ghost.CanTouch = true, false, false, false
            ghost.Size = part.Size
            ghost.CFrame = part.CFrame
            ghost.Material = Enum.Material.Neon
            ghost.Color = Color3.fromRGB(190, 210, 255)
            ghost.Transparency = 0.4
            ghost.Parent = Workspace
            TweenService:Create(ghost, TweenInfo.new(0.35), { Transparency = 1 }):Play()
            task.delay(0.4, function() ghost:Destroy() end)
        end
    end
end

function Y.findSafeSpot(origin, threatPos, hum, root)
    local char = Y.getChar()
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { char }

    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances = { char }

    local rigHeight = (hum.RigType == Enum.HumanoidRigType.R6) and 3 or (hum.HipHeight + root.Size.Y / 2)
    rigHeight = rigHeight + 0.3

    local minR = math.max(4, State.Ultra.MinTP * State.Ultra.Adapt)
    local maxR = math.max(minR + 1, State.Ultra.MaxTP * State.Ultra.Adapt)

    local best, bestScore
    for _ = 1, 16 do
        local ang = math.random() * math.pi * 2
        local rad = minR + math.random() * (maxR - minR)
        local cand = origin + Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)

        local down = Workspace:Raycast(cand + Vector3.new(0, 30, 0), Vector3.new(0, -90, 0), rayParams)
        if down and down.Normal.Y > 0.6 then
            local pos = down.Position + Vector3.new(0, rigHeight, 0)
            if math.abs(pos.Y - origin.Y) < 25
                and #Workspace:GetPartBoundsInRadius(pos, 2.2, overlap) == 0 then
                local score = (pos - threatPos).Magnitude + math.random() * 6
                if not bestScore or score > bestScore then best, bestScore = pos, score end
            end
        end
    end
    return best, minR
end

function Y.performDodge(threat)
    local char, root, hum = Y.getChar(), Y.getRoot(), Y.getHum()
    if not (char and root and hum) or hum.Health <= 0 then return end
    if not threat or not threat.Parent then return end
    if os.clock() - lastDodge < State.Ultra.Cooldown then return end
    lastDodge = os.clock()

    local origin = root.Position
    local threatPos = threat.Position
    local spot, minR = Y.findSafeSpot(origin, threatPos, hum, root)
    if not spot then
        local away = (origin - threatPos) * Vector3.new(1, 0, 1)
        away = away.Magnitude > 0.1 and away.Unit or -root.CFrame.LookVector
        spot = origin + away * minR
    end

    if State.Ultra.Ghost then Y.afterimage(char) end

    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    local faceAt = Vector3.new(threatPos.X, spot.Y, threatPos.Z)
    if (faceAt - spot).Magnitude > 0.5 then
        root.CFrame = CFrame.lookAt(spot, faceAt)
    else
        root.CFrame = CFrame.new(spot)
    end

    local id = State.Ultra.AnimId
    if id ~= "" then
        pcall(function()
            local d = Y.digitsOnly(id)
            if d == "" then return end
            local anim = Instance.new("Animation")
            anim.AnimationId = "rbxassetid://" .. d
            if dodgeTrack then dodgeTrack:Stop(0.05) end
            dodgeTrack = hum:LoadAnimation(anim)
            dodgeTrack.Priority = Enum.AnimationPriority.Action4
            dodgeTrack.Looped = false
            dodgeTrack:Play(0.05)
            task.delay(0.8, function() if dodgeTrack then dodgeTrack:Stop(0.1) end end)
        end)
    end

    local moved = (spot - origin).Magnitude
    task.delay(0.25, function()
        local r = Y.getRoot()
        if not (r and State.Anti.Rubber) then return end
        if moved > 8 and (r.Position - origin).Magnitude < 4 then
            State.Ultra.Adapt = math.max(0.35, State.Ultra.Adapt * 0.7)
            if os.clock() - lastAdaptNotify > 5 then
                lastAdaptNotify = os.clock()
                Y.notify("Ultra Instincts", "Server pulled you back. Teleport range auto-reduced.", 3)
            end
        else
            State.Ultra.Adapt = math.min(1, State.Ultra.Adapt + 0.1)
        end
    end)
end

function Y.triggerDodge(src)
    if not State.Ultra.Enabled then return end
    if os.clock() - lastDodge < State.Ultra.Cooldown then return end
    local d = State.Ultra.Delay
    if d <= 0 then
        Y.performDodge(src)
    else
        task.delay(d, function() if State.Ultra.Enabled then Y.performDodge(src) end end)
    end
end

function Y.isAttackTrack(track)
    if track.Looped then return false end
    local name = (track.Name or ""):lower()
    for _, ignore in ipairs(IgnoreAnimNames) do
        if name:find(ignore, 1, true) then return false end
    end
    if State.Ultra.Strict then return ActionPriorities[track.Priority] == true end
    return track.Length <= 3
end

function Y.watchAttacker(plr)
    if plr == LocalPlayer then return end
    local m = Y.fmaid("Ultra")
    local function hook(char)
        local hum  = char:WaitForChild("Humanoid", 5)
        local root = char:WaitForChild("HumanoidRootPart", 5)
        if not (hum and root) then return end
        local animator = hum:WaitForChild("Animator", 5)
        if not animator then return end
        m:Give(animator.AnimationPlayed:Connect(function(track)
            if not State.Ultra.Enabled then return end
            if State.Ultra.TeamCheck and Y.sameTeam(plr) then return end
            local myRoot = Y.getRoot()
            if not myRoot then return end
            local to = myRoot.Position - root.Position
            local dist = to.Magnitude
            if dist > State.Ultra.Range + 6 or dist < 0.1 then return end
            if not Y.isAttackTrack(track) then return end
            local facing = root.CFrame.LookVector:Dot(to.Unit)
            if facing < (State.Ultra.Strict and 0.3 or -0.2) then return end
            Y.triggerDodge(root)
        end))
    end
    if plr.Character then task.spawn(hook, plr.Character) end
    m:Give(plr.CharacterAdded:Connect(function(c) task.spawn(hook, c) end))
end

function Y.startUltra()
    local m = Y.fmaid("Ultra")
    for _, p in ipairs(Players:GetPlayers()) do Y.watchAttacker(p) end
    m:Give(Players.PlayerAdded:Connect(Y.watchAttacker))

    m:Give(RunService.Heartbeat:Connect(function()
        if not (State.Ultra.Enabled and State.Ultra.Dash) then return end
        local myRoot = Y.getRoot()
        if not myRoot then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and Y.isAlive(plr)
                and not (State.Ultra.TeamCheck and Y.sameTeam(plr)) then
                local r = plr.Character.HumanoidRootPart
                local to = myRoot.Position - r.Position
                local dist = to.Magnitude
                if dist < State.Ultra.Range and dist > 0.5 then
                    if r.AssemblyLinearVelocity:Dot(to / dist) > State.Ultra.DashSpeed then
                        Y.triggerDodge(r)
                    end
                end
            end
        end
    end))

    m:Give(Workspace.DescendantAdded:Connect(function(d)
        if not (State.Ultra.Enabled and State.Ultra.Projectiles) then return end
        if not d:IsA("BasePart") or d.Anchored then return end
        task.defer(function()
            if not d.Parent then return end
            local myRoot, myChar = Y.getRoot(), Y.getChar()
            if not (myRoot and myChar) then return end
            if d:IsDescendantOf(myChar) or Y.isCharacterPart(d) then return end
            if d.Size.Magnitude > 14 then return end
            local to = myRoot.Position - d.Position
            local dist = to.Magnitude
            if dist < 0.5 or dist > State.Ultra.Range * 5 then return end
            local closing = d.AssemblyLinearVelocity:Dot(to / dist)
            if closing < 40 then return end
            local t = dist / closing
            if t > 1.5 then return end
            task.delay(math.max(0, t - 0.15 - State.Ultra.Delay), function()
                if State.Ultra.Enabled and d.Parent then Y.performDodge(d) end
            end)
        end)
    end))
end

------------------------------------------------------------
-- ORBIT (selected player)
------------------------------------------------------------
function Y.stopOrbit()
    Y.fmaid("Orbit"):Destroy()
    local root = Y.getRoot()
    if root then root.AssemblyLinearVelocity = Vector3.zero end
end
function Y.startOrbit()
    Y.stopOrbit()
    local angle = 0
    Y.fmaid("Orbit"):Give(RunService.Heartbeat:Connect(function(dt)
        local target = State.Target and Players:FindFirstChild(State.Target)
        local root = Y.getRoot()
        if not (target and root and Y.isAlive(target)) then return end
        local tRoot = target.Character.HumanoidRootPart
        angle = angle + dt * State.Orbit.Speed
        local offset = Vector3.new(math.cos(angle) * State.Orbit.Radius, State.Orbit.Height,
                                   math.sin(angle) * State.Orbit.Radius)
        root.CFrame = CFrame.lookAt(tRoot.Position + offset, tRoot.Position)
        root.AssemblyLinearVelocity = Vector3.zero
    end))
end

------------------------------------------------------------
-- FLING (selected player / everyone)
------------------------------------------------------------
local flingOrigin
function Y.stopFling()
    Y.fmaid("Fling"):Destroy()
    Noclip.Release("Fling")
    local root = Y.getRoot()
    if root then
        root.AssemblyAngularVelocity = Vector3.zero
        root.AssemblyLinearVelocity = Vector3.zero
        if flingOrigin then root.CFrame = flingOrigin end
    end
    flingOrigin = nil
end

function Y.startFling()
    Y.stopFling()
    local root = Y.getRoot()
    if not root then return end
    flingOrigin = root.CFrame
    Noclip.Acquire("Fling")
    Y.fmaid("Fling"):Give(RunService.Heartbeat:Connect(function()
        local r = Y.getRoot()
        if not r then return end
        local victims = {}
        if State.Fling.All then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and Y.isAlive(p) then victims[#victims + 1] = p end
            end
        elseif State.Target then
            local p = Players:FindFirstChild(State.Target)
            if p and Y.isAlive(p) then victims[1] = p end
        end
        local victim = victims[(math.floor(os.clock() * 4) % math.max(#victims, 1)) + 1]
        if victim then
            r.CFrame = victim.Character.HumanoidRootPart.CFrame
            r.AssemblyLinearVelocity = Vector3.new(9e5, 9e5, 9e5)
            r.AssemblyAngularVelocity = Vector3.new(0, 9e5, 0)
        end
    end))
end

------------------------------------------------------------
-- SPIN
------------------------------------------------------------
function Y.stopSpin() Y.fmaid("Spin"):Destroy() end
function Y.startSpin()
    Y.stopSpin()
    local root = Y.getRoot()
    if not root then return end
    local m = Y.fmaid("Spin")
    local att = Y.tag(Instance.new("Attachment"), "Spin")
    att.Parent = root
    m:Give(att)
    local av = Y.tag(Instance.new("AngularVelocity"), "Spin")
    av.Attachment0 = att
    av.MaxTorque = math.huge
    av.RelativeTo = Enum.ActuatorRelativeTo.World
    av.AngularVelocity = Vector3.new(0, State.Spin.Speed, 0)
    av.Parent = root
    m:Give(av)
    m:Give(RunService.Heartbeat:Connect(function()
        av.AngularVelocity = Vector3.new(0, State.Spin.Speed, 0)
    end))
end

------------------------------------------------------------
-- ANIMATIONS: Emote (play an ID) + Bundle / Animation Pack (replace Animate script IDs)
------------------------------------------------------------
local AssetService = game:GetService("AssetService")

function Y.classifyAnim(name)
    local n = tostring(name or ""):lower():gsub("[%s_%-]", "")
    if n:find("swimidle", 1, true) then return "Swim Idle" end
    if n:find("swim", 1, true) then return "Swim" end
    if n:find("idle", 1, true) then return "Idle" end
    if n:find("walk", 1, true) then return "Walk" end
    if n:find("run", 1, true) then return "Run" end
    if n:find("jump", 1, true) then return "Jump" end
    if n:find("fall", 1, true) then return "Fall" end
    if n:find("climb", 1, true) then return "Climb" end
    return nil
end

-- loads an asset and returns every Animation inside it
function Y.loadAnimInstances(assetId)
    local objs
    local ok = pcall(function() objs = game:GetObjects("rbxassetid://" .. tostring(assetId)) end)
    if not ok or not objs then
        pcall(function() objs = { game:GetService("InsertService"):LoadAsset(tonumber(assetId)) } end)
    end
    local out = {}
    if not objs then return out end
    for _, obj in ipairs(objs) do
        local list = obj:GetDescendants()
        list[#list + 1] = obj
        for _, d in ipairs(list) do
            if d:IsA("Animation") and d.AnimationId ~= "" then
                out[#out + 1] = { name = d.Name, parent = d.Parent and d.Parent.Name or "", id = d.AnimationId }
            end
        end
        pcall(function() obj:Destroy() end)
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Bundle ID (or a single pack asset ID) -> { Idle = {ids}, Walk = {ids}, ... }
function Y.resolveAnimPack(id)
    local slots, items, label = {}, {}, "Asset " .. id
    local okB, details = pcall(function() return AssetService:GetBundleDetailsAsync(tonumber(id)) end)
    if okB and type(details) == "table" and details.Items then
        label = details.Name or label
        for _, it in ipairs(details.Items) do
            if it.Type == "Asset" then items[#items + 1] = { id = it.Id, name = it.Name or "" } end
        end
    else
        items[1] = { id = tonumber(id), name = "" }
    end
    for _, item in ipairs(items) do
        for _, a in ipairs(Y.loadAnimInstances(item.id)) do
            local slot = Y.classifyAnim(a.parent) or Y.classifyAnim(item.name) or Y.classifyAnim(a.name)
            if slot then
                slots[slot] = slots[slot] or {}
                table.insert(slots[slot], a.id)
            end
        end
    end
    return slots, label
end

local SLOT_MAP = {
    ["Idle"]      = { "idle",     { "Animation1", "Animation2" } },
    ["Walk"]      = { "walk",     { "WalkAnim" } },
    ["Run"]       = { "run",      { "RunAnim" } },
    ["Jump"]      = { "jump",     { "JumpAnim" } },
    ["Fall"]      = { "fall",     { "FallAnim" } },
    ["Climb"]     = { "climb",    { "ClimbAnim" } },
    ["Swim"]      = { "swim",     { "Swim" } },
    ["Swim Idle"] = { "swimidle", { "SwimIdle" } },
}
local AnimBackup = setmetatable({}, { __mode = "k" }) -- Animation instance -> original id

function Y.restartAnimate(animate)
    local hum = Y.getHum()
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    animate.Disabled = true
    if animator then
        for _, t in ipairs(animator:GetPlayingAnimationTracks()) do pcall(function() t:Stop(0) end) end
    end
    task.wait(0.05)
    animate.Disabled = false
end

function Y.partsToSet(v)
    local set = {}
    if type(v) == "table" then
        for _, x in pairs(v) do set[tostring(x)] = true end
    elseif v ~= nil then
        set[tostring(v)] = true
    end
    return set
end

function Y.applyPack(slots, parts)
    local c = Y.getChar()
    local animate = c and c:FindFirstChild("Animate")
    if not animate then return nil, "This character has no Animate script." end
    local want = Y.partsToSet(parts)
    local all = want["All"] or next(want) == nil
    local equipped = {}
    for slot, map in pairs(SLOT_MAP) do
        local ids = slots[slot]
        if ids and #ids > 0 and (all or want[slot]) then
            local folder = animate:FindFirstChild(map[1])
            if folder then
                local touched = false
                for i, childName in ipairs(map[2]) do
                    local inst = folder:FindFirstChild(childName)
                    if inst and inst:IsA("Animation") then
                        if AnimBackup[inst] == nil then AnimBackup[inst] = inst.AnimationId end
                        inst.AnimationId = ids[i] or ids[1]
                        touched = true
                    end
                end
                if touched then equipped[#equipped + 1] = slot end
            end
        end
    end
    if #equipped == 0 then return nil, "Nothing matched the parts you picked." end
    Y.restartAnimate(animate)
    return equipped
end

function Y.equipPack()
    local id = Y.digitsOnly(State.Bundle.Id)
    if id == "" then return Y.notify("Animation Pack", "Place a Bundle / pack ID first.", 3) end
    task.spawn(function()
        Y.notify("Animation Pack", "Loading pack...", 2)
        local slots, label = Y.resolveAnimPack(id)
        if not slots or next(slots) == nil then
            return Y.notify("Animation Pack", "Couldn't read animations from that ID. Check the ID, or your executor may lack game:GetObjects.", 6)
        end
        State.Bundle.Slots = slots
        local equipped, err = Y.applyPack(slots, State.Bundle.Parts)
        if not equipped then return Y.notify("Animation Pack", err, 4) end
        Y.notify("Animation Pack", label .. ": " .. table.concat(equipped, ", "), 5)
    end)
end

function Y.resetPack()
    local c = Y.getChar()
    local animate = c and c:FindFirstChild("Animate")
    State.Bundle.Slots = nil
    if not animate then return end
    for inst, orig in pairs(AnimBackup) do
        if inst.Parent then inst.AnimationId = orig end
        AnimBackup[inst] = nil
    end
    task.spawn(function() Y.restartAnimate(animate) end)
    Y.notify("Animation Pack", "Back to your default animations.", 3)
end

-- Emote: play an animation / emote ID
function Y.stopAnim()
    if State.Anim.Track then
        pcall(function() State.Anim.Track:Stop(0.1); State.Anim.Track:Destroy() end)
        State.Anim.Track = nil
    end
end

function Y.playAnim()
    Y.stopAnim()
    local hum = Y.getHum()
    local d = Y.digitsOnly(State.Anim.Id)
    if not hum then return Y.notify("Emote", "No character found.") end
    if d == "" then return Y.notify("Emote", "Place an emote ID first.") end
    task.spawn(function()
        local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
        local function try(idStr)
            local anim = Instance.new("Animation")
            anim.AnimationId = idStr
            local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
            if not ok or not track then return nil end
            local t0 = os.clock()
            repeat task.wait(0.05) until track.Length > 0 or os.clock() - t0 > 1.5
            if track.Length <= 0 then pcall(function() track:Destroy() end); return nil end
            return track
        end
        local track = try("rbxassetid://" .. d)
        if not track then
            -- catalog emote / pack asset IDs: unwrap the real Animation inside
            for _, a in ipairs(Y.loadAnimInstances(d)) do
                track = try(a.id)
                if track then break end
            end
        end
        if not track then
            return Y.notify("Emote", "Couldn't load that ID (needs an animation or emote asset ID).", 5)
        end
        track.Priority = Enum.AnimationPriority.Action4
        track.Looped = State.Anim.Looped
        track:Play(0.1, 1, State.Anim.Speed)
        State.Anim.Track = track
    end)
end

------------------------------------------------------------
-- ATTACH ENGINE: Headsit / Cape / Hang on back  (selected player, FE)
-- Your own character is positioned every frame, so the server replicates
-- the position and everyone sees it.
------------------------------------------------------------
local Attach = { Mode = nil }

function Y.stopAttach()
    Y.fmaid("Attach"):Destroy()
    Noclip.Release("Attach")
    local h, r = Y.getHum(), Y.getRoot()
    if h then h.Sit = false; h.PlatformStand = false end
    if r then
        r.AssemblyLinearVelocity = Vector3.zero
        r.AssemblyAngularVelocity = Vector3.zero
    end
    Attach.Mode = nil
end

function Y.startAttach(mode)
    Y.stopAttach()
    if not State.Target then
        Y.notify(mode, "Pick a selected player first.", 3)
        return false
    end
    Attach.Mode = mode
    Noclip.Acquire("Attach")
    local m = Y.fmaid("Attach")
    local t0 = os.clock()

    m:Give(RunService.Heartbeat:Connect(function()
        local r, h = Y.getRoot(), Y.getHum()
        local tp = State.Target and Players:FindFirstChild(State.Target)
        local tc = tp and tp.Character
        local tr = tc and tc:FindFirstChild("HumanoidRootPart")
        if not (r and h and tr) then return end

        r.AssemblyLinearVelocity = Vector3.zero
        r.AssemblyAngularVelocity = Vector3.zero

        local rot = tr.CFrame - tr.CFrame.Position
        local cf
        if mode == "Headsit" then
            h.Sit = true
            local head = tc:FindFirstChild("Head") or tr
            local p = head.Position + Vector3.new(0, head.Size.Y / 2 + State.Attach.HeadOffset, 0)
            cf = CFrame.new(p) * rot
        elseif mode == "Hang" then
            h.Sit = true
            cf = tr.CFrame * CFrame.new(0, 0.25, State.Attach.HangDist) * CFrame.Angles(math.rad(-12), 0, 0)
        else -- Cape
            h.PlatformStand = true
            local speedFactor = math.clamp(tr.AssemblyLinearVelocity.Magnitude / 16 * 14, 0, 38)
            local sway = 8 + speedFactor + math.sin((os.clock() - t0) * 2.6) * 4
            cf = tr.CFrame * CFrame.new(0, 1.1, State.Attach.CapeDist)
                * CFrame.Angles(-math.rad(sway), 0, 0) * CFrame.new(0, -2, 0)
        end
        r.CFrame = cf
    end))
    return true
end

function Y.attachToggle(mode, key, v)
    if v then
        for k, _ in pairs({ Headsit = 1, Cape = 1, Hang = 1 }) do
            if k ~= mode then Y.setToggle(k, false) end
        end
        if not Y.startAttach(mode) then Y.setToggle(key, false) end
    else
        if Attach.Mode == mode then Y.stopAttach() end
    end
end

------------------------------------------------------------
-- RAGDOLL (FE: joints replaced by ball sockets on your own character)
------------------------------------------------------------
function Y.ragdollOff()
    Y.fmaid("Ragdoll"):Destroy()
    local c, h = Y.getChar(), Y.getHum()
    if c then
        for _, mo in ipairs(c:GetDescendants()) do
            if mo:IsA("Motor6D") and mo.Enabled == false then mo.Enabled = true end
        end
    end
    if h then
        h.PlatformStand = false
        pcall(function() h:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
end

function Y.ragdollOn()
    Y.ragdollOff()
    local c, h = Y.getChar(), Y.getHum()
    if not (c and h) or h.Health <= 0 then return end
    local m = Y.fmaid("Ragdoll")

    for _, mo in ipairs(c:GetDescendants()) do
        if mo:IsA("Motor6D") and mo.Part0 and mo.Part1 and mo.Part0.Name ~= "HumanoidRootPart" then
            local a0 = Y.tag(Instance.new("Attachment"), "Ragdoll")
            a0.CFrame = mo.C0
            a0.Parent = mo.Part0
            local a1 = Y.tag(Instance.new("Attachment"), "Ragdoll")
            a1.CFrame = mo.C1
            a1.Parent = mo.Part1
            local bs = Y.tag(Instance.new("BallSocketConstraint"), "Ragdoll")
            bs.Attachment0 = a0
            bs.Attachment1 = a1
            bs.LimitsEnabled = true
            bs.UpperAngle = 70
            bs.TwistLimitsEnabled = true
            bs.TwistLowerAngle = -45
            bs.TwistUpperAngle = 45
            bs.Parent = mo.Part0
            mo.Enabled = false
            m:Give(a0); m:Give(a1); m:Give(bs)
        end
    end

    h.PlatformStand = true
    pcall(function() h:ChangeState(Enum.HumanoidStateType.Physics) end)
    m:Give(RunService.Heartbeat:Connect(function()
        local hh = Y.getHum()
        if not hh or hh.Health <= 0 then return end
        hh.PlatformStand = true
        if hh:GetState() ~= Enum.HumanoidStateType.Physics then
            pcall(function() hh:ChangeState(Enum.HumanoidStateType.Physics) end)
        end
    end))
end

------------------------------------------------------------
-- FREEZE (FE: root anchored, optional pose freeze)
------------------------------------------------------------
function Y.stopFreeze()
    Y.fmaid("Freeze"):Destroy()
    local r, h = Y.getRoot(), Y.getHum()
    if r then r.Anchored = false end
    if h then
        local animator = h:FindFirstChildOfClass("Animator")
        if animator then
            for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
                pcall(function() t:AdjustSpeed(1) end)
            end
        end
    end
end

function Y.startFreeze()
    Y.stopFreeze()
    local r, h = Y.getRoot(), Y.getHum()
    if not (r and h) then return end
    local m = Y.fmaid("Freeze")
    r.AssemblyLinearVelocity = Vector3.zero
    r.AssemblyAngularVelocity = Vector3.zero
    r.Anchored = true
    m:Give(RunService.Heartbeat:Connect(function()
        local rr, hh = Y.getRoot(), Y.getHum()
        if rr and not rr.Anchored then rr.Anchored = true end
        if State.Freeze.Pose and hh then
            local animator = hh:FindFirstChildOfClass("Animator")
            if animator then
                for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
                    if t.Speed ~= 0 then pcall(function() t:AdjustSpeed(0) end) end
                end
            end
        end
    end))
end

------------------------------------------------------------
-- INVISIBLE (FE: real character parked in the sky, you drive a local clone)
------------------------------------------------------------
local Invis = { On = false, Busy = false, Real = nil, Fake = nil }
local INVIS_SKY = Vector3.new(0, math.pi * 1000000, 0)

function Y.stopMovers()
    if State.Fly.Enabled then State.Fly.Enabled = false; Y.stopFly(); Y.setToggle("Fly", false) end
    if State.Spin.Enabled then State.Spin.Enabled = false; Y.stopSpin(); Y.setToggle("Spin", false) end
    if State.Fling.Enabled then State.Fling.Enabled = false; Y.stopFling(); Y.setToggle("Fling", false) end
    if State.Orbit.Enabled then State.Orbit.Enabled = false; Y.stopOrbit(); Y.setToggle("Orbit", false) end
    if State.Ragdoll.Enabled then State.Ragdoll.Enabled = false; Y.ragdollOff(); Y.setToggle("Ragdoll", false) end
    if State.Freeze.Enabled then State.Freeze.Enabled = false; Y.stopFreeze(); Y.setToggle("Freeze", false) end
    if Attach.Mode then
        local mode = Attach.Mode
        Y.stopAttach()
        Y.setToggle(mode, false)
    end
end

function Y.stopInvis()
    if not Invis.On then return end
    Y.fmaid("Invis"):Destroy()
    local real, fake = Invis.Real, Invis.Fake
    Invis.On = false
    State.Invis.Enabled = false

    pcall(function()
        local fr = fake and fake:FindFirstChild("HumanoidRootPart")
        local rr = real and real:FindFirstChild("HumanoidRootPart")
        local dest = fr and fr.CFrame
        if real then
            real.Parent = Workspace
            LocalPlayer.Character = real
            if rr and dest then
                rr.CFrame = dest
                rr.AssemblyLinearVelocity = Vector3.zero
            end
            local h = real:FindFirstChildOfClass("Humanoid")
            if h then Workspace.CurrentCamera.CameraSubject = h end
        end
    end)
    if fake then pcall(function() fake:Destroy() end) end
    Invis.Real, Invis.Fake = nil, nil
end

function Y.startInvis()
    if Invis.On or Invis.Busy then return end
    local char, root, hum = Y.getChar(), Y.getRoot(), Y.getHum()
    if not (char and root and hum) or hum.Health <= 0 then
        return Y.notify("Invisible", "No character found.")
    end
    Invis.Busy = true
    Y.stopMovers()

    task.spawn(function()
        local ok, err = pcall(function()
            char.Archivable = true
            local fake = char:Clone()
            -- strip any movers cloned along with the character
            for _, d in ipairs(fake:GetDescendants()) do
                if d:GetAttribute("YenOwner") then d:Destroy() end
            end
            for _, d in ipairs(fake:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.Transparency = (d.Name == "HumanoidRootPart") and 1 or 0.5
                end
            end

            local origCF = root.CFrame
            local cam = Workspace.CurrentCamera
            cam.CameraType = Enum.CameraType.Scriptable
            char:MoveTo(INVIS_SKY)
            task.wait(0.2)
            char.Parent = Lighting
            fake.Parent = Workspace
            local fr = fake:WaitForChild("HumanoidRootPart", 3)
            if fr then fr.CFrame = origCF end

            Invis.Real, Invis.Fake, Invis.On = char, fake, true
            State.Invis.Enabled = true
            LocalPlayer.Character = fake
            local fh = fake:FindFirstChildOfClass("Humanoid")
            if fh then cam.CameraSubject = fh end
            cam.CameraType = Enum.CameraType.Custom

            if fh then
                Y.fmaid("Invis"):Give(fh.Died:Connect(function()
                    Y.stopInvis()
                    Y.setToggle("Invis", false)
                end))
            end
        end)
        Invis.Busy = false
        if not ok then
            pcall(function() Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
            State.Invis.Enabled = false
            Y.setToggle("Invis", false)
            Y.notify("Invisible", "Failed: " .. tostring(err), 4)
        end
    end)
end

------------------------------------------------------------
-- R6 <-> R15 (saves the rig through the official avatar prompt, then respawns)
------------------------------------------------------------
function Y.switchRig(rig)
    local h = Y.getHum()
    if not h then return Y.notify("Rig", "No character found.") end
    if h.RigType == rig then
        return Y.notify("Rig", "You are already " .. (rig == Enum.HumanoidRigType.R6 and "R6." or "R15."), 3)
    end
    task.spawn(function()
        local ok, desc = pcall(function() return h:GetAppliedDescription() end)
        if not ok or not desc then return Y.notify("Rig", "Couldn't read your avatar.", 4) end
        local ok2, err = pcall(function() AvatarEditorService:PromptSaveAvatar(desc, rig) end)
        if not ok2 then return Y.notify("Rig", "Avatar prompt unavailable: " .. tostring(err), 5) end
        local result = AvatarEditorService.PromptSaveAvatarCompleted:Wait()
        if result == Enum.AvatarPromptResult.Success then
            Y.notify("Rig", "Saved. Respawning into the new rig...", 3)
            task.wait(0.4)
            pcall(function()
                local hh = Y.getHum()
                if hh then hh.Health = 0 end
            end)
        else
            Y.notify("Rig", "Cancelled or failed (" .. tostring(result) .. ").", 4)
        end
    end)
end

------------------------------------------------------------
-- TOOLS: TP Tool + Platform Tool
------------------------------------------------------------
function Y.getBackpack() return LocalPlayer:FindFirstChildOfClass("Backpack") end
function Y.removeTool(name)
    local bp = Y.getBackpack()
    if bp then local t = bp:FindFirstChild(name); if t then t:Destroy() end end
    local c = Y.getChar()
    if c then local t = c:FindFirstChild(name); if t then t:Destroy() end end
end

function Y.giveTPTool()
    Y.removeTool("TP Tool")
    local bp = Y.getBackpack()
    if not bp then return Y.notify("TP Tool", "Backpack not found.") end
    local tool = Instance.new("Tool")
    tool.Name = "TP Tool"
    tool.ToolTip = "Click / tap to teleport"
    tool.RequiresHandle = false
    tool.CanBeDropped = false
    tool.Activated:Connect(function()
        local r = Y.getRoot()
        local mouse = LocalPlayer:GetMouse()
        mouse.TargetFilter = Y.getChar()
        local hit = mouse.Hit
        if r and hit then
            local rot = r.CFrame - r.CFrame.Position
            r.CFrame = CFrame.new(hit.Position + Vector3.new(0, State.TPTool.Height, 0)) * rot
            r.AssemblyLinearVelocity = Vector3.zero
        end
    end)
    tool.Parent = bp
    State.TPTool.Given = true
end

local PlatformPart
function Y.feetY()
    local r, h = Y.getRoot(), Y.getHum()
    if not (r and h) then return nil end
    local off = (h.RigType == Enum.HumanoidRigType.R6) and 3 or (h.HipHeight + r.Size.Y / 2)
    return r.Position.Y - off
end
function Y.destroyPlatform()
    if PlatformPart then PlatformPart:Destroy(); PlatformPart = nil end
end
function Y.applyPlatformProps()
    if not (PlatformPart and PlatformPart.Parent) then return end
    local S, T = State.PlatTool.Size, State.PlatTool.Thick
    local cf = PlatformPart.CFrame
    PlatformPart.Size = Vector3.new(S, T, S)
    PlatformPart.Transparency = State.PlatTool.Trans
    PlatformPart.CFrame = cf
end
function Y.placePlatform()
    local r, fy = Y.getRoot(), Y.feetY()
    if not (r and fy) then return end
    if not (PlatformPart and PlatformPart.Parent) then
        PlatformPart = Instance.new("Part")
        PlatformPart.Name = "YenPlatform"
        PlatformPart.Anchored = true
        PlatformPart.CanCollide = true
        PlatformPart.TopSurface = Enum.SurfaceType.Smooth
        PlatformPart.BottomSurface = Enum.SurfaceType.Smooth
        PlatformPart.Material = Enum.Material.SmoothPlastic
        PlatformPart.Color = Color3.fromRGB(120, 140, 255)
        PlatformPart.Parent = Workspace
    end
    local S, T = State.PlatTool.Size, State.PlatTool.Thick
    PlatformPart.Size = Vector3.new(S, T, S)
    PlatformPart.Transparency = State.PlatTool.Trans
    PlatformPart.CFrame = CFrame.new(r.Position.X, fy - T / 2 - 0.1, r.Position.Z)
end

function Y.givePlatformTool()
    Y.removeTool("Platform")
    local bp = Y.getBackpack()
    if not bp then return Y.notify("Platform", "Backpack not found.") end
    local tool = Instance.new("Tool")
    tool.Name = "Platform"
    tool.ToolTip = "Click / tap to place a platform under your feet"
    tool.RequiresHandle = false
    tool.CanBeDropped = false
    tool.Activated:Connect(Y.placePlatform)
    tool.Equipped:Connect(function()
        Y.fmaid("PlatFollow"):Destroy()
        Y.fmaid("PlatFollow"):Give(RunService.Heartbeat:Connect(function()
            local r = Y.getRoot()
            if State.PlatTool.Follow and PlatformPart and PlatformPart.Parent and r then
                local y = PlatformPart.Position.Y
                PlatformPart.CFrame = CFrame.new(r.Position.X, y, r.Position.Z)
            end
        end))
    end)
    tool.Unequipped:Connect(function() Y.fmaid("PlatFollow"):Destroy() end)
    tool.Parent = bp
    State.PlatTool.Given = true
end

------------------------------------------------------------
-- WEATHER (client-side only, NOT FE)
------------------------------------------------------------
local Weather = { Orig = nil }
local LIGHT_KEYS = { "Brightness", "ClockTime", "Ambient", "OutdoorAmbient", "FogColor", "FogStart",
    "FogEnd", "ColorShift_Top", "ColorShift_Bottom", "ExposureCompensation" }

local WeatherPresets = {
    Rain = { bright = 1.4, amb = Color3.fromRGB(95, 105, 120), out = Color3.fromRGB(85, 95, 110),
        fog = Color3.fromRGB(115, 125, 140), fogEnd = 1500, atm = 0.40, atmColor = Color3.fromRGB(155, 165, 180),
        cloud = 0.85, cloudColor = Color3.fromRGB(95, 100, 110), rain = true },
    Thunderstorm = { bright = 0.9, amb = Color3.fromRGB(60, 65, 80), out = Color3.fromRGB(55, 60, 75),
        fog = Color3.fromRGB(70, 75, 90), fogEnd = 1000, atm = 0.55, atmColor = Color3.fromRGB(110, 115, 130),
        cloud = 1, cloudColor = Color3.fromRGB(55, 58, 68), rain = true, heavy = true, lightning = true },
    Snow = { bright = 2.2, amb = Color3.fromRGB(150, 155, 165), out = Color3.fromRGB(165, 170, 180),
        fog = Color3.fromRGB(215, 220, 230), fogEnd = 1400, atm = 0.45, atmColor = Color3.fromRGB(225, 230, 240),
        cloud = 0.7, cloudColor = Color3.fromRGB(220, 225, 235), snow = true },
    Fog = { bright = 1.6, amb = Color3.fromRGB(130, 135, 140), out = Color3.fromRGB(135, 140, 145),
        fog = Color3.fromRGB(175, 180, 185), fogEnd = 700, atm = 0.8, atmColor = Color3.fromRGB(190, 195, 200),
        cloud = 0.5, cloudColor = Color3.fromRGB(170, 175, 180) },
    Sandstorm = { bright = 1.8, amb = Color3.fromRGB(170, 130, 80), out = Color3.fromRGB(180, 140, 85),
        fog = Color3.fromRGB(200, 160, 100), fogEnd = 500, atm = 0.75, atmColor = Color3.fromRGB(205, 160, 95),
        cloud = 0.3, cloudColor = Color3.fromRGB(190, 150, 90), sand = true },
    Sunset = { clock = 17.8, bright = 2.4, amb = Color3.fromRGB(120, 90, 85), out = Color3.fromRGB(150, 100, 90),
        fog = Color3.fromRGB(230, 150, 110), fogEnd = 4000, top = Color3.fromRGB(255, 170, 110) },
    Night = { clock = 0, bright = 0.4, amb = Color3.fromRGB(35, 40, 65), out = Color3.fromRGB(30, 35, 60),
        fog = Color3.fromRGB(15, 18, 30), fogEnd = 4000 },
}

function Y.weatherSnapshot()
    if Weather.Orig then return end
    local o = { light = {} }
    for _, k in ipairs(LIGHT_KEYS) do o.light[k] = Lighting[k] end
    local atm = Lighting:FindFirstChildOfClass("Atmosphere")
    if atm then
        o.atm = { Density = atm.Density, Offset = atm.Offset, Color = atm.Color, Decay = atm.Decay,
                  Glare = atm.Glare, Haze = atm.Haze }
    end
    local cl = Workspace.Terrain:FindFirstChildOfClass("Clouds")
    if cl then o.clouds = { Cover = cl.Cover, Density = cl.Density, Color = cl.Color, Enabled = cl.Enabled } end
    Weather.Orig = o
end

function Y.stopWeather()
    Y.fmaid("Weather"):Destroy()
    local o = Weather.Orig
    if not o then return end
    for k, v in pairs(o.light) do pcall(function() Lighting[k] = v end) end
    local atm = Lighting:FindFirstChildOfClass("Atmosphere")
    if atm and o.atm then
        for k, v in pairs(o.atm) do pcall(function() atm[k] = v end) end
    end
    local cl = Workspace.Terrain:FindFirstChildOfClass("Clouds")
    if cl and o.clouds then
        for k, v in pairs(o.clouds) do pcall(function() cl[k] = v end) end
    end
    Weather.Orig = nil
end

function Y.makeEmitterPart(m)
    local p = Instance.new("Part")
    p.Name = "YenWeather"
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.Transparency = 1
    p.Size = Vector3.new(90, 1, 90)
    p.Parent = Workspace
    m:Give(p)
    m:Give(RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        if cam then p.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 45, 0)) end
    end))
    return p
end

function Y.applyWeather(name, intensity)
    Y.stopWeather()
    if name == "Clear" then return end
    local p = WeatherPresets[name]
    if not p then return end
    Y.weatherSnapshot()
    local k = math.clamp(intensity, 1, 100) / 100
    local m = Y.fmaid("Weather")

    if p.clock then Lighting.ClockTime = p.clock end
    Lighting.Brightness = p.bright
    Lighting.Ambient = p.amb
    Lighting.OutdoorAmbient = p.out
    Lighting.FogColor = p.fog
    Lighting.FogStart = 0
    Lighting.FogEnd = p.fogEnd * (1.6 - k * 1.2)
    if p.top then Lighting.ColorShift_Top = p.top end

    if p.atm then
        local atm = Lighting:FindFirstChildOfClass("Atmosphere")
        if not atm then
            atm = Instance.new("Atmosphere")
            atm.Name = "YenAtmosphere"
            atm.Parent = Lighting
            m:Give(atm)
        end
        atm.Density = math.clamp(p.atm * (0.4 + k * 0.9), 0, 1)
        atm.Color = p.atmColor
        atm.Decay = p.atmColor
        atm.Haze = 1 + k * 2
        atm.Glare = 0
    end

    if p.cloud then
        local cl = Workspace.Terrain:FindFirstChildOfClass("Clouds")
        if not cl then
            cl = Instance.new("Clouds")
            cl.Parent = Workspace.Terrain
            m:Give(cl)
        end
        cl.Enabled = true
        cl.Cover = p.cloud
        cl.Density = 0.6 + k * 0.4
        cl.Color = p.cloudColor
    end

    if p.rain or p.snow or p.sand then
        local part = Y.makeEmitterPart(m)
        local e = Instance.new("ParticleEmitter")
        e.LockedToPart = false
        e.EmissionDirection = Enum.NormalId.Bottom
        e.Parent = part
        if p.rain then
            e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
            e.Rate = (p.heavy and 1400 or 800) * k + 100
            e.Lifetime = NumberRange.new(0.8, 1.0)
            e.Speed = NumberRange.new(95, 115)
            e.SpreadAngle = Vector2.new(4, 4)
            e.Size = NumberSequence.new(0.18)
            e.Transparency = NumberSequence.new(0.35)
            e.Color = ColorSequence.new(Color3.fromRGB(190, 205, 225))
            e.Orientation = Enum.ParticleOrientation.VelocityParallel
            pcall(function() e.Squash = NumberSequence.new(-4) end)
            e.Acceleration = Vector3.new(-6, -40, 0)
        elseif p.snow then
            e.Texture = "rbxasset://textures/particles/smoke_main.dds"
            e.Rate = 450 * k + 40
            e.Lifetime = NumberRange.new(5, 7)
            e.Speed = NumberRange.new(6, 10)
            e.SpreadAngle = Vector2.new(25, 25)
            e.Size = NumberSequence.new(0.35)
            e.Transparency = NumberSequence.new(0.2)
            e.Color = ColorSequence.new(Color3.new(1, 1, 1))
            e.Acceleration = Vector3.new(3, -2, 1)
            e.RotSpeed = NumberRange.new(-40, 40)
        else
            e.Texture = "rbxasset://textures/particles/smoke_main.dds"
            e.Rate = 700 * k + 60
            e.Lifetime = NumberRange.new(2, 3)
            e.Speed = NumberRange.new(40, 60)
            e.SpreadAngle = Vector2.new(30, 30)
            e.Size = NumberSequence.new(3)
            e.Transparency = NumberSequence.new(0.65)
            e.Color = ColorSequence.new(Color3.fromRGB(205, 165, 105))
            e.Acceleration = Vector3.new(60, -4, 20)
        end
    end

    if p.lightning then
        local alive = true
        m:Give(function() alive = false end)
        task.spawn(function()
            while alive do
                task.wait(math.random(40, 100) / 10 / (0.5 + k))
                if not alive then break end
                local base = p.bright
                for _ = 1, math.random(1, 2) do
                    Lighting.Brightness = 6
                    task.wait(0.06)
                    Lighting.Brightness = base
                    task.wait(0.08)
                end
                Lighting.Brightness = 5
                TweenService:Create(Lighting, TweenInfo.new(0.45), { Brightness = base }):Play()
            end
        end)
    end
end

------------------------------------------------------------
-- RTX (client-side only, NOT FE)  WARNING: heavy on weak devices
-- Works in layers so you always see a difference, even when the executor
-- can't switch the engine to Future lighting.
------------------------------------------------------------
local RTX = { Orig = nil, Refl = setmetatable({}, { __mode = "k" }) }
local RTX_PRESETS = {
    Low    = { bloom = 0.7, bsize = 30, thr = 0.85, rays = 0.10, dof = false, soft = 0.20, spec = 1.2, contrast = 0.15, sat = 0.20, bright = 0.02, atm = false, refl = false },
    Medium = { bloom = 1.0, bsize = 36, thr = 0.80, rays = 0.20, dof = false, soft = 0.10, spec = 1.5, contrast = 0.22, sat = 0.28, bright = 0.03, atm = true,  refl = false },
    High   = { bloom = 1.3, bsize = 44, thr = 0.75, rays = 0.30, dof = true,  soft = 0.05, spec = 2.0, contrast = 0.30, sat = 0.35, bright = 0.04, atm = true,  refl = false },
    Ultra  = { bloom = 1.7, bsize = 56, thr = 0.70, rays = 0.40, dof = true,  soft = 0.02, spec = 3.0, contrast = 0.38, sat = 0.42, bright = 0.05, atm = true,  refl = true  },
}
local REFLECT = {
    [Enum.Material.Metal] = 0.25, [Enum.Material.DiamondPlate] = 0.25, [Enum.Material.CorrodedMetal] = 0.12,
    [Enum.Material.Glass] = 0.30, [Enum.Material.Ice] = 0.25, [Enum.Material.Marble] = 0.12,
    [Enum.Material.Granite] = 0.07, [Enum.Material.SmoothPlastic] = 0.06, [Enum.Material.Foil] = 0.3,
}
local RTX_LIGHT_KEYS = { "Brightness", "ExposureCompensation", "EnvironmentSpecularScale",
    "EnvironmentDiffuseScale", "ShadowSoftness", "GlobalShadows", "ColorShift_Top" }

function Y.reflectPart(p)
    if not p:IsA("BasePart") or p.Reflectance > 0 or Y.isCharacterPart(p) then return end
    local r = REFLECT[p.Material]
    if r then RTX.Refl[p] = p.Reflectance; p.Reflectance = r end
end

function Y.rtxOff()
    Y.fmaid("RTX"):Destroy()
    local o = RTX.Orig
    if not o then return end
    RTX.Orig = nil
    for k, v in pairs(o.light) do pcall(function() Lighting[k] = v end) end
    for inst, props in pairs(o.atm) do
        if inst.Parent then for k, v in pairs(props) do pcall(function() inst[k] = v end) end end
    end
    if o.tech ~= nil then pcall(function() sethiddenproperty(Lighting, "Technology", o.tech) end) end
    if o.mat ~= nil then pcall(function() MaterialService.Use2022Materials = o.mat end) end
    if o.quality ~= nil then pcall(function() settings().Rendering.QualityLevel = o.quality end) end
    if o.water then
        pcall(function()
            Workspace.Terrain.WaterReflectance = o.water.refl
            Workspace.Terrain.WaterTransparency = o.water.trans
        end)
    end
    for p, orig in pairs(RTX.Refl) do
        if p and p.Parent then p.Reflectance = orig end
        RTX.Refl[p] = nil
    end
end

function Y.rtxOn(quality)
    Y.rtxOff()
    local q = RTX_PRESETS[quality] or RTX_PRESETS.Medium
    local m = Y.fmaid("RTX")
    local o = { light = {}, atm = {} }
    for _, k in ipairs(RTX_LIGHT_KEYS) do
        local ok, v = pcall(function() return Lighting[k] end)
        if ok then o.light[k] = v end
    end
    for _, d in ipairs(Lighting:GetChildren()) do
        if d:IsA("Atmosphere") then
            o.atm[d] = { Density = d.Density, Offset = d.Offset, Glare = d.Glare, Haze = d.Haze, Color = d.Color }
        end
    end
    local okT, tech = pcall(function() return gethiddenproperty(Lighting, "Technology") end)
    if okT then o.tech = tech end
    local okM, mat = pcall(function() return MaterialService.Use2022Materials end)
    if okM then o.mat = mat end
    local okQ, ql = pcall(function() return settings().Rendering.QualityLevel end)
    if okQ then o.quality = ql end
    pcall(function() o.water = { refl = Workspace.Terrain.WaterReflectance, trans = Workspace.Terrain.WaterTransparency } end)
    RTX.Orig = o

    -- 1) engine: Future lighting (needs sethiddenproperty)
    pcall(function() sethiddenproperty(Lighting, "Technology", Enum.Technology.Future) end)
    local okR, now = pcall(function() return gethiddenproperty(Lighting, "Technology") end)
    local future = okR and now == Enum.Technology.Future

    -- 2) lighting values that are visible on every technology
    pcall(function() Lighting.GlobalShadows = true end)
    pcall(function() Lighting.ShadowSoftness = q.soft end)
    pcall(function() Lighting.EnvironmentSpecularScale = q.spec end)
    pcall(function() Lighting.EnvironmentDiffuseScale = 1 end)
    pcall(function() Lighting.ExposureCompensation = 0.25 end)
    pcall(function() Lighting.Brightness = math.max(Lighting.Brightness, 2.5) end)
    pcall(function() Lighting.ColorShift_Top = Color3.fromRGB(255, 236, 210) end)
    pcall(function() MaterialService.Use2022Materials = true end)
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level21 end)
    pcall(function()
        Workspace.Terrain.WaterReflectance = 1
        Workspace.Terrain.WaterTransparency = 0.9
    end)

    -- 3) post-processing (this is what makes the change obvious)
    local bloom = Instance.new("BloomEffect")
    bloom.Name = "YenRTXBloom"
    bloom.Intensity = q.bloom; bloom.Size = q.bsize; bloom.Threshold = q.thr
    bloom.Parent = Lighting; m:Give(bloom)

    local cc = Instance.new("ColorCorrectionEffect")
    cc.Name = "YenRTXColor"
    cc.Contrast = q.contrast; cc.Saturation = q.sat; cc.Brightness = q.bright
    cc.TintColor = Color3.fromRGB(255, 247, 238)
    cc.Parent = Lighting; m:Give(cc)

    if q.rays > 0 then
        local sr = Instance.new("SunRaysEffect")
        sr.Name = "YenRTXRays"
        sr.Intensity = q.rays; sr.Spread = 1
        sr.Parent = Lighting; m:Give(sr)
    end
    if q.dof then
        local dof = Instance.new("DepthOfFieldEffect")
        dof.Name = "YenRTXDof"
        dof.FarIntensity = 0.18; dof.NearIntensity = 0
        dof.FocusDistance = 55; dof.InFocusRadius = 45
        dof.Parent = Lighting; m:Give(dof)
    end
    if q.atm then
        local atm = Lighting:FindFirstChildOfClass("Atmosphere")
        if not atm then
            atm = Instance.new("Atmosphere")
            atm.Name = "YenRTXAtmosphere"
            atm.Density = 0.3; atm.Offset = 0.25
            atm.Color = Color3.fromRGB(199, 205, 220)
            atm.Decay = Color3.fromRGB(106, 112, 125)
            atm.Parent = Lighting; m:Give(atm)
        end
        atm.Glare = 0.5
        atm.Haze = 1.4
    end

    -- 4) reflections on shiny materials (Ultra)
    if q.refl then
        task.spawn(function()
            local n = 0
            for _, d in ipairs(Workspace:GetDescendants()) do
                if not RTX.Orig then break end
                Y.reflectPart(d)
                n = n + 1
                if n % 400 == 0 then task.wait() end
            end
        end)
        m:Give(Workspace.DescendantAdded:Connect(function(d) task.defer(Y.reflectPart, d) end))
    end

    Y.notify("RTX", (future and "Future lighting: ON. " or "Future lighting unavailable on this executor, using the effect layers. ")
        .. "Quality: " .. quality .. ". If you lag, lower it or turn RTX off.", 6)
end

------------------------------------------------------------
-- VISIBILITY: No Fog / No Darkness / Full Brightness
------------------------------------------------------------
local LightFX = { active = {}, count = 0, base = nil }
local LF_KEYS = { "Brightness", "ClockTime", "Ambient", "OutdoorAmbient", "FogStart", "FogEnd",
    "GlobalShadows", "ExposureCompensation" }

function Y.lfSnapshot()
    local b = { light = {}, atm = {}, fx = {} }
    for _, k in ipairs(LF_KEYS) do b.light[k] = Lighting[k] end
    for _, d in ipairs(Lighting:GetChildren()) do
        if d:IsA("Atmosphere") then
            b.atm[d] = { Density = d.Density, Haze = d.Haze }
        elseif d:IsA("ColorCorrectionEffect") and not d.Name:find("YenRTX", 1, true) then
            b.fx[d] = { Brightness = d.Brightness }
        end
    end
    LightFX.base = b
end

function Y.lfRestore()
    local b = LightFX.base
    if not b then return end
    LightFX.base = nil
    for k, v in pairs(b.light) do pcall(function() Lighting[k] = v end) end
    for inst, props in pairs(b.atm) do
        if inst.Parent then for k, v in pairs(props) do pcall(function() inst[k] = v end) end end
    end
    for inst, props in pairs(b.fx) do
        if inst.Parent then for k, v in pairs(props) do pcall(function() inst[k] = v end) end end
    end
end

function Y.lfEnable(name, fn)
    if LightFX.active[name] then return end
    if LightFX.count == 0 then Y.lfSnapshot() end
    LightFX.active[name] = true
    LightFX.count = LightFX.count + 1
    Y.fmaid("LF_" .. name):Give(RunService.RenderStepped:Connect(fn))
end

function Y.lfDisable(name)
    if not LightFX.active[name] then return end
    Y.fmaid("LF_" .. name):Destroy()
    LightFX.active[name] = nil
    LightFX.count = LightFX.count - 1
    if LightFX.count <= 0 then LightFX.count = 0; Y.lfRestore() end
end

function Y.noFogStep()
    Lighting.FogStart = 9e8
    Lighting.FogEnd = 9e9
    for _, d in ipairs(Lighting:GetChildren()) do
        if d:IsA("Atmosphere") and not d.Name:find("YenRTX", 1, true) then
            d.Density = 0
            d.Haze = 0
        end
    end
end

function Y.noDarkStep()
    local a, o = Lighting.Ambient, Lighting.OutdoorAmbient
    Lighting.Ambient = Color3.new(math.max(a.R, 0.5), math.max(a.G, 0.5), math.max(a.B, 0.5))
    Lighting.OutdoorAmbient = Color3.new(math.max(o.R, 0.55), math.max(o.G, 0.55), math.max(o.B, 0.55))
    if Lighting.Brightness < 2 then Lighting.Brightness = 2 end
    if Lighting.ExposureCompensation < 0 then Lighting.ExposureCompensation = 0 end
    for _, d in ipairs(Lighting:GetChildren()) do
        if d:IsA("ColorCorrectionEffect") and d.Brightness < 0 and not d.Name:find("YenRTX", 1, true) then
            d.Brightness = 0
        end
    end
end

function Y.fullBrightStep()
    Lighting.ClockTime = 14
    Lighting.Brightness = 3
    Lighting.GlobalShadows = false
    Lighting.Ambient = Color3.fromRGB(178, 178, 178)
    Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
    if Lighting.ExposureCompensation < 0 then Lighting.ExposureCompensation = 0 end
end

------------------------------------------------------------
-- CAMERA VIEW (First Person / Third Person)
------------------------------------------------------------
local CamOrig
function Y.setCameraMode(mode)
    Y.fmaid("CamMode"):Destroy()
    local lp = LocalPlayer
    if mode == "Default" then
        if CamOrig then
            pcall(function()
                lp.CameraMaxZoomDistance = CamOrig.Max
                lp.CameraMinZoomDistance = CamOrig.Min
                lp.CameraMode = CamOrig.Mode
            end)
            CamOrig = nil
        end
        return
    end
    if not CamOrig then
        CamOrig = { Mode = lp.CameraMode, Min = lp.CameraMinZoomDistance, Max = lp.CameraMaxZoomDistance }
    end
    local function apply()
        pcall(function()
            if mode == "First Person" then
                lp.CameraMinZoomDistance = 0.5
                lp.CameraMaxZoomDistance = 0.5
                lp.CameraMode = Enum.CameraMode.LockFirstPerson
            else
                lp.CameraMode = Enum.CameraMode.Classic
                lp.CameraMaxZoomDistance = math.max(400, State.Cam.Distance)
                lp.CameraMinZoomDistance = State.Cam.Distance
            end
        end)
    end
    apply()
    local acc = 0
    Y.fmaid("CamMode"):Give(RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc < 0.4 then return end
        acc = 0
        apply()
    end))
end

------------------------------------------------------------
-- FAKE LAG (others see you stutter / skip)
------------------------------------------------------------
function Y.stopFakeLag()
    Y.fmaid("FakeLag"):Destroy()
    local r = Y.getRoot()
    if r and not State.Freeze.Enabled then r.Anchored = false end
end

function Y.startFakeLag()
    Y.stopFakeLag()
    local m = Y.fmaid("FakeLag")
    local alive = true
    m:Give(function() alive = false end)
    task.spawn(function()
        while alive do
            task.wait(State.FakeLag.Interval * (0.6 + math.random() * 0.8))
            if not alive then break end
            local r = Y.getRoot()
            if r and not State.Freeze.Enabled then
                r.AssemblyLinearVelocity = Vector3.zero
                r.Anchored = true
                task.wait(State.FakeLag.Duration * (0.6 + math.random() * 0.8))
                local r2 = Y.getRoot()
                if r2 and not State.Freeze.Enabled then r2.Anchored = false end
            end
        end
    end)
end

------------------------------------------------------------
-- TELEPORT POINTS (unlimited, saved per game, optional ESP, ordered routes)
------------------------------------------------------------
local placeKey = tostring(game.PlaceId)
local Points = { list = {}, tpDd = nil, routeEl = nil, token = 0, espFolder = nil }

function Y.ptNames()
    local t = {}
    for _, p in ipairs(Points.list) do t[#t + 1] = p.name end
    return t
end
function Y.ptFind(name)
    for i, p in ipairs(Points.list) do
        if p.name == name then return p, i end
    end
    return nil
end
function Y.ptPersist()
    local arr = {}
    for _, p in ipairs(Points.list) do
        arr[#arr + 1] = { name = p.name, c = { p.cf:GetComponents() } }
    end
    Saved.points[placeKey] = arr
    Y.writeSaved()
end
function Y.ptLoad()
    local arr = Saved.points[placeKey]
    if type(arr) ~= "table" then return end
    for _, e in ipairs(arr) do
        if type(e) == "table" and type(e.c) == "table" and #e.c == 12 then
            Points.list[#Points.list + 1] = { name = tostring(e.name), cf = CFrame.new(table.unpack(e.c)) }
        end
    end
end
Y.ptLoad()

function Y.ptClearEsp()
    Y.fmaid("PointEsp"):Destroy()
    if Points.espFolder then Points.espFolder:Destroy(); Points.espFolder = nil end
end

function Y.ptBuildEsp()
    Y.ptClearEsp()
    if not State.Points.Esp then return end
    local folder = Instance.new("Folder")
    folder.Name = "YenPoints"
    folder.Parent = Workspace
    Points.espFolder = folder
    local labels = {}
    for _, p in ipairs(Points.list) do
        local anchor = Instance.new("Part")
        anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
        anchor.Transparency = 1
        anchor.Size = Vector3.one
        anchor.Position = p.cf.Position
        anchor.Parent = folder

        local pillar = Instance.new("Part")
        pillar.Anchored, pillar.CanCollide, pillar.CanQuery, pillar.CanTouch = true, false, false, false
        pillar.Material = Enum.Material.Neon
        pillar.Color = Color3.fromRGB(90, 220, 255)
        pillar.Transparency = 0.45
        pillar.Size = Vector3.new(0.4, 40, 0.4)
        pillar.Position = p.cf.Position + Vector3.new(0, 18, 0)
        pillar.Parent = folder

        local gui = Instance.new("BillboardGui")
        gui.Adornee = anchor
        gui.AlwaysOnTop = true
        gui.Size = UDim2.fromOffset(150, 38)
        gui.StudsOffset = Vector3.new(0, 3, 0)
        gui.Parent = anchor
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.fromScale(1, 1)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 13
        lbl.TextColor3 = Color3.fromRGB(150, 235, 255)
        lbl.TextStrokeTransparency = 0.3
        lbl.RichText = true
        lbl.Parent = gui
        labels[#labels + 1] = { lbl = lbl, name = p.name, pos = p.cf.Position }
    end
    local acc = 0
    Y.fmaid("PointEsp"):Give(RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        local r = Y.getRoot()
        for _, l in ipairs(labels) do
            local d = r and (r.Position - l.pos).Magnitude or 0
            l.lbl.Text = string.format("<b>%s</b>\n%dm", Y.esc(l.name), math.floor(d))
        end
    end))
end

function Y.ptRouteText()
    if #State.Points.Route == 0 then return "Order is empty. Select a point, then press 'Add selected to Order'." end
    local parts = {}
    for i, n in ipairs(State.Points.Route) do parts[#parts + 1] = i .. ". " .. n end
    return table.concat(parts, "\n")
end

function Y.ptRefreshUI()
    if Points.tpDd then pcall(function() Points.tpDd:Refresh(Y.ptNames()) end) end
    if Points.routeEl then pcall(function() Points.routeEl:SetDesc(Y.ptRouteText()) end) end
    Y.ptBuildEsp()
end

function Y.ptAdd(name)
    local r = Y.getRoot()
    if not r then return Y.notify("Point", "No character found.") end
    local base = (name ~= nil and name ~= "") and name or ("Point " .. (#Points.list + 1))
    local final, n = base, 1
    while Y.ptFind(final) do n = n + 1; final = base .. " (" .. n .. ")" end
    Points.list[#Points.list + 1] = { name = final, cf = r.CFrame }
    Y.ptPersist()
    Y.ptRefreshUI()
    Y.notify("Point", "Saved: " .. final, 2)
end

function Y.ptDelete(name)
    local _, i = Y.ptFind(name)
    if not i then return Y.notify("Point", "Pick a point first.", 3) end
    table.remove(Points.list, i)
    for j = #State.Points.Route, 1, -1 do
        if State.Points.Route[j] == name then table.remove(State.Points.Route, j) end
    end
    if State.Points.Selected == name then State.Points.Selected = nil end
    Y.ptPersist()
    Y.ptRefreshUI()
    Y.notify("Point", "Deleted: " .. name, 2)
end

function Y.ptTeleport(name)
    local p = Y.ptFind(name)
    local r = Y.getRoot()
    if not (p and r) then return Y.notify("Point", "Pick a point first.", 3) end
    r.CFrame = p.cf + Vector3.new(0, 0.5, 0)
    r.AssemblyLinearVelocity = Vector3.zero
end

function Y.ptStopRoute()
    Points.token = Points.token + 1
end

function Y.ptRunRoute()
    if #State.Points.Route == 0 then return Y.notify("Order", "The order is empty.", 3) end
    Points.token = Points.token + 1
    local my = Points.token
    task.spawn(function()
        repeat
            for _, name in ipairs(State.Points.Route) do
                if Points.token ~= my then return end
                local p = Y.ptFind(name)
                local r = Y.getRoot()
                if p and r then
                    r.CFrame = p.cf + Vector3.new(0, 0.5, 0)
                    r.AssemblyLinearVelocity = Vector3.zero
                end
                task.wait(State.Points.Delay)
            end
        until (not State.Points.Loop) or Points.token ~= my
    end)
end

------------------------------------------------------------
-- ANTI-FREEZE WATCHDOG + UNSTICK
------------------------------------------------------------
local Watch = {}
local BadStates = {
    [Enum.HumanoidStateType.Physics]          = true,
    [Enum.HumanoidStateType.PlatformStanding] = true,
    [Enum.HumanoidStateType.Ragdoll]          = true,
    [Enum.HumanoidStateType.FallingDown]      = true,
}

function Y.held(key, cond, tol)
    if not cond then Watch[key] = nil; return false end
    Watch[key] = Watch[key] or os.clock()
    if os.clock() - Watch[key] > tol then Watch[key] = nil; return true end
    return false
end

function Y.sweepLeftoverMovers(container)
    for _, d in ipairs(container:GetDescendants()) do
        local owner = d:GetAttribute("YenOwner")
        if owner and not (State[owner] and State[owner].Enabled) then d:Destroy() end
    end
end

function Y.startWatchdog()
    local acc = 0
    MainMaid:Give(RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc < 0.2 then return end
        acc = 0
        if not State.Anti.Freeze then return end
        local c, h, r = Y.getChar(), Y.getHum(), Y.getRoot()
        if not (c and h and r) or h.Health <= 0 then return end
        local tol = State.Anti.Tolerance

        if not State.Freeze.Enabled and not State.FakeLag.Enabled then
            if Y.held("anchor", r.Anchored, tol) then r.Anchored = false end
        end

        local special = State.Fly.Enabled or State.Ragdoll.Enabled or Attach.Mode ~= nil
        if not special then
            if Y.held("plat", h.PlatformStand, tol) then h.PlatformStand = false end
            if Y.held("state", BadStates[h:GetState()] == true, tol + 0.5) then
                pcall(function() h:ChangeState(Enum.HumanoidStateType.Freefall) end)
            end
        end

        if not State.Speed.Enabled and Y.held("ws", h.WalkSpeed < 1, tol + 1) then
            h.WalkSpeed = defaultWalkSpeed
        end
        if not State.Jump.Enabled then
            local low = h.UseJumpPower and h.JumpPower < 1 or ((not h.UseJumpPower) and h.JumpHeight < 0.5)
            if Y.held("jp", low, tol + 1) then
                if h.UseJumpPower then h.JumpPower = defaultJumpPower else h.JumpHeight = defaultJumpHeight end
            end
        end

        Y.sweepLeftoverMovers(r)
    end))
end

function Y.unstick()
    local c, h, r = Y.getChar(), Y.getHum(), Y.getRoot()
    if not (c and h and r) then return Y.notify("Unstick", "No character found.") end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.Anchored then p.Anchored = false end
    end
    Y.sweepLeftoverMovers(c)
    h.PlatformStand = false
    h.Sit = false
    if not State.Speed.Enabled and h.WalkSpeed < 1 then h.WalkSpeed = defaultWalkSpeed end
    if not State.Jump.Enabled and h.JumpPower < 1 then h.JumpPower = defaultJumpPower end
    r.AssemblyLinearVelocity = Vector3.zero
    r.AssemblyAngularVelocity = Vector3.zero
    pcall(function() h:ChangeState(Enum.HumanoidStateType.Freefall) end)
    Y.notify("Unstick", "Movement state reset.", 2)
end

------------------------------------------------------------
-- WINDOW
------------------------------------------------------------
local Window = WindUI:CreateWindow({
    Title  = "Yenrenuton [OUT OF ALPHA]",
    Icon   = "zap",
    Author = "Yenrenuton",
    Folder = "Yenrenuton",
    Size   = Y.getWindowSize(),
    Theme  = "Dark",
    KeySystem = {
        Key     = { "WELLCOME" },
        Note    = "Enter the key to continue. Key: WELLCOME",
        SaveKey = true,
    },
})
pcall(function() Window:SetToggleKey(Enum.KeyCode.RightShift) end)
pcall(function() Window:EditOpenButton({ Title = "Yenrenuton", Icon = "zap", Draggable = true }) end)

------------------------------------------------------------
-- UNLOAD
------------------------------------------------------------
function Y.fullUnload()
    Hooks.alive = false
    Y.stopAimbot(false)
    Noclip.Release("User"); Noclip.Release("FlingNpc")
    Y.lfDisable("NoFog"); Y.lfDisable("NoDark"); Y.lfDisable("FullBright")
    Y.setCameraMode("Default")
    Y.stopFakeLag()
    Y.ptStopRoute(); Y.ptClearEsp()
    Y.stopFlingNpc()
    if State.Fly.Enabled then Y.stopFly() end
    if State.Speed.Enabled then Y.stopSpeed() end
    if State.Jump.Enabled then Y.stopJump() end
    if State.Fling.Enabled then Y.stopFling() end
    if Attach.Mode then Y.stopAttach() end
    if State.Ragdoll.Enabled then Y.ragdollOff() end
    if State.Freeze.Enabled then Y.stopFreeze() end
    if Invis.On then Y.stopInvis() end
    Y.stopWeather()
    Y.rtxOff()
    Y.stopXray()
    Y.stopAnim()
    Y.destroyPlatform()
    Y.removeTool("TP Tool")
    Y.removeTool("Platform")
    for _, m in pairs(Feature) do m:Destroy() end
    Noclip.Release("Fling"); Noclip.Release("Attach")
    local hum = Y.getHum()
    if hum then hum.PlatformStand = false end
    MainMaid:Destroy()
    pcall(function() Window:Destroy() end)
    genv.__YenrenutonUnload = nil
end
genv.__YenrenutonUnload = Y.fullUnload

------------------------------------------------------------
-- TABS
------------------------------------------------------------
local UtilityTab  = Window:Tab({ Title = "Utility",  Icon = "settings" })
local PlayerTab   = Window:Tab({ Title = "Player",   Icon = "user" })
local AvatarTab   = Window:Tab({ Title = "Avatar",   Icon = "shirt" })
local InteractTab = Window:Tab({ Title = "Interact", Icon = "users" })
local ToolsTab    = Window:Tab({ Title = "Tools",    Icon = "wrench" })
local NpcTab      = Window:Tab({ Title = "NPC",      Icon = "bug" })
local WorldTab    = Window:Tab({ Title = "World",    Icon = "cloud" })

------------------------------------------------------------
-- UTILITY TAB
------------------------------------------------------------
UtilityTab:Section({ Title = "Settings" })
UtilityTab:Dropdown({
    Title = "Theme",
    Values = { "Dark", "Light", "Rose", "Plant", "Red", "Indigo", "Sky", "Violet", "Amber", "Emerald" },
    Value = "Dark",
    Callback = function(v) pcall(function() WindUI:SetTheme(v) end) end,
})
if Platform.Keyboard then
    UtilityTab:Keybind({
        Title = "Y.Toggle UI Key",
        Value = "RightShift",
        Callback = function(v)
            local key = typeof(v) == "EnumItem" and v or Enum.KeyCode[v]
            if key then pcall(function() Window:SetToggleKey(key) end) end
        end,
    })
end
UtilityTab:Paragraph({
    Title = "Device",
    Desc  = Platform.Mobile and "Mobile detected. Touch controls enabled."
         or Platform.Laptop and "Laptop detected. Compact layout."
         or "PC detected.",
})

UtilityTab:Section({ Title = "Stability" })
Y.Toggle(UtilityTab, nil, "Anti-Freeze Watchdog", State.Anti.Freeze, function(v) State.Anti.Freeze = v end)
Y.NumBox(UtilityTab, "Freeze Tolerance (seconds)", State.Anti.Tolerance, 0.2, 5, function(v) State.Anti.Tolerance = v end)
Y.Toggle(UtilityTab, nil, "Anti-Rubberband (auto-adapt teleport range)", State.Anti.Rubber,
    function(v) State.Anti.Rubber = v end)
UtilityTab:Button({ Title = "Unstick (force reset movement)", Callback = Y.unstick })
UtilityTab:Button({ Title = "Unload Script (full remove)", Callback = Y.fullUnload })

UtilityTab:Section({ Title = "Discord" })
local DISCORD_LINK = "https://discord.gg/hvuS2vmKb"
UtilityTab:Paragraph({ Title = "Join the community", Desc = DISCORD_LINK })
UtilityTab:Button({
    Title = "Discord Link",
    Desc  = "Copies the invite link to your clipboard",
    Callback = function()
        local copied = false
        if setclipboard then copied = pcall(setclipboard, DISCORD_LINK)
        elseif toclipboard then copied = pcall(toclipboard, DISCORD_LINK) end
        if copied then
            Y.notify("Discord", "Link copied: " .. DISCORD_LINK, 5)
        else
            Y.notify("Discord", "Copy it manually: " .. DISCORD_LINK, 8)
        end
    end,
})

UtilityTab:Section({ Title = "Credit" })
UtilityTab:Paragraph({
    Title = "Yenrenuton [OUT OF ALPHA]",
    Desc  = "Script by Yenrenuton\nUI library: WindUI\nStatus: Out of alpha.",
})

------------------------------------------------------------
-- PLAYER TAB: movement
------------------------------------------------------------
PlayerTab:Section({ Title = "Movement (Infinite Yield method)" })

Y.Toggle(PlayerTab, "Fly", "Fly", false, function(v)
    if v == State.Fly.Enabled then return end
    State.Fly.Enabled = v
    if v then Y.startFly() else Y.stopFly() end
end, "W/A/S/D + Space/E up, Ctrl/Q down. Mobile: joystick + the arrow buttons.")
Y.NumBox(PlayerTab, "Fly Speed", State.Fly.Speed, 1, 2000, function(v) State.Fly.Speed = v end)

Y.Toggle(PlayerTab, "Speed", "Speed", false, function(v)
    if v == State.Speed.Enabled then return end
    State.Speed.Enabled = v
    if v then Y.startSpeed() else Y.stopSpeed() end
end)
Y.NumBox(PlayerTab, "Walk Speed", State.Speed.Value, 0, 2000, function(v) State.Speed.Value = v end)
PlayerTab:Dropdown({ Title = "Speed Method", Values = { "WalkSpeed (Yield)", "TPWalk (Yield)" },
    Value = State.Speed.Mode,
    Callback = function(v)
        State.Speed.Mode = v
        if State.Speed.Enabled then Y.startSpeed() end
    end })
Y.NumBox(PlayerTab, "TPWalk Multiplier (1 = +10 studs/s)", State.Speed.TP, 0, 100, function(v) State.Speed.TP = v end)

Y.Toggle(PlayerTab, "Jump", "Jump Power", false, function(v)
    if v == State.Jump.Enabled then return end
    State.Jump.Enabled = v
    if v then Y.startJump() else Y.stopJump() end
end, "Sets JumpPower, or JumpHeight if the game uses JumpHeight.")
Y.NumBox(PlayerTab, "Jump Power", State.Jump.Power, 0, 2000, function(v) State.Jump.Power = v end)
Y.Toggle(PlayerTab, "InfJump", "Infinite Jump", false, function(v) Y.setInfJump(v) end)

Y.Toggle(PlayerTab, "Noclip", "Noclip", false, function(v)
    if v == State.NoclipU.Enabled then return end
    State.NoclipU.Enabled = v
    if v then Noclip.Acquire("User") else Noclip.Release("User") end
end, "Walk through walls.")

PlayerTab:Section({ Title = "Camera View" })
PlayerTab:Dropdown({ Title = "Camera View", Values = { "Default", "First Person", "Third Person" },
    Value = State.Cam.Mode,
    Callback = function(v)
        State.Cam.Mode = v
        Y.setCameraMode(v)
    end })
Y.NumBox(PlayerTab, "Third Person Distance", State.Cam.Distance, 1, 400, function(v)
    State.Cam.Distance = v
    if State.Cam.Mode == "Third Person" then Y.setCameraMode("Third Person") end
end)

PlayerTab:Section({ Title = "Fake Lag" })
Y.Toggle(PlayerTab, "FakeLag", "Fake Lag", false, function(v)
    if v == State.FakeLag.Enabled then return end
    State.FakeLag.Enabled = v
    if v then Y.startFakeLag() else Y.stopFakeLag() end
end, "Briefly freezes you at random so others see you skip / lag. You stutter too.")
Y.NumBox(PlayerTab, "Lag Interval (seconds between stutters)", State.FakeLag.Interval, 0.1, 10, function(v) State.FakeLag.Interval = v end)
Y.NumBox(PlayerTab, "Lag Duration (seconds frozen)", State.FakeLag.Duration, 0.05, 3, function(v) State.FakeLag.Duration = v end)

------------------------------------------------------------
-- PLAYER TAB: visuals
------------------------------------------------------------
PlayerTab:Section({ Title = "Visuals" })
Y.Toggle(PlayerTab, "ESP", "ESP", false, function(v)
    if v == State.ESP.Enabled then return end
    State.ESP.Enabled = v
    if v then Y.startESP() else Y.stopESP() end
end)
PlayerTab:Dropdown({ Title = "ESP Style", Values = { "Aura", "Box", "Both" }, Value = State.ESP.Mode,
    Callback = function(v) State.ESP.Mode = v end })
Y.Toggle(PlayerTab, nil, "ESP: HP",       State.ESP.HP,       function(v) State.ESP.HP = v end)
Y.Toggle(PlayerTab, nil, "ESP: Distance", State.ESP.Distance, function(v) State.ESP.Distance = v end)
Y.Toggle(PlayerTab, nil, "ESP: Team",     State.ESP.Team,     function(v) State.ESP.Team = v end)
Y.Toggle(PlayerTab, nil, "ESP: Hide Teammates", State.ESP.TeamCheck, function(v) State.ESP.TeamCheck = v end)
Y.NumBox(PlayerTab, "ESP Max Distance", State.ESP.MaxDist, 50, 20000, function(v) State.ESP.MaxDist = v end)
Y.NumBox(PlayerTab, "Aura Fill Transparency (0-100)", State.ESP.Fill, 0, 100, function(v) State.ESP.Fill = v end)

Y.Toggle(PlayerTab, "Xray", "X-Ray", false, function(v)
    if v == State.Xray.Enabled then return end
    State.Xray.Enabled = v
    if v then Y.startXray() else Y.stopXray() end
end)
Y.NumBox(PlayerTab, "X-Ray Transparency (1-100)", State.Xray.Transparency, 1, 100, function(v)
    State.Xray.Transparency = v
    if State.Xray.Enabled then
        for part, orig in pairs(XrayOriginals) do
            if part and part.Parent then part.Transparency = math.max(orig, v / 100) end
        end
    end
end)

------------------------------------------------------------
-- PLAYER TAB: combat
------------------------------------------------------------
PlayerTab:Section({ Title = "Aim-bot" })
Y.Toggle(PlayerTab, "Aim", "Aim-bot", false, function(v)
    if v == State.Aim.Enabled then return end
    State.Aim.Enabled = v
    if v then
        State.Aim.Active = true
        Y.startAim()
        Y.notify("Aimbot", "On. Use the draggable AIMBOT button to switch it off/on without opening the menu.", 4)
    else
        Y.stopAimbot(false)
    end
end, "Shows a draggable ON/OFF button on screen.")
PlayerTab:Dropdown({ Title = "Aim Mode", Values = { "Camera Lock", "Non-Camera Lock" }, Value = State.Aim.Mode,
    Callback = function(v)
        State.Aim.Mode = v
        if v == "Non-Camera Lock" then
            if Y.installSilentHooks() then
                Y.notify("Aimbot", "Non-Camera Lock: your camera stays free, shots are redirected to the target.", 5)
            else
                Y.notify("Aimbot", "Executor lacks hookmetamethod. Camera Lock will be used instead.", 5)
            end
        end
    end })
Y.Toggle(PlayerTab, nil, "Aim: Target Players", State.Aim.Players, function(v) State.Aim.Players = v end)
Y.Toggle(PlayerTab, nil, "Aim: Target NPCs (names from the NPC tab)", State.Aim.Npcs, function(v) State.Aim.Npcs = v end)
PlayerTab:Dropdown({ Title = "Aim Part", Values = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" },
    Value = State.Aim.Part, Callback = function(v) State.Aim.Part = v end })
Y.NumBox(PlayerTab, "Aim FOV", State.Aim.FOV, 10, 1500, function(v) State.Aim.FOV = v end)
Y.NumBox(PlayerTab, "Aim Smoothness (Camera Lock only, 0 = instant)", State.Aim.Smooth, 0, 100, function(v) State.Aim.Smooth = v end)
Y.Toggle(PlayerTab, nil, "Aim: Team Check", State.Aim.TeamCheck, function(v) State.Aim.TeamCheck = v end)
Y.Toggle(PlayerTab, nil, "Aim: Wall Check", State.Aim.WallCheck, function(v) State.Aim.WallCheck = v end)
if not Platform.Mobile then
    Y.Toggle(PlayerTab, nil, "Aim: Hold Right Click (Camera Lock)", State.Aim.HoldRMB, function(v) State.Aim.HoldRMB = v end)
    PlayerTab:Input({ Title = "Aim On/Off Key", Desc = "Press this key to switch the aimbot on/off", Value = State.Aim.KillKey,
        Placeholder = "K",
        Callback = function(txt)
            local t = tostring(txt or ""):gsub("%s", "")
            if t ~= "" and Enum.KeyCode[t:upper()] then State.Aim.KillKey = t:upper()
            else Y.notify("Aim On/Off Key", "Unknown key name.", 2) end
        end })
end
Y.Toggle(PlayerTab, nil, "Aim: Show FOV Circle", State.Aim.ShowFOV, function(v) State.Aim.ShowFOV = v end)

PlayerTab:Section({ Title = "Aim-bot Prediction" })
Y.Toggle(PlayerTab, nil, "Prediction (lead moving targets)", State.Aim.Predict, function(v) State.Aim.Predict = v end,
    "Aims beside the part, ahead of where they are going. Running at you = normal aim.")
Y.NumBox(PlayerTab, "Prediction Time (seconds)", State.Aim.PredictTime, 0, 2, function(v) State.Aim.PredictTime = v end)
Y.NumBox(PlayerTab, "Projectile Speed (0 = use time above)", State.Aim.ProjSpeed, 0, 10000, function(v) State.Aim.ProjSpeed = v end)
Y.Toggle(PlayerTab, nil, "Predict Vertical Movement", State.Aim.PredictVertical, function(v) State.Aim.PredictVertical = v end)

------------------------------------------------------------
-- PLAYER TAB: ultra instincts
------------------------------------------------------------
PlayerTab:Section({ Title = "Ultra Instincts" })
Y.Toggle(PlayerTab, "Ultra", "Ultra Instincts (teleport dodge)", false, function(v)
    if v == State.Ultra.Enabled then return end
    State.Ultra.Enabled = v
    if v then Y.startUltra() else Y.fmaid("Ultra"):Destroy() end
end)
Y.NumBox(PlayerTab, "Reaction Delay (ms, 0 = instant)", 0, 0, 1000, function(v) State.Ultra.Delay = v / 1000 end)
Y.NumBox(PlayerTab, "Detection Range", State.Ultra.Range, 5, 200, function(v) State.Ultra.Range = v end)
Y.NumBox(PlayerTab, "Teleport Min Distance", State.Ultra.MinTP, 4, 80,
    function(v) State.Ultra.MinTP = v; State.Ultra.MaxTP = math.max(State.Ultra.MaxTP, v + 1) end)
Y.NumBox(PlayerTab, "Teleport Max Distance", State.Ultra.MaxTP, 6, 120,
    function(v) State.Ultra.MaxTP = math.max(v, State.Ultra.MinTP + 1) end)
Y.NumBox(PlayerTab, "Dodge Cooldown (ms)", math.floor(State.Ultra.Cooldown * 1000), 100, 5000,
    function(v) State.Ultra.Cooldown = v / 1000 end)
Y.NumBox(PlayerTab, "Dash Detect Speed", State.Ultra.DashSpeed, 20, 300, function(v) State.Ultra.DashSpeed = v end)
Y.Toggle(PlayerTab, nil, "Detect Dashes / Rushes", State.Ultra.Dash, function(v) State.Ultra.Dash = v end)
Y.Toggle(PlayerTab, nil, "Detect Projectiles", State.Ultra.Projectiles, function(v) State.Ultra.Projectiles = v end)
Y.Toggle(PlayerTab, nil, "Strict Animation Filter", State.Ultra.Strict, function(v) State.Ultra.Strict = v end)
Y.Toggle(PlayerTab, nil, "Ignore Teammates", State.Ultra.TeamCheck, function(v) State.Ultra.TeamCheck = v end)
Y.Toggle(PlayerTab, nil, "After-image Effect", State.Ultra.Ghost, function(v) State.Ultra.Ghost = v end)
local dodgeInput = PlayerTab:Input({ Title = "Dodge Animation ID (optional)", Placeholder = "e.g. 1234567890",
    Callback = function(v) State.Ultra.AnimId = v or "" end })
Y.SavedListUI(PlayerTab, "dodge", "Dodge Animation", function() return State.Ultra.AnimId end, function(id)
    State.Ultra.AnimId = id
    pcall(function() dodgeInput:Set(id) end)
    Y.notify("Dodge Animation", "Using saved ID " .. id, 2)
end)

------------------------------------------------------------
-- AVATAR TAB
------------------------------------------------------------
AvatarTab:Section({ Title = "Rig" })
AvatarTab:Paragraph({
    Title = "R6 / R15",
    Desc  = "Uses Roblox's own avatar prompt, then respawns you. This changes your saved avatar type. "
         .. "Games that force a rig will ignore it.",
})
AvatarTab:Button({ Title = "R6 to R15", Callback = function() Y.switchRig(Enum.HumanoidRigType.R15) end })
AvatarTab:Button({ Title = "R15 to R6", Callback = function() Y.switchRig(Enum.HumanoidRigType.R6) end })

AvatarTab:Section({ Title = "Body" })
Y.Toggle(AvatarTab, "Invis", "Invisible", false, function(v)
    if v then
        Y.startInvis()
    else
        if Invis.On then Y.stopInvis() end
        State.Invis.Enabled = false
    end
end, "Turns off Fly/Spin/Fling/Orbit/Ragdoll/Freeze/Attach when enabled. Your clone can't use tools.")
Y.Toggle(AvatarTab, "Ragdoll", "Ragdoll", false, function(v)
    if v == State.Ragdoll.Enabled then return end
    State.Ragdoll.Enabled = v
    if v then Y.ragdollOn() else Y.ragdollOff() end
end)
Y.Toggle(AvatarTab, "Freeze", "Freeze", false, function(v)
    if v == State.Freeze.Enabled then return end
    State.Freeze.Enabled = v
    if v then Y.startFreeze() else Y.stopFreeze() end
end, "Locks your character in place. Turn off to move again.")
Y.Toggle(AvatarTab, nil, "Freeze: also freeze animation pose", State.Freeze.Pose, function(v)
    State.Freeze.Pose = v
    if not v and State.Freeze.Enabled then
        local h = Y.getHum()
        local animator = h and h:FindFirstChildOfClass("Animator")
        if animator then
            for _, t in ipairs(animator:GetPlayingAnimationTracks()) do pcall(function() t:AdjustSpeed(1) end) end
        end
    end
end)

AvatarTab:Section({ Title = "Bundle Pack Animation" })
AvatarTab:Paragraph({
    Title = "How it works",
    Desc  = "Place a Bundle ID (or a single animation-pack asset ID). It replaces your Idle / Walk / Run / "
         .. "Jump / Fall / Climb / Swim animations. Pick which parts to equip, or keep All.",
})
local bundleInput = AvatarTab:Input({ Title = "Bundle / Pack ID", Placeholder = "Paste the bundle ID here",
    Callback = function(v) State.Bundle.Id = v or "" end })
AvatarTab:Dropdown({ Title = "Parts to equip", Values = { "All", "Idle", "Walk", "Run", "Jump", "Fall", "Climb", "Swim", "Swim Idle" },
    Value = { "All" }, Multi = true,
    Callback = function(v) State.Bundle.Parts = v end })
Y.Toggle(AvatarTab, nil, "Keep pack after respawn", State.Bundle.Keep, function(v) State.Bundle.Keep = v end)
AvatarTab:Button({ Title = "Equip Pack", Callback = Y.equipPack })
AvatarTab:Button({ Title = "Reset to default animations", Callback = Y.resetPack })
Y.SavedListUI(AvatarTab, "bundle", "Bundle", function() return State.Bundle.Id end, function(id)
    State.Bundle.Id = id
    pcall(function() bundleInput:Set(id) end)
    Y.equipPack()
end)

AvatarTab:Section({ Title = "Emote Animation" })
local emoteInput = AvatarTab:Input({ Title = "Emote ID", Placeholder = "Paste the emote / animation ID here",
    Callback = function(v) State.Anim.Id = v or "" end })
Y.NumBox(AvatarTab, "Emote Speed", State.Anim.Speed, 0.1, 10, function(v)
    State.Anim.Speed = v
    if State.Anim.Track then State.Anim.Track:AdjustSpeed(v) end
end)
Y.Toggle(AvatarTab, nil, "Loop Emote", State.Anim.Looped, function(v)
    State.Anim.Looped = v
    if State.Anim.Track then State.Anim.Track.Looped = v end
end)
AvatarTab:Button({ Title = "Play Emote", Callback = Y.playAnim })
AvatarTab:Button({ Title = "Stop Emote", Callback = Y.stopAnim })
Y.SavedListUI(AvatarTab, "emote", "Emote", function() return State.Anim.Id end, function(id)
    State.Anim.Id = id
    pcall(function() emoteInput:Set(id) end)
    Y.playAnim()
end)

------------------------------------------------------------
-- INTERACT TAB (selected player)
------------------------------------------------------------
InteractTab:Section({ Title = "Selected Player" })
UI.Dropdowns.Target = InteractTab:Dropdown({
    Title = "Selected Player",
    Values = Y.playerNames(),
    Callback = function(v) State.Target = v end,
})
InteractTab:Button({ Title = "Clear Selected Player", Callback = function()
    State.Target = nil
    Y.notify("Selected Player", "Cleared.", 2)
end })

InteractTab:Section({ Title = "Attach [FE]" })
Y.Toggle(InteractTab, "Headsit", "Headsit", false, function(v) Y.attachToggle("Headsit", "Headsit", v) end,
    "Sit on the selected player's head.")
Y.NumBox(InteractTab, "Headsit Height", State.Attach.HeadOffset, -3, 6, function(v) State.Attach.HeadOffset = v end)
Y.Toggle(InteractTab, "Cape", "Cape", false, function(v) Y.attachToggle("Cape", "Cape", v) end,
    "Your body hangs on their back like a cape and sways when they move.")
Y.NumBox(InteractTab, "Cape Distance", State.Attach.CapeDist, 0, 6, function(v) State.Attach.CapeDist = v end)
Y.Toggle(InteractTab, "Hang", "Hang on Back", false, function(v) Y.attachToggle("Hang", "Hang", v) end,
    "Hug the selected player's back.")
Y.NumBox(InteractTab, "Hang Distance", State.Attach.HangDist, 0, 6, function(v) State.Attach.HangDist = v end)

InteractTab:Section({ Title = "Orbit / Fling / Spin" })
Y.Toggle(InteractTab, "Orbit", "Orbit Player", false, function(v)
    if v == State.Orbit.Enabled then return end
    State.Orbit.Enabled = v
    if v then
        if not State.Target then Y.notify("Orbit", "Pick a selected player first.") end
        Y.startOrbit()
    else Y.stopOrbit() end
end)
Y.NumBox(InteractTab, "Orbit Speed", State.Orbit.Speed, 0.1, 50, function(v) State.Orbit.Speed = v end)
Y.NumBox(InteractTab, "Orbit Radius", State.Orbit.Radius, 1, 100, function(v) State.Orbit.Radius = v end)
Y.NumBox(InteractTab, "Orbit Height", State.Orbit.Height, -50, 100, function(v) State.Orbit.Height = v end)

Y.Toggle(InteractTab, "Fling", "Fling", false, function(v)
    if v == State.Fling.Enabled then return end
    State.Fling.Enabled = v
    if v then Y.startFling() else Y.stopFling() end
end)
Y.Toggle(InteractTab, nil, "Fling: Target Everyone", State.Fling.All, function(v) State.Fling.All = v end)

Y.Toggle(InteractTab, "Spin", "Spin", false, function(v)
    if v == State.Spin.Enabled then return end
    State.Spin.Enabled = v
    if v then Y.startSpin() else Y.stopSpin() end
end)
Y.NumBox(InteractTab, "Spin Speed", State.Spin.Speed, 1, 500, function(v) State.Spin.Speed = v end)

------------------------------------------------------------
-- TOOLS TAB
------------------------------------------------------------
ToolsTab:Section({ Title = "TP Tool [FE]" })
ToolsTab:Button({ Title = "Get TP Tool", Callback = function()
    Y.giveTPTool()
    Y.notify("TP Tool", "Equip it, then click/tap to teleport.", 3)
end })
ToolsTab:Button({ Title = "Remove TP Tool", Callback = function()
    State.TPTool.Given = false
    Y.removeTool("TP Tool")
end })
Y.NumBox(ToolsTab, "TP Height Offset", State.TPTool.Height, 0, 50, function(v) State.TPTool.Height = v end)

ToolsTab:Section({ Title = "Platform Tool [Half FE]" })
ToolsTab:Paragraph({
    Title = "How it works",
    Desc  = "Click/tap with the tool to place a platform under your feet. Others can't see the platform, "
         .. "but they see you standing on air. Click again in mid-air to stack higher.",
})
ToolsTab:Button({ Title = "Get Platform Tool", Callback = function()
    Y.givePlatformTool()
    Y.notify("Platform", "Equip it, then click/tap to place a platform.", 3)
end })
ToolsTab:Button({ Title = "Remove Platform Tool + Platform", Callback = function()
    State.PlatTool.Given = false
    Y.fmaid("PlatFollow"):Destroy()
    Y.removeTool("Platform")
    Y.destroyPlatform()
end })
Y.NumBox(ToolsTab, "Platform Size (studs)", State.PlatTool.Size, 2, 2048, function(v)
    State.PlatTool.Size = v; Y.applyPlatformProps()
end)
Y.NumBox(ToolsTab, "Platform Thickness", State.PlatTool.Thick, 0.2, 50, function(v)
    State.PlatTool.Thick = v; Y.applyPlatformProps()
end)
Y.NumBox(ToolsTab, "Platform Transparency (0-100)", State.PlatTool.Trans * 100, 0, 100, function(v)
    State.PlatTool.Trans = v / 100; Y.applyPlatformProps()
end)
Y.Toggle(ToolsTab, nil, "Platform follows you (while tool is equipped)", State.PlatTool.Follow,
    function(v) State.PlatTool.Follow = v end)

ToolsTab:Section({ Title = "Set To Point" })
ToolsTab:Paragraph({ Title = "Teleport points", Desc = "Save unlimited positions. They are remembered per game." })
local pointNameDraft = ""
ToolsTab:Input({ Title = "Point name (optional)", Placeholder = "e.g. Base", Callback = function(v) pointNameDraft = v or "" end })
ToolsTab:Button({ Title = "Set Point Here", Callback = function() Y.ptAdd(pointNameDraft) end })
Y.Toggle(ToolsTab, "PointEsp", "Points ESP (show where they are)", State.Points.Esp, function(v)
    State.Points.Esp = v
    Y.ptBuildEsp()
end)

ToolsTab:Section({ Title = "Tp Point" })
Points.tpDd = ToolsTab:Dropdown({ Title = "Teleport points (open the list)", Values = Y.ptNames(),
    Callback = function(v) State.Points.Selected = v end })
ToolsTab:Button({ Title = "Teleport to selected", Callback = function() Y.ptTeleport(State.Points.Selected) end })
ToolsTab:Button({ Title = "Delete selected point", Callback = function() Y.ptDelete(State.Points.Selected) end })

ToolsTab:Section({ Title = "Order (teleport in sequence)" })
Points.routeEl = ToolsTab:Paragraph({ Title = "Current order", Desc = Y.ptRouteText() })
ToolsTab:Button({ Title = "Add selected to Order", Callback = function()
    local name = State.Points.Selected
    if not (name and Y.ptFind(name)) then return Y.notify("Order", "Pick a point first.", 3) end
    State.Points.Route[#State.Points.Route + 1] = name
    Y.ptRefreshUI()
end })
ToolsTab:Button({ Title = "Remove last from Order", Callback = function()
    table.remove(State.Points.Route)
    Y.ptRefreshUI()
end })
ToolsTab:Button({ Title = "Clear Order", Callback = function()
    State.Points.Route = {}
    Y.ptRefreshUI()
end })
Y.NumBox(ToolsTab, "Delay between points (seconds)", State.Points.Delay, 0, 60, function(v) State.Points.Delay = v end)
Y.Toggle(ToolsTab, nil, "Loop the Order", State.Points.Loop, function(v) State.Points.Loop = v end)
ToolsTab:Button({ Title = "Run Order", Callback = Y.ptRunRoute })
ToolsTab:Button({ Title = "Stop Order", Callback = Y.ptStopRoute })

------------------------------------------------------------
-- NPC TAB
------------------------------------------------------------
NpcTab:Section({ Title = "NPC / Anomaly List" })
NpcTab:Paragraph({
    Title = "How it works",
    Desc  = "Type the name of the NPC / anomaly exactly as it appears in Workspace and add it to the list. "
         .. "Aimbot targeting is switched on in the Player tab. Kill / delete / fling / drain only show for "
         .. "other players if your client owns that NPC, otherwise they are local to you.",
})
local npcDraft, npcSelected = "", nil
NpcTab:Input({ Title = "NPC / Anomaly name", Placeholder = "e.g. Zombie", Callback = function(v) npcDraft = v or "" end })
NpcTab:Button({ Title = "Add name to list", Callback = function() Y.addNpcName(npcDraft) end })
UI.Dropdowns.Npc = NpcTab:Dropdown({ Title = "Names in the list", Values = { table.unpack(State.Npc.List) },
    Callback = function(v) npcSelected = v end })
NpcTab:Button({ Title = "Remove selected name", Callback = function() Y.removeNpcName(npcSelected) end })
NpcTab:Button({ Title = "Clear list", Callback = function()
    State.Npc.List = {}
    npcSelected = nil
    Y.npcListRefresh()
end })
NpcTab:Button({ Title = "Scan & add nearby NPC names (150 studs)", Callback = function() Y.scanNearbyNames(150) end })
Y.Toggle(NpcTab, nil, "Partial name match", State.Npc.Partial, function(v)
    State.Npc.Partial = v
    NpcCache.last = 0
end, "Off = exact name. On = any name that contains the text.")
NpcTab:Button({ Title = "Count matching NPCs now", Callback = function()
    Y.notify("NPC", #Y.scanNpcs() .. " matching NPC(s) found.", 3)
end })

NpcTab:Section({ Title = "NPC Features" })
Y.Toggle(NpcTab, "FlingNpc", "Fling NPC", false, function(v)
    if v == State.Npc.Fling then return end
    State.Npc.Fling = v
    if v then
        if #State.Npc.List == 0 then Y.notify("Fling NPC", "Add an NPC name to the list first.", 4) end
        Y.startFlingNpc()
    else
        Y.stopFlingNpc()
    end
end)
NpcTab:Button({ Title = "Delete NPCs (from list)", Callback = function() Y.deleteNpcs(false) end })
Y.Toggle(NpcTab, nil, "Loop delete NPCs", State.Npc.LoopDelete, function(v) Y.setLoopDelete(v) end)
Y.Toggle(NpcTab, nil, "Drain NPC HP", State.Npc.Drain, function(v)
    if v and #State.Npc.List == 0 then Y.notify("Drain NPC HP", "Add an NPC name to the list first.", 4) end
    Y.setDrain(v)
end)
Y.NumBox(NpcTab, "Drain rate (HP per second)", State.Npc.DrainRate, 1, 100000, function(v) State.Npc.DrainRate = v end)
NpcTab:Button({ Title = "Kill NPCs now", Callback = Y.killNpcs })

------------------------------------------------------------
-- WORLD TAB (client-side only)
------------------------------------------------------------
WorldTab:Section({ Title = "Weather [Not FE]" })
WorldTab:Dropdown({
    Title = "Weather",
    Values = { "Clear", "Rain", "Thunderstorm", "Snow", "Fog", "Sandstorm", "Sunset", "Night" },
    Value = "Clear",
    Callback = function(v)
        State.Weather.Name = v
        Y.applyWeather(v, State.Weather.Intensity)
    end,
})
Y.NumBox(WorldTab, "Weather Intensity (1-100)", State.Weather.Intensity, 1, 100, function(v)
    State.Weather.Intensity = v
    if State.Weather.Name ~= "Clear" then Y.applyWeather(State.Weather.Name, v) end
end)

WorldTab:Section({ Title = "Visibility [Not FE]" })
Y.Toggle(WorldTab, "NoFog", "No Fog", false, function(v)
    if v == State.NoFog.Enabled then return end
    State.NoFog.Enabled = v
    if v then Y.lfEnable("NoFog", Y.noFogStep) else Y.lfDisable("NoFog") end
end)
Y.Toggle(WorldTab, "NoDark", "No Darkness", false, function(v)
    if v == State.NoDark.Enabled then return end
    State.NoDark.Enabled = v
    if v then Y.lfEnable("NoDark", Y.noDarkStep) else Y.lfDisable("NoDark") end
end, "Lifts shadows and dark ambient light.")
Y.Toggle(WorldTab, "FullBright", "Full Brightness", false, function(v)
    if v == State.FullBright.Enabled then return end
    State.FullBright.Enabled = v
    if v then Y.lfEnable("FullBright", Y.fullBrightStep) else Y.lfDisable("FullBright") end
end, "Daytime, max light, no shadows.")

WorldTab:Section({ Title = "RTX [Not FE]" })
WorldTab:Paragraph({
    Title = "WARNING",
    Desc  = "YOU MUST HAVE A GOOD PHONE/PC OR ELSE YOU WILL LAG. Only you see it.",
})
WorldTab:Dropdown({ Title = "RTX Quality", Values = { "Low", "Medium", "High", "Ultra" }, Value = State.RTX.Quality,
    Callback = function(v)
        State.RTX.Quality = v
        if State.RTX.Enabled then Y.rtxOn(v) end
    end })
Y.Toggle(WorldTab, "RTX", "Turn on RTX", false, function(v)
    if v == State.RTX.Enabled then return end
    State.RTX.Enabled = v
    if v then Y.rtxOn(State.RTX.Quality) else Y.rtxOff() end
end)

------------------------------------------------------------
-- Dropdown refresh + respawn handling
------------------------------------------------------------
function Y.refreshDropdowns()
    local names = Y.playerNames()
    if UI.Dropdowns.Target then pcall(function() UI.Dropdowns.Target:Refresh(names) end) end
end
MainMaid:Give(Players.PlayerAdded:Connect(Y.refreshDropdowns))
MainMaid:Give(Players.PlayerRemoving:Connect(function() task.defer(Y.refreshDropdowns) end))

MainMaid:Give(LocalPlayer.CharacterAdded:Connect(function(c)
    -- swaps caused by Invisible are ours, ignore them
    if Invis.On and (c == Invis.Fake or c == Invis.Real) then return end
    if Invis.On then
        Invis.On = false
        State.Invis.Enabled = false
        Y.fmaid("Invis"):Destroy()
        if Invis.Fake then pcall(function() Invis.Fake:Destroy() end) end
        Invis.Real, Invis.Fake = nil, nil
        Y.setToggle("Invis", false)
    end
    task.wait(0.6)
    State.Ultra.Adapt = 1
    local h = Y.getHum()
    if h then
        if h.WalkSpeed >= 1 then defaultWalkSpeed = h.WalkSpeed end
        if h.JumpPower >= 1 then defaultJumpPower = h.JumpPower end
        if h.JumpHeight >= 0.5 then defaultJumpHeight = h.JumpHeight end
    end
    if State.Fly.Enabled     then Y.startFly()     end
    if State.Speed.Enabled   then Y.startSpeed()   end
    if State.Jump.Enabled    then Y.startJump()    end
    if State.Jump.Inf        then Y.setInfJump(true) end
    if State.Orbit.Enabled   then Y.startOrbit()   end
    if State.Fling.Enabled   then Y.startFling()   end
    if State.Spin.Enabled    then Y.startSpin()    end
    if State.Ragdoll.Enabled then Y.ragdollOn()    end
    if State.Freeze.Enabled  then Y.startFreeze()  end
    if Attach.Mode           then Y.startAttach(Attach.Mode) end
    if State.TPTool.Given    then Y.giveTPTool()   end
    if State.PlatTool.Given  then Y.givePlatformTool() end
    if State.Bundle.Slots and State.Bundle.Keep then Y.applyPack(State.Bundle.Slots, State.Bundle.Parts) end
end))

------------------------------------------------------------
-- Launch
------------------------------------------------------------
Y.startWatchdog()
Y.ptRefreshUI()
Y.notify("Yenrenuton [OUT OF ALPHA]",
    Platform.Mobile and "Loaded. Close the menu and use the open button to bring it back."
    or "Loaded. RightShift toggles the UI, or use the open button after closing.", 5)
