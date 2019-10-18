--[[
Revised BSD license

This is a specific instance of the Open Source Initiative (OSI) BSD license template
http://www.opensource.org/licenses/bsd-license.php


Copyright © 2004-2008 Brent Fulgham, 2005-2019 Isaac Gouy
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

   Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

   Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

   Neither the name of "The Computer Language Benchmarks Game" nor the name of "The Computer Language Benchmarks Game Benchmarks" nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

-- The Computer Language Benchmarks Game
-- https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
-- contributed by Mike Pall
-- Updated for Lua 5.3 by Robin
-- modified for 5.x by ImagicTheCat

local write, char, unpack = io.write, string.char, table.unpack or unpack
local N = tonumber(arg and arg[1]) or 100
local M, ba, bb, buf = 2/N, 2^(N%8+1)-1, 2^(8-N%8), {}
write("P4\n", N, " ", N, "\n")
for y=0,N-1 do
  local Ci, b, p = y*M-1, 1, 0
  for x=0,N-1 do
    local Cr = x*M-1.5
    local Zr, Zi, Zrq, Ziq = Cr, Ci, Cr*Cr, Ci*Ci
    b = b + b
    for i=1,49 do
      Zi = Zr*Zi*2 + Ci
      Zr = Zrq-Ziq + Cr
      Ziq = Zi*Zi
      Zrq = Zr*Zr
      if Zrq+Ziq > 4.0 then b = b + 1; break; end
    end
    if b >= 256 then p = p + 1; buf[p] = 511 - b; b = 1; end
  end
  if b ~= 1 then p = p + 1; buf[p] = (ba-b)*bb; end
  write(char(unpack(buf, 1, p)))
end