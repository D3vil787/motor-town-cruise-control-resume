import os, sys
from lupa import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'CruiseResume', 'Scripts', 'main.lua'), encoding='utf-8').read()

harness = r'''
local out = {}
_G.__log = out
local realprint = print
print = function(s) out[#out+1] = (tostring(s):gsub("\n","")) end

-- виртуальная игра
G = { on=false, target=100, speed=47.0, taps={}, time=0, pending={}, now=0 }
local function mkobj(name, getter)
  local o = {}
  o.IsValid = function() return true end
  o.GetFName = function() return { ToString=function() return name end } end
  o.GetFullName = function() return "Transient."..name end
  o.GetAddress = function() return 1234 end
  for k,v in pairs(getter or {}) do o[k]=v end
  return o
end
local tb = mkobj("CruiseControlSpeedTextBlock", { GetText=function() return { ToString=function() return tostring(G.target) end } end })
local vb = mkobj("CruiseControlVerticalBox", { GetVisibility=function() return G.on and 4 or 1 end })
local pawn = mkobj("Golima_Semi_C", { GetVelocity=function() return {X=G.speed/0.036, Y=0, Z=0} end })
local pc = mkobj("PC", { ClientMessage=function(_, m) out[#out+1]="[toast] "..m end })
pc.Pawn = pawn

package.preload["UEHelpers"] = function() return { GetPlayerController=function() return pc end } end
Key = setmetatable({}, { __index=function(_,k) return k end })

keybinds = {}
RegisterKeyBind = function(k, f) keybinds[k] = f end
FindAllOf = function(cls)
  if cls=="TextBlock" then return { tb } elseif cls=="VerticalBox" then return { vb } end
end
ExecuteInGameThread = function(f) f() end
LoopAsync = function(ms, f) _G.__loop = f end
-- отложенные вызовы выполняются по "виртуальному времени"
ExecuteWithDelay = function(ms, f) G.pending[#G.pending+1] = { at=G.now+ms, f=f } end

-- "помощник": пишем в io.open -> перехватываем
local realopen = io.open
io.open = function(path, mode)
  if path:find("%.cmd$") then
    local buf = {}
    return { write=function(_, s) buf[#buf+1]=s end, close=function()
      local cmd = table.concat(buf)
      local key = cmd:match("tap (%S+)")
      G.taps[#G.taps+1] = key
      -- реакция игры
      if key == "5" then G.on = not G.on; if G.on then G.target = math.floor(G.speed+0.5) end
      elseif key == "pgup" and G.on then G.target = G.target + 1
      elseif key == "pgdn" and G.on then G.target = G.target - 1 end
    end }
  end
  if path:find("alive%.txt$") then
    return { read=function() return tostring(os.time()) end, close=function() end }
  end
  return realopen(path, mode)
end
os.execute = function() end
'''
lua.execute(harness)
lua.execute(src)

run = lua.eval('''function(ms)
  -- прокрутить виртуальное время
  local target = G.now + ms
  while G.now < target do
    G.now = G.now + 10
    if G.now % 150 == 0 and __loop then __loop() end
    local keep = {}
    for _, p in ipairs(G.pending) do
      if p.at <= G.now then p.f() else keep[#keep+1] = p end
    end
    G.pending = keep
  end
end''')
press = lua.eval('function(k) keybinds[k]() end')
setg = lua.eval('function(k,v) G[k]=v end')
getg = lua.eval('function(k) return G[k] end')

def dump(title):
    print("\n=== " + title + " ===")
    out = lua.eval('__log')
    for i in range(1, len(out)+1):
        print(out[i])
    lua.execute('for i=#__log,1,-1 do __log[i]=nil end')

# сценарий 1: ехал на круизе 100, снял, едет 47, жмёт R
setg('on', True); setg('target', 100); setg('speed', 100.0)
run(1500); dump("круиз включён на 100")
setg('on', False); setg('speed', 47.0)
run(500); dump("круиз снят")
press('F7'); run(6000); dump("RESUME нажата")
print("taps:", [lua.eval('G.taps')[i] for i in range(1, len(lua.eval('G.taps'))+1)])
print("итог: on=", getg('on'), "target=", getg('target'))
assert getg('on') and getg('target') == 100, "scenario 1 failed"

run(4000); dump("хвост сценария 1")
print("\n\n######## СЦЕНАРИЙ 2: запомнено 60, едет 85 ########")
lua.execute('G.taps = {}')
setg('on', True); setg('target', 60); setg('speed', 60.0)
run(1500); dump("на круизе 60")
setg('on', False); setg('speed', 85.0)
run(500); dump("снят")
press('F7'); run(8000); dump("F7")
t = lua.eval('G.taps'); taps=[t[i] for i in range(1,len(t)+1)]
print("нажатий всего:", len(taps), "первые:", taps[:3], "итог: on=", getg('on'), "target=", getg('target'))
assert getg('on') and getg('target') == 60, "scenario 2 failed"
print("\nOK: both scenarios passed")
