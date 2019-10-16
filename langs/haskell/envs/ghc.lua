
local path = os.getenv("GHC_PATH") or "ghc"

local f = io.popen(path.." --version")
local version = f:read("*a")
f:close()

return {
  version = 1,
  title = "GHC",
  description = [[
https://www.haskell.org/ghc/
  ]],
  host_info = version,
  build = function(impl_path, tmp_path)
    return os.execute(path.." "..impl_path.." -o "..tmp_path.."/run") == 0
  end,
  run_cmd = function(impl_path, tmp_path, ...) return tmp_path.."/run", ... end
}