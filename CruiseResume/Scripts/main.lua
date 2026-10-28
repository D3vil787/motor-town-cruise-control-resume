-- CruiseResume v0.5 (прототип) - Resume для штатного круиз-контроля Motor Town.
--
-- Как работает:
--   * мод следит за табло круиза и запоминает скорость, на которой круиз был включён;
--   * по F7 (если круиз выключен): включает штатный круиз (клавиша 5) и жмёт Page Up / Page Down,
--     пока скорость круиза не станет равна запомненной;
--   * клавиши "нажимает" маленький помощник keyhelper.ps1 (обычный ввод Windows), и только
--     когда активно окно игры. Данные игры мод не меняет.
--
-- Клавиши мода:  F7 = Resume,  F9 = вкл/выкл мод (на время чата!),  F6 = подробный лог,  F8 = статус

local UEHelpers = require("UEHelpers")

---------------------------------------------------------------------------
-- НАСТРОЙКИ
---------------------------------------------------------------------------
local CFG = {
    RESUME_KEY       = Key.F7,
    DISABLE_KEY      = Key.F9,
    DEBUG_KEY        = Key.F6,
    STATUS_KEY       = Key.F8,

    -- клавиши игры (как у тебя назначены) - имена см. в keyhelper.ps1
    TOGGLE_KEY       = "5",       -- Toggle Cruise Control
    INC_KEY          = "pgup",    -- Inc Speed
    DEC_KEY          = "pgdn",    -- Dec Speed

    MIN_SAVE_KMH     = 15,        -- ниже этой скорости не запоминаем
    POLL_MS          = 150,       -- как часто смотреть на табло
    BURST            = 15,        -- сколько нажатий +/- за один круг (шаг круиза = 1 км/ч)
    TAP_MS           = 90,        -- примерное время одного нажатия у помощника
    SETTLE_MS        = 350,       -- пауза после пачки нажатий перед перечитыванием табло
    MAX_ROUNDS       = 25,        -- предохранитель
}

---------------------------------------------------------------------------
-- УТИЛИТЫ
---------------------------------------------------------------------------
local function log(s) print("[CruiseResume] " .. tostring(s) .. "\n") end

local function valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v
end

local function fullname(o)
    local ok, n = pcall(function() return o:GetFullName() end)
    return ok and n or "?"
end

local function addrOf(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    if ok then return a end
    return nil
end

local function getPawn()
    local ok, pc = pcall(function() return UEHelpers.GetPlayerController() end)
    if not ok or not valid(pc) then return nil, nil end
    local pawn
    pcall(function() pawn = pc.Pawn end)
    if not valid(pawn) then return pc, nil end
    return pc, pawn
end

local function speedKmh(pawn)
    local ok, v = pcall(function() return pawn:GetVelocity() end)
    if not ok or not v then return nil end
    return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) * 0.036
end

local function toast(pc, msg)
    log(msg)
    if pc then pcall(function() pc:ClientMessage(msg) end) end
end

local function later(ms, fn)
    ExecuteWithDelay(ms, function() ExecuteInGameThread(fn) end)
end

---------------------------------------------------------------------------
-- ПУТИ И ПОМОЩНИК
---------------------------------------------------------------------------
local modDir
do
    local src = ""
    pcall(function() src = debug.getinfo(1, "S").source or "" end)
    src = src:gsub("^@", "")
    modDir = src:match("^(.*)[\\/]Scripts[\\/][^\\/]*$")
end
if not modDir then
    modDir = [[G:\SteamLibrary\steamapps\common\Motor Town\MotorTown\Binaries\Win64\ue4ss\Mods\CruiseResume]]
end
local qDir       = modDir .. [[\q]]
local aliveFile  = modDir .. [[\alive.txt]]
local helperPath = modDir .. [[\helper\keyhelper.ps1]]

local function helperAlive()
    local f = io.open(aliveFile, "r")
    if not f then return false end
    local s = f:read("*a")
    f:close()
    local t = tonumber((s or ""):match("%d+"))
    return t ~= nil and (os.time() - t) <= 6
end

local stdoutFile = modDir .. [[\helper_stdout.log]]

local function startHelper()
    if helperAlive() then return true end
    -- вывод помощника (в т.ч. ошибки PowerShell) пишем в helper_stdout.log
    local inner = "& '" .. helperPath .. "' -QueueDir '" .. qDir .. "' *> '" .. stdoutFile .. "'"
    local cmd = 'start "" /B powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "'
        .. inner .. '"'
    local ok, a, b, c = pcall(function() return os.execute(cmd) end)
    log(string.format("запуск помощника: pcall=%s os.execute=%s/%s/%s", tostring(ok), tostring(a), tostring(b), tostring(c)))
    return ok
end

local seq = 0
local function sendTap(name, quiet)
    seq = seq + 1
    local path = string.format("%s\\%d_%04d.cmd", qDir, os.time(), seq)
    local f = io.open(path, "w")
    if not f then
        log("НЕ УДАЛОСЬ записать команду в " .. path .. " (папка q есть?)")
        return false
    end
    f:write("tap " .. name)
    f:close()
    if not quiet then log("tap " .. name) end
    return true
end

---------------------------------------------------------------------------
-- ТАБЛО КРУИЗА
---------------------------------------------------------------------------
local hud = { tb = nil, vb = nil, lastFind = -10 }

local function findHud()
    local now = os.clock()
    if now - hud.lastFind < 1.0 then return end
    hud.lastFind = now
    pcall(function()
        local tbs = FindAllOf("TextBlock")
        if tbs then
            for _, t in ipairs(tbs) do
                if valid(t) and t:GetFName():ToString() == "CruiseControlSpeedTextBlock"
                    and string.find(fullname(t), "Transient", 1, true) then
                    hud.tb = t break
                end
            end
        end
    end)
    pcall(function()
        local vbs = FindAllOf("VerticalBox")
        if vbs then
            for _, v in ipairs(vbs) do
                if valid(v) and v:GetFName():ToString() == "CruiseControlVerticalBox"
                    and string.find(fullname(v), "Transient", 1, true) then
                    hud.vb = v break
                end
            end
        end
    end)
end

-- возвращает { on = bool|nil, text = string|nil, target = number|nil }
local function readCruise()
    if not (hud.tb and valid(hud.tb) and hud.vb and valid(hud.vb)) then
        hud.tb, hud.vb = nil, nil
        findHud()
    end
    local res = {}
    if hud.vb and valid(hud.vb) then
        local ok, v = pcall(function() return hud.vb:GetVisibility() end)
        if ok and type(v) == "number" then
            res.vis = v
            res.on = not (v == 1 or v == 2)   -- 1=Collapsed, 2=Hidden -> выключен
        end
    end
    if hud.tb and valid(hud.tb) then
        pcall(function() res.text = hud.tb:GetText():ToString() end)
        if res.text then
            local n = tonumber(res.text:match("%d+%.?%d*"))
            if n then res.target = n end
        end
    end
    return res
end

---------------------------------------------------------------------------
-- СОСТОЯНИЕ
---------------------------------------------------------------------------
local enabled   = true
local debugLog  = false
local saved     = nil      -- запомненная скорость круиза, км/ч
local prevOn    = nil
local prevSpd   = 0
local stable    = 0
local lastPawn  = nil
local resuming  = false
local lastDbg   = 0

local function setSaved(v, why)
    if saved ~= v then
        saved = v
        log(string.format("запомнено: %s км/ч (%s)", tostring(v), why or "-"))
    end
end

local function tick()
    if not enabled then return end
    local pc, pawn = getPawn()
    if not pawn then return end

    local a = addrOf(pawn)
    if a ~= lastPawn then
        lastPawn = a
        saved = nil
        prevOn = nil
        log("новая машина: " .. fullname(pawn))
    end

    local c = readCruise()
    local spd = speedKmh(pawn) or 0

    if c.on ~= prevOn then
        log(string.format("КРУИЗ %s  (speed=%.1f, hudText=%s, vis=%s)", c.on and "ВКЛ" or "ВЫКЛ",
            spd, tostring(c.text), tostring(c.vis)))
        prevOn = c.on
    end

    if c.on and not resuming then
        if c.target and c.target >= CFG.MIN_SAVE_KMH and c.target < 300 then
            setSaved(c.target, "табло")
        else
            if math.abs(spd - prevSpd) < 0.3 then stable = stable + 1 else stable = 0 end
            if stable >= 6 and spd >= CFG.MIN_SAVE_KMH then
                setSaved(math.floor(spd + 0.5), "по скорости")
            end
        end
    end
    prevSpd = spd

    if debugLog then
        local now = os.clock()
        if now - lastDbg > 1.0 then
            lastDbg = now
            log(string.format("DBG speed=%.1f on=%s hudText=%s vis=%s saved=%s helper=%s", spd,
                tostring(c.on), tostring(c.text), tostring(c.vis), tostring(saved), tostring(helperAlive())))
        end
    end
