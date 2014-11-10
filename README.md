#lash#

Lash is a pure-Lua OOP library based on [Classy](https://github.com/siffiejoe/lua-classy/) with inspiration from [middleclass](https://github.com/kikito/middleclass).

##Features##
Core features are derived from [Classy](https://github.com/siffiejoe/lua-classy/). What's different:
* Includes a base Object class.
* Optional object properties system (detailed below).
* Classes are identified (and unique) by name.
* Dependencies may be loaded by name during declaration or via lash.require().
* Ancestors may be added after class declaration (Classy only allows inheritance during declaration).
* Added a mixin() method for non-class includes.
* A touch less error-prone than Classy when dealing with certain object variables.

##Weaknesses##
* If you require anonymous or private classes, a separate instance of Lash is needed.
* Class/object initialization and memory usage is probably more intense than some other options.
* Propagation does not occur when tables included via mixin() change. If working with dynamic mixins, consider either converting the mixin to a class for actual inheritance or propagating the mixin's entries manually.

##Usage##
```lua
local lash = require 'lash'
local class = lash('MyClass')

class.initialize = function (self, ...)
  return print(getmetatable(self).__name, ...)
end
local object = class('I am an object!') --> fires :initialize(...) --> 'MyClass'  'I am an object!'

-- Subclassing
local child = lash('ChildClass', class or 'MyClass') -- May inherit by name or reference.
local childObject = child("I'm a child!", 'This is another arg!') --> 'ChildClass'  'I'm a child!'  'This is another arg!'

-- Preloading (feat. unique class names)
local external = lash.require('external', 'otherext') -- loads ./classes/external.lua and ./classes/otherext.lua (this uses Lua's require(), so package.path will change how this works). Using this is *not needed* in most cases, as Lash will do this for you in include() when a string is passed to it.
local oops = lash('external') -- ERROR: 'external' class exists already
local external = lash('ExternalClass', 'external') -- Valid. Note that if we hadn't used lash.require() above, Lash would do so for us.

-- Mixin, post-creation include, child initializer
local stepchild = lash('StepChildClass')
stepchild:mixin( { mixedin = true } )
stepchild:include('MyClass', external) -- Again, this will call lash.require('MyClass') if 'MyClass' isn't a thing yet. Useful, but be careful with it because Lua's require() *will* error if it there's no file.
stepchild.initialize = function (self)
  return print('This is an initialize function.')
end
stepchildObject = stepchild() -- Ancestor's initialize() is *not* used. --> 'This is an initialize function.'
-- Note: If you change an ancestor's initialize() method, the change will *not* propagate to children! This may be fixed in a later commit.

-- Propagation
class.thing = 'stuff'
print(child.thing) -- Entries added to a class propagate to objects and subclasses --> 'stuff'
object.thing = 'changed'; print(object.thing, child.thing) -- Entries changed in initialized objects don't affect the class itself --> 'changed'  'stuff'
print(childObject.thing) -- Same. --> 'stuff'
-- If you're doing really funky things and propagation isn't happening automatically, you can tell Lash to propagate manually by passing the key to class:propagate() as such:
child:propagate('thing')

-- Object properties

-- :Set(k, v, raw) -- Set a property, return it. The below methods all use this when setting a property.
local var = object:Set('variable', false) --> true
local var = object:Set('variable', nil) --> nil

local f = function () print('foo') end -- What if we want to use a function as a value?
local var = object:Set('variable', f) -- Function will be fired with no args with the return used as the value. --> 'foo'
local var = object:Set('variable', f, true) -- ...Except if we use the raw flag. --> function 0xef12ac2
-- Note: The inverse is not true. Keys are used just as they are passed.
local var = object:Set(f, true) --> true; object:Get(f) == true; object:Get('foo') == nil

-- :Get(k, default, raw) -- Retrieve a property (Note: the raw flag is the same throughout)
local var = object:Get('newvar') --> nil
local var = object:Get('newvar', true) -- Get() allows a default value as well. --> true
local var = object:Get('newvar', false) --> Yes, it will set the property. --> false
local var = object:Get('newvar', true) -- ...But only if it's not nil. --> false

-- :SafeSet(k, v, raw) -- As :Set, but will never overwrite an existing value.
local var = object:SafeSet('safevar', false) --> false
local var = object:SafeSet('safevar', 'thing!') --> false

-- :OptSet(k, v, default, raw) -- Combine :Get and :Set (very useful in functions where optional args are used to change properties with suitable defaults)
local var = object:OptSet('optvar', nil, false) --> false (defaulted since v is nil - :Get('optvar', false) was called here)
local var = object:OptSet('optvar', false, 'foo') --> false (v takes precedence - :Set('optvar', false) was called here)
local var = object:OptSet('optvar', nil, true) --> false (:Get('optvar', true) returns the existing value in this case)
```

##Properties System##
Lash adds a __properties table to each initialized object intended for storing object-specific variables. This is completely optional to use, but is as lightweight as possible and allows for some very cool stuff.

Four methods are available within the Object class:
* `Set(self, key, value, raw)` sets `self.__properties[key] = value` regardless of the current value of `self.__properties[k]`.
* `SafeSet(self, key, value, raw)` calls `Set(...)` *only* if `self.__properties[key]` is not `nil`.
* `Get(self, key, default, raw)` returns `self.__properties[key]`, or `Set(self, key, default, raw)` if the entry is `nil`.
* `OptSet(self, key, value, default, raw)` returns `Get(self, key, default, raw)` if `self.__properties[key]` is nil, or `Set(self, key, value, raw)` if it's not.

Notes:
* Keys are used as-is and can be anything you like (including tables and functions).
* `Set` assumes that if `value` is a function, the final value should be the return of `value()`. Use `raw` to store a function as-is.
* `object.__properties` is a normal table. You can work with it directly if you like.
* These methods are set by lash.Object and may be overloaded or ignored as you please.

##TODO##
* Lash's code isn't very well-documented.
* When using class:mixin, changed to the mixed-in table aren't propagated when changed (unlike includes).
* This readme is probably a pretty crappy read. Sorry!
* I'm sure there's a few critical missing features and massive bugs here and there.

##Addendum##
Aside from how propagation works, Lash is a pretty basic beast. It doesn't try to emulate the entire Java class system, nor does it attempt to validate much of anything. While I've found it fairly difficult to break, your mileage may vary. If you find a show-stopping bug, please let me know.

Please keep in mind this library is written for the author's personal use and that feature requests, though appreciated, will probably be passed on if they aren't A) awesome, and/or B) direly needed. I'm always happy to help if you're trying to extend Lash, but there's a pretty good chance that a "plz add cloning and interfaces' request won't be honored.
