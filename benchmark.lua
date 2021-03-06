-- requires LuaJIT

local ffi = require("ffi")
local argparse = require("argparse")
local msgpack = require("MessagePack")
local sha2 = require("extern.sha2.sha2")

-- DEF

-- return (true, ...) or (false, err) on failure
local function loadconfig(path)
  local f, err = loadfile(path)
  if f then
    return pcall(f)
  else
    return false, err
  end
end

local C = ffi.C
ffi.cdef([[
typedef struct{
  long int pid;
  int fd_read;
  bool running;
  int status;
  double start_time;
  double time, utime, stime;
  long maxrss;
} subproc_t;

bool subproc_create(char * const argv[], subproc_t *data);
int subproc_step(subproc_t *p, void *buf, size_t count, int timeout);
void subproc_kill(subproc_t *p);
void subproc_close(subproc_t *p);
double mclock();
void bind_signal_handler(subproc_t *p);
]])
local lib = ffi.load("./libbenchmark.so")

local subproc = ffi.new("subproc_t")

-- capture end of child (subproc) process
lib.bind_signal_handler(subproc);

-- hash_output: true to return sha256 of the output, false for plain output
-- return output string or (nil, err) on failure
local function measure_subproc(args, timeout, check_delay, hash_output)
  -- convert to C args
  if #args < 1 then return end
  local cargs = ffi.new("const char*[?]", #args+1, args)
  cargs[#args] = nil

  -- create sub process
  if lib.subproc_create(ffi.cast("char * const*", cargs), subproc) then
    local outs = (hash_output and sha2.sha256() or {})
    local data = ffi.new("char[4096]")

    -- read output, check for timeout
    local n = lib.subproc_step(subproc, data, 4096, check_delay)

    while n ~= 0 or subproc.running do -- read all output and wait end of process
      if n > 0 then -- append output
        if hash_output then
          outs(ffi.string(data, n))
        else
          table.insert(outs, ffi.string(data, n))
        end
      end

      -- timeout check
      if lib.mclock()-subproc.start_time > timeout then
        lib.subproc_kill(subproc)
      end

      n = lib.subproc_step(subproc, data, 4096, check_delay)
    end

    lib.subproc_close(subproc)

    if subproc.status ~= 0 then return nil, "status" end

    -- return hash or plain output
    if hash_output then return outs() else return table.concat(outs) end
  else
    return nil, "spawn"
  end
end

local works = {}
local langs = {}
local host

-- measure work and produce result file
-- lang, env, work, impl: strings
local function measure_work(lang, env, work, impl)
  local lcfg = langs[lang]
  if lcfg then
    local ecfg = lcfg.envs[env]
    if ecfg then
      local wcfg = works[work]
      if wcfg then
        print("build and run measures", lang, env, work, impl)
        local impl_data = lcfg.works_impls[work][impl]

        local env_params = {
          p_impl = "langs/"..lang.."/impls/"..work.."/"..impl,
          p_tmp = "tmp",
          vars = {}
        }

        -- select env vars
        for _, var in ipairs(impl_data.vars) do
          local v_host, v_env, k, v = unpack(var)
          if (#v_host == 0 or v_host == host.name) and (#v_env == 0 or env == v_env) then
            env_params.vars[k] = v
          end
        end

        -- build
        if ecfg.build(env_params) then
          local result = {
            steps = {},
            date = os.date(),
            host_info = ecfg.host_info,
            work_version = wcfg.version,
            env_version = ecfg.version,
            impl_hash = impl_data.hash
          }

          -- measure steps
          for step, params in ipairs(wcfg.steps) do
            local measures = {}
            table.insert(result.steps, measures)

            local ok = true

            for i=1,host.measures do -- sub measures
              local measure = {}
              local args = {ecfg.run_cmd(env_params, unpack(params))}
              print("--", unpack(args))

              local hash_output = (type(wcfg.check) == "table")
              local out, err = measure_subproc(args, host.timeout, host.check_delay, hash_output)

              if err ~= "spawn" then
                measure.status = subproc.status
                measure.maxrss = tonumber(subproc.maxrss)
                measure.time = subproc.time
                measure.stime = subproc.stime
                measure.utime = subproc.utime
              end

              if out then
                if (hash_output and wcfg.check[step] ~= out) or (not hash_output and not wcfg.check(out, unpack(params))) then
                  measure.err = "output"
                end
              else
                measure.err = err
              end

              if measure.err then
                if measure.err == "status" then
                  print("--", "error", measure.err, measure.status)
                else
                  print("--", "error", measure.err)
                end
              else
                print("--", "time", measure.time.."s", "mem", measure.maxrss.." kB")
              end
              table.insert(measures, measure)
            end
          end

          -- write result
          local dir = "results/"..table.concat({host.name, lang, env, work}, "/")
          os.execute("mkdir -p "..dir)
          local f_out, err = io.open(dir.."/"..impl..".data", "w")
          if f_out then
            f_out:write(msgpack.pack(result))
            f_out:close()
          else
            print(err)
          end
        else
          print("--", "build failed")
        end
      end
    end
  end
end

-- popen followed by string match for each line
-- return list of captures {...}
local function popen_match(cmd, pattern)
  local r = {}

  local f = io.popen(cmd)
  local line = f:read("*l")
  while line do
    local captures = {string.match(line, pattern)}
    if #captures > 0 then table.insert(r, captures) end
    line = f:read("*l")
  end
  f:close()

  return r
end

-- EXEC

local parser = argparse(unpack(arg))
parser:argument("host", "Host profile name.")
parser:option("-l --lang", "Languages."):count("*")
parser:option("-w --work", "Works."):count("*")
parser:option("-e --env", "Environments."):count("*")
parser:option("-i --impl", "Implementations."):count("*")
parser:flag("-f --force", "Force recomputation of measures.")

local params = parser:parse()

-- load host
local ok, _host = loadconfig("hosts/"..params.host..".lua")
if not ok then error(_host) else host = _host end
host.name = params.host

-- find works (params or find)
if #params.work == 0 then -- all langs
  local works = popen_match("find works/ -mindepth 1 -maxdepth 1 -type f", "^works/(.*)%.lua$")
  for _, captures in ipairs(works) do
    table.insert(params.work, captures[1])
  end
end

-- load works
for _, work in ipairs(params.work) do
  local ok, cfg = loadconfig("works/"..work..".lua")
  if ok then
    works[work] = cfg
  else
    print(cfg)
  end
end

-- find langs (params or find)
if #params.lang == 0 then -- all langs
  local langs = popen_match("find langs/ -mindepth 1 -maxdepth 1 -type d", "^langs/(.*)$")
  for _, captures in ipairs(langs) do
    table.insert(params.lang, captures[1])
  end
end

-- load langs
for _, lang in ipairs(params.lang) do
  local ok, cfg = loadconfig("langs/"..lang.."/config.lua")
  if ok then
    langs[lang] = cfg

    -- find envs (params or find)
    local p_envs = {}
    for _, env in ipairs(params.env) do table.insert(p_envs, env) end
    if #p_envs == 0 then
      local envs = popen_match("find langs/"..lang.."/envs -mindepth 1 -maxdepth 1 -type f", "^langs/.-/envs/(.*)%.lua$")
      for _, captures in ipairs(envs) do
        table.insert(p_envs, captures[1])
      end
    end

    -- load envs
    cfg.envs = {}
    for _, env in ipairs(p_envs) do
      print("load "..lang.."/"..env.." environment")
      local ok, ecfg = loadconfig("langs/"..lang.."/envs/"..env..".lua")
      if ok then
        cfg.envs[env] = ecfg
        print(ecfg.host_info)
      else
        print(ecfg)
      end
    end

    -- find impls
    cfg.works_impls = {}
    for work in pairs(works) do
      local impls = {} -- map of impl => data {.hash, .vars}
      cfg.works_impls[work] = impls

      local l_impls = {}
      for _, impl in ipairs(params.impl) do table.insert(l_impls, impl) end
      if #l_impls == 0 then
        local f_impls = popen_match("find langs/"..lang.."/impls/"..work.." -type f", "^langs/.-/impls/.-/(.*)$")
        for _, captures in ipairs(f_impls) do
          table.insert(l_impls, captures[1])
        end
      end

      -- compute implementations data
      for _, impl in ipairs(l_impls) do
        local f = io.open("langs/"..lang.."/impls/"..work.."/"..impl)
        if f then
          local data = {}
          impls[impl] = data

          local content = f:read("*a")

          -- compute hash
          data.hash = sha2.sha256(content)

          -- parse vars
          data.vars = {}
          for host, env, k, v in string.gmatch(content, "!BENCHLANG:(.-):(.-)%((.-)%)=%[(.-)%]") do
            table.insert(data.vars, {host, env, k, v})
          end

          f:close()
        end
      end
    end
  else
    print(cfg)
  end
end

local work_todo = {} -- list of {lang, env, work, impl}
do
  -- build index of results
  local results = {}
  local paths = popen_match("find results/"..host.name.." -type f", "^results/.-/(.*)%.data$")
  for _, captures in ipairs(paths) do
    results[captures[1]] = true
  end

  -- build list of work to do
  for lang, lcfg in pairs(langs) do
    for env, ecfg in pairs(lcfg.envs) do
      for work, impls in pairs(lcfg.works_impls) do
        for impl, impl_data in pairs(impls) do
          local wpath = {lang, env, work, impl}

          -- not already computed or force recomputation
          local todo = (params.force or not results[table.concat(wpath, "/")])

          -- check result versions/hashes
          if not todo then
            local f = io.open("results/"..host.name.."/"..table.concat(wpath, "/")..".data")
            if f then
              local result = msgpack.unpack(f:read("*a"))
              todo = (result.env_version ~= ecfg.version
                or result.work_version ~= works[work].version
                or result.impl_hash ~= impl_data.hash)
            else
              todo = true -- couldn't read result data, recompute
            end
          end

          if todo then
            table.insert(work_todo, wpath)
          end
        end
      end
    end
  end
end

-- do measures
os.execute("mkdir -p tmp")
os.execute("mkdir -p results/"..host.name)
print(#work_todo.." result(s) to compute.")
for _, wpath in ipairs(work_todo) do
  measure_work(unpack(wpath))
end
