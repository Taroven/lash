local lash = {
	_VERSION     = 'lash v0.1',
	_DESCRIPTION = 'Lua OO library based on Classy with some tweaks',
	_URL         = 'https://github.com/taroven/lash',
	_LICENSE     = [[
    MIT LICENSE

    Copyright (c) 2014 Ezra Sims

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ]]
}

local getmetatable,setmetatable = getmetatable,setmetatable
local type = type
local pairs,ipairs = pairs,ipairs
local table,string = table,string
local concat = table.concat or concat
local loadstring = loadstring or load
local subclass

-- index of allowed metamethods (__index is reserved)
local metamethods = {
  __add = true, __sub = true, __mul = true, __div = true,
  __mod = true, __pow = true, __unm = true, __concat = true,
  __len = true, __eq = true, __lt = true, __le = true, __call = true,
  __tostring = true, __pairs = true, __ipairs = true, __gc = true,
  __newindex = true, __metatable = true, __idiv = true, __band = true,
  __bor = true, __bxor = true, __bnot = true, __shl = true,
  __shr = true,
}

-- Commonly reused metatable
local weakmt = {__mode = "k"}

-- Index of active classes (weak)
local classinfo = setmetatable({},weakmt)

-- __pairs/__ipairs metamethods for iterating members of classes
local class_pairs = function (self)
  return pairs(classinfo[self].o_meta.__index)
end

local class_ipairs = function (self)
  return ipairs(classinfo[self].o_meta.__index)
end

local constructor = function (self, ...)
	local info = classinfo[self]
	local o = setmetatable({},info.o_meta)
	if o.initialize then o:initialize(...) end
	return o
end

-- propagate a changed method to a sub class
local propagate = function (self, k)
	if not k then return end
  local info = classinfo[self]
  if type(info.members[k]) ~= "nil" then
    info.o_meta.__index[k] = info.members[k]
  else
    for i = 1, #info.super do
      local val = classinfo[info.super[i]].members[k]
      if type(val) ~= "nil" then
        info.o_meta.__index[k] = val
        return
      end
    end
    info.o_meta.__index[k] = nil
  end
end


-- __newindex handler for class proxy tables, allowing to set certain
-- metamethods, initializers, and normal members. updates sub classes!
local class_newindex = function (self, k, v)
  local info = classinfo[self]
  
  -- Changed: Ignore replacement of existing metamethods instead of throwing an error
  if metamethods[k] and not info.o_meta[k] then
    info.o_meta[k] = v
  
  -- Changed: initialize instead of __init, no more constructor shenanigans
  elseif key == "initialize" then
    info.members.initialize = v
    info.o_meta.__index.initialize = v
  
  -- Changed: Ignore .class instead of throwing an error
  elseif k ~= "class" then
    info.members[k] = v
    propagate(self, k)
    for sub in pairs(info.subclasses) do
      propagate(sub, k)
    end
  end
end

-- Based on Classy: Width-first linearization of a class's heirarchy.
-- Changed: Now called as super = linearize(cls, parents)
-- Removed: Lash doesn't care about heirarchy distance.
-- TODO: Fix this up a bit for cls:inherit() instead of rerunning it every time
local linearize = function (info)
	local super = {}
  
  for i,parent in ipairs(info.supers) do
    if classinfo[parent] then
    	super[#super + 1] = parent
    end
  end

  for i,p in ipairs( super ) do
    local pinfo = classinfo[p]
    local psuper = pinfo.super

    for i = 1, #psuper do
      super[#super + 1] = psuper[i]
    end
  end
  
  return super
end

-- Classy does not provide methods for inheritance after birth.
-- This is a bit of a monkey patch, but it does the job nicely.
local include = function (self, ...)
	local info = classinfo[self]
	local index = classinfo[self].o_meta.__index
	
	local includes = {...}
	for i = #includes, 1, -1 do
		local pinfo = classinfo[includes[i]]
		if pinfo then
			local exists
			for _,v in ipairs(info.supers) do
				if includes[i] == v then exists = true; break end
 			end
 			if not exists then
 				table.insert(info.supers,1,includes[i])
 			end
 			pinfo.subclasses[self] = self
 		end
	end
	
	info.super = linearize(info)
  for i = #info.super, 1, -1 do
    for k,v in pairs(classinfo[info.super[i]].members) do
      if k ~= "initialize" then index[k] = v end
    end
  end
  
  return self
end

-- Non-class includes
local mixin = function (self, ...)
	local mixins = {...}
	for _,mixin in ipairs(mixins) do
		if classinfo[mixin] then include(self,mixin) else
			mixins[mixin] = mixin
			for k,v in pairs(mixin) do self[k] = v end
		end
	end
end

-- create the necessary metadata for the class, setup the inheritance
-- hierarchy, set a suitable metatable, and return the class
local newclass = function (name, ...)
  assert( type( name ) == "string", "class name must be a string" )
  local cls, index = {}, {}
  local o_meta = {
    __index = index,
    __name = name,
    __class = cls,
  }
  local info = {
    name = name,
    subclasses = setmetatable( {}, mode_k_meta ), -- subclass references for propagate()
    members = {}, -- k/v pairs added to object instances, either added or included
    supers = {}, -- Added: list of inherited classes for include()
    mixins = {}, -- Added: list of tables from mixin() (only for diagnostic purposes)
    o_meta = o_meta, -- Metatable applied to object instances
    c_meta = { -- Metatable applied to class objects
      __index = index, -- Reference of o_meta.__index
      __newindex = class_newindex, -- Apply new keys to the appropriate places
      __call = function (self, ...)
      		local o = setmetatable({},o_meta)
      		if o.initialize then o:initialize() end
      		return o
      	end,
      __pairs = class_pairs, -- read from o_meta instead of self
      __ipairs = class_ipairs,
      __name = "class", -- FIXME: completely superflouous
      --__metatable = false, -- No reason to block getmetatable()
    },
  }
  
  index.__class = cls
  classinfo[cls] = info
  
  cls.include = include
  cls.mixin = mixin
  cls.propagate = propagate
  cls.subclass = subclass
  
  include(cls, ...)
  return setmetatable( cls, info.c_meta )
end

subclass = function (self, name, ...)
	return newclass(name, self, ...)
end

lash.classinfo = classinfo
lash.class = newclass
lash.include = include
lash.mixin = mixin
lash.subclass = subclass

setmetatable(lash, { __call = function (_, ...) return lash.class(...) end })
return lash