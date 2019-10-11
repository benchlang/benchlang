-- requires LuaJIT
local host = ...

local ffi = require("ffi")
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
void set_signal_handler(void (*handler)(int));
]])
local lib = ffi.load("benchmark")

local subproc = ffi.new("subproc_t")

-- capture end of child (subproc) process
lib.set_signal_handler(function(signal)
  subproc.time = lib.mclock()-subproc.start_time
end)

-- return output string or nil on failure
local function measure_subproc(args, timeout)
  -- convert to C args
  if #args < 1 then return end
  local cargs = ffi.new("const char*[?]", #args+1, args)
  cargs[#args] = nil

  -- create sub process
  if lib.subproc_create(ffi.cast("char * const*", cargs), subproc) then
    print(tonumber(subproc.pid), unpack(args)) -- debug
    local outs = {}
    local data = ffi.new("char[4096]")

    -- read output, check for timeout
    local n = lib.subproc_step(subproc, data, 4096, 100)

    while n ~= 0 or subproc.running do -- read all output and wait end of process
      print("read",n,subproc.running) -- debug
      if n > 0 then table.insert(outs, ffi.string(data, n)) end -- append output

      -- timeout check
      if lib.mclock()-subproc.start_time > 5 then
        lib.subproc_kill(subproc)
      end

      n = lib.subproc_step(subproc, data, 4096, 100)
    end

    lib.subproc_close(subproc)

    print(subproc.status, subproc.time, subproc.utime, subproc.stime, tonumber(subproc.maxrss)) -- debug

    if subproc.status == 0 then
      return table.concat(outs)
    end
  end
end

local function compute_work(host, lang, work, env, impl)
end

measure_subproc({"ls", "-a"})
measure_subproc({"sleep", "3"})
measure_subproc({"sleep", "20"})
measure_subproc({"luajit", "-e", "while true do end"})
measure_subproc({"dsfslfdkjflk", "3"})