end

---------------------------------------------------------------------------
-- RESUME
---------------------------------------------------------------------------
local function resume()
    if not enabled then return end
    if resuming then return end
    local pc, pawn = getPawn()
    if not pawn then return end

    if not helperAlive() then
        startHelper()
        log("помощник не запущен - запускаю, повтори F7 через пару секунд")
        return
    end

    local c = readCruise()
    if c.on == nil then log("RESUME: не вижу табло круиза") return end
    if c.on then log("RESUME: круиз уже включён - ничего не делаю") return end
    if not saved then toast(pc, "Resume: нет запомненной скорости") return end

    local S = saved
    resuming = true
    log(string.format("RESUME start: цель %d км/ч, сейчас %.1f км/ч", S, speedKmh(pawn) or -1))
    if not sendTap(CFG.TOGGLE_KEY) then resuming = false return end

    local rounds = 0

    local function finish(msg)
        resuming = false
        log("RESUME: " .. msg)
    end

    -- круг: перечитали цель круиза на табло -> нажали нужное число раз +/- (пачкой) -> подождали
    local function round()
        rounds = rounds + 1
        if rounds > CFG.MAX_ROUNDS then finish("слишком много кругов, стоп") return end
        local _, p = getPawn()
        if not p then finish("машина пропала") return end
        local cur = readCruise()

        if not cur.on then
            if rounds <= 8 then later(150, round) return end
            finish("круиз не включился (клавиша 5 не сработала? смотри helper.log)")
            return
        end

        local T = cur.target
        if not T then
            T = math.floor((speedKmh(p) or 0) + 0.5)
            log("табло без цели - беру текущую скорость как цель: " .. T)
        end

        local diff = S - T
        if diff == 0 then
            finish(string.format("готово: цель круиза %d км/ч", T))
            return
        end

        local n = math.min(math.abs(diff), CFG.BURST)
        local key = (diff > 0) and CFG.INC_KEY or CFG.DEC_KEY
        log(string.format("круг %d: цель круиза %s, нужно %d -> жму %s x%d", rounds, tostring(T), S, key, n))
        for i = 1, n do sendTap(key, true) end
        later(n * CFG.TAP_MS + CFG.SETTLE_MS, round)
    end

    later(400, round)
end

---------------------------------------------------------------------------
-- КЛАВИШИ
---------------------------------------------------------------------------
RegisterKeyBind(CFG.RESUME_KEY, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(resume)
        if not ok then log("resume error: " .. tostring(err)) resuming = false end
    end)
end)

RegisterKeyBind(CFG.DISABLE_KEY, function()
    enabled = not enabled
    log("мод " .. (enabled and "ВКЛЮЧЁН" or "ВЫКЛЮЧЕН (F7 не трогает клавиши)"))
end)

RegisterKeyBind(CFG.DEBUG_KEY, function()
    debugLog = not debugLog
    log("подробный лог: " .. tostring(debugLog))
end)

RegisterKeyBind(CFG.STATUS_KEY, function()
    ExecuteInGameThread(function()
        local _, pawn = getPawn()
        local c = readCruise()
        log("---- STATUS ----")
        log("enabled=" .. tostring(enabled) .. " helper=" .. tostring(helperAlive()) .. " saved=" .. tostring(saved))
        log(string.format("pawn=%s speed=%.1f", pawn and fullname(pawn) or "nil", pawn and (speedKmh(pawn) or -1) or -1))
        log(string.format("cruise on=%s hudText=%s vis=%s", tostring(c.on), tostring(c.text), tostring(c.vis)))
        log("modDir=" .. modDir)
        log("----------------")
    end)
end)

---------------------------------------------------------------------------
-- СТАРТ
---------------------------------------------------------------------------
LoopAsync(CFG.POLL_MS, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(tick)
        if not ok then log("tick error: " .. tostring(err)) end
    end)
    return false
end)

startHelper()
log("v0.5 загружен. F7=Resume, F9=вкл/выкл, F6=подробный лог, F8=статус. modDir=" .. modDir)
