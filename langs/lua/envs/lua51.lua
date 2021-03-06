local path = os.getenv("BL_LUA51_PATH") or "lua5.1"

local f = io.popen(path.." -v 2>&1")
local version = f:read("*a")
f:close()

return {
  version = 1,
  title = "PUC 5.1",
  description = [[
https://www.lua.org/

Official VM implementation (5.1).
  ]],
  host_info = version,
  build = function(e) return true end,
  run_cmd = function(e, ...) return path, e.p_impl, ... end
}
