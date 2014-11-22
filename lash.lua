local lash = {
	classes      = {},
	local        = {__name = true, __properties = true, __class = true},
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

local super_mt = {
	__index = function (self, k) return self.__k[k] or self.__i[k] end,
	__newindex = function (self, k, v)
		self.__k[k] = v
		self.__i[#self.__i + 1] = v
	end,
	__pairs = function (self) return pairs(self.__k) end,
	__ipairs = function (self) return ipairs(self.__i) end,
	__len = function (self) return #self.__i end,
}

local supertable = function ()
	return setmetatable({__k = {}, __i = {}}, super_mt)
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
  elseif not lash.local[k] then
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
  	--print("linearize",info.name,classinfo[parent].name)
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
-- This is a bit of a monkey patch, but it does the job.
local mixin
local include = function (self, ...)
	local info = classinfo[self]
	local index = classinfo[self].o_meta.__index

	local includes = {...}
	for i,v in ipairs(includes) do
		if type(v) == 'string' then
			includes[i] = lash.require(v)
		end
	end
	for i = #includes, 1, -1 do
		local pinfo = classinfo[includes[i]]
		if pinfo then -- metatable abuse: info.supers is a lie.
			--print("include",includes[i], pinfo)
			info.supers[#info.supers + 1] = includes[i]
 			pinfo.subclasses[self] = self
 		else -- NTS: if we somehow run into classinfo[includes[i]] ceasing to exist between mixin -> include, something is very wrong with everything.
 			mixin(self, includes[i])
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
mixin = function (self, ...)
	local mixins = {...}
	for _,mixin in ipairs(mixins) do
		if classinfo[mixin] then include(self,mixin)
		elseif type(mixin) == "table" then
			local info = classinfo[self]
			info.mixins[mixin] = mixin
			for k,v in pairs(mixin) do self[k] = v end
		end
	end
end

-- create the necessary metadata for the class, setup the inheritance
-- hierarchy, set a suitable metatable, and return the class
local subclass
local newclass = function (name, ...)
  assert( not lash.classes[name], "class " .. name .. " already exists")
  assert( type( name ) == "string", "class name must be a string" )
  local cls, index = {__properties = {}}, {}
  local o_meta = {
    __index = index,
    __name = name,
    __class = cls,
  }
  local info = {
    name = name,
    subclasses = setmetatable( {}, weakmt ), -- subclass references for propagate()
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

  mixin(cls, lash.classbase)
  include(cls, ...)
  local final = setmetatable( cls, info.c_meta )
  lash.classes[name] = final
  return final
end

local tprint = function (...)
	local t = {...}
	for i,v in ipairs(t) do
		print(i,type(v),tostring(v))
	end
end

subclass = function (self, name, ...)
	return newclass(name, self, ...)
end

local loadclasses = function (...)
	local t = {}
	for i = 1, select('#',...) do
		local v = select(i,...)
		if not lash.classes[v] then require(lash.classpath .. '.' .. v) end
		t[#t + 1] = lash.classes[v]
	end
	return (unpack or table.unpack)(t)
end

lash.classbase = {}
lash.classinfo = classinfo
lash.classpath = "classes"
lash.class = newclass
lash.include = include
lash.mixin = mixin
lash.subclass = subclass
lash.require = loadclasses

local c = newclass("Object")

-- Directly set (or unset, using nil) a property.
-- If 'v' is a function, the return of v() will be the final value unless 'raw' is used.
-- Returns the final value.
c.Set = function (self, k, v, raw)
  local p = self.__properties
	if (not raw) and type(v) == 'function' then v = v() end
	p[k] = v
	return p[k]
end

-- See :Set, but will never overwrite a non-nil property.
-- Note: See :Set for 'raw' functionality in all methods below.
c.SafeSet = function (self, k, v, raw)
	if type(self.__properties[k]) == 'nil' then
		return self:Set(k,v)
	end
end

-- Return a property. If the property is nil, this will call :Set(k, default, raw) first.
c.Get = function (self, k, default, raw)
  local p = self.__properties
	if (type(p[k]) == 'nil') then
		self:Set(k,default,raw)
	end
	return p[k]
end

-- Combined :Get and :Set for situations where a function arg should update a property or set to a default value.
c.OptSet = function (self, k, v, default, raw)
	if type(v) == 'nil' then
		return self:Get(k,default,raw)
	else
		return self:Set(k,v,raw)
	end
end

lash.Object = c

setmetatable(lash, { __call = function (_, name, super, ...) return lash.subclass(super or lash.Object, name, ...) end })
return lash
