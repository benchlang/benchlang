local path = os.getenv("LUA_PATH") or "lua"

local f = io.popen(path.." -v")
local version = f:read("*a")
f:close()

return {
  version = 1,
  title = "PUC-Lua",
  description = [[
https://www.lua.org/

Official VM implementation (latest).
  ]],
  host_info = version,
  build = function(impl_path, tmp_path) return true end,
  run_cmd = function(impl_path, tmp_path, ...) return path, impl_path, ... end
}