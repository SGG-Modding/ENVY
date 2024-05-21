---@meta _
---@diagnostic disable

local auto, locals, exports_private, exports

do

	local getmetatable, setmetatable, type, traceback, getupvalue, setupvalue, upvaluejoin, getinfo, pack, unpack
		= getmetatable, setmetatable, type, debug.traceback, debug.getupvalue, debug.setupvalue, debug.upvaluejoin, debug.getinfo, table.pack, table.unpack

	local globals = getmetatable(_ENV).__index or _G

	local binders = setmetatable({},{__mode = "k"})

	local function getinternal( self, name )
		local binder = binders[ self ]
		local idx = 0
		repeat
			idx = idx + 1
			local n, value = getupvalue( binder, idx )
			if n == name then
				return value
			end
		until not n
	end
	local function setinternal( self, name, value )
		local binder = binders[ self ]
		local idx = name and 0 or -1
		repeat
			idx = idx + 1
			local n = getupvalue( binder, idx )
			if n == name then
				setupvalue( binder, idx, value )
				return
			end
		until not n
	end
	local function nextinternal( self, name )
		local binder = binders[ self ]
		local idx = name and 0 or -1
		repeat
			idx = idx + 1
			local n = getupvalue( binder, idx )
			if n == name then
				local value
				repeat
					idx = idx + 1
					n, value = getupvalue( binder, idx )
					if n then
						return n, value
					end
				until not n
			end
		until not n
	end

	local internal = {
		__index = getinternal,
		__newindex = setinternal,
		__next = nextinternal,
		__pairs = function( self )
			return nextinternal, self
		end
	}

	local function export( binder )
		if type( binder ) ~= "function" then
			binder = getinfo( ( binder or 1 ) + 1, "f" ).func
		end
		local bound = { }
		binders[ bound ] = binder
		return setmetatable( bound, internal )
	end

	local function import(env,file,fenv,level,...)
		local level = (level or 1) + 1
		local fenv = fenv or env
		if type(file) == "string" then
			-- assume file is a name or path
			local path = file
			if env and env._PLUGIN then
				--print('Plugin:',env._PLUGIN.guid .. '/' .. file)
				path = env._PLUGIN.plugins_mod_folder_path .. '/' .. file
			else
				--print('File:',path)
			end
			local func, msg = loadfile(path, "t", fenv)
			if func == nil then error(msg, level) end
			file = func
		elseif type(file) == "userdata" then
			-- assume file is a FILE* handle from the io module
			local valid, data = pcall(file.read, file,"*a")
			if valid then
				local func, msg = load(data, nil, "t", fenv)
				if func == nil then error(msg, level) end
				file = func
			end
		elseif type(file) == "table" then
			-- assume this is a table to import
			return file
		end
		local ret = pack(xpcall(file, traceback, ...))
		local status, msg = ret[1],ret[2]
		if not status then error(msg,level) end
		return unpack(ret, 2, ret.n)
		
	end

	local function import_all(env,mod,fenv,level,...)
		local level = (level or 1) + 1
		if type(mod) ~= "table" then
			mod = import(env,mod,fenv,level,...)
		end

		for k,v in pairs(mod) do
			rawset(env,k,v)
		end
	end

	local fallbacks = setmetatable({},{__mode = "k"})
	local shared = setmetatable({},{__mode = "k"})

	local function import_as_fallback(env,mod,fenv,level,...)
		local level = (level or 1) + 1
		if type(mod) ~= "table" then
			mod = import(env,mod,fenv,level,...)
		end
		
		fallbacks[env] = fallbacks[env] or setmetatable({},{__mode = "k"})
		if fallbacks[env][mod] then return end
		
		local meta = getmetatable(env)
		local _index = meta.__index
		if type(_index) == "table" then
			meta.__index = function(s,k)
				local v = mod[k]
				if v ~= nil then return v end
				return _index[k]
			end
		elseif type(_index) == "function" then
			meta.__index = function(s,k)
				local v = mod[k]
				if v ~= nil then return v end
				return _index(s,k)
			end
		end
		
		fallbacks[env][mod] = true
	end

	local function import_as_shared(env,mod,fenv,level,...)
		local level = (level or 1) + 1
		if type(mod) ~= "table" then
			mod = import(env,mod,fenv,level,...)
		end

		shared[env] = shared[env] or setmetatable({},{__mode = "k"})
		if shared[env][mod] then return end

		local meta = getmetatable(env)
		local _index = meta.__index
		if type(_index) == "table" then
			meta.__index = function(s,k)
				local v = mod[k]
				if v ~= nil then return v end
				return _index[k]
			end
		elseif type(_index) == "function" then
			meta.__index = function(s,k)
				local v = mod[k]
				if v ~= nil then return v end
				return _index(s,k)
			end
		end
		local _newindex = meta.__newindex
		if type(_newindex) == "table" then
			meta.__newindex = function(s,k,v)
				local u = mod[k]
				if u ~= nil then 
					mod[k] = v
				else
					_newindex[k] = v
				end
			end
		elseif type(_newindex) == "function" then
			meta.__newindex = function(s,k,v)
				local u = mod[k]
				if u ~= nil then 
					mod[k] = v
				else
					_newindex(s,k,v)
				end
			end
		end
		
		shared[env][mod] = true
	end

	local private = setmetatable({},{__mode = 'k'})
	local public = setmetatable({},{__mode = 'v'})
	local extra = setmetatable({},{__mode = 'kv'})

	local function endow(env,mod)
		return {
			import = function(file,fenv,...) return import(mod,file,fenv,2,...) end;
			import_all = function(file,fenv,...) return import_all(mod,file,fenv,2,...) end;
			import_as_shared = function(file,fenv,...) return import_as_shared(mod,file,fenv,2,...) end;
			import_as_fallback = function(file,fenv,...) return import_as_fallback(mod,file,fenv,2,...) end;
			private = mod;
			public = env;
			export = export;
		}
	end

	local function setup(env)
		local mod = private[env]
		if mod ~= nil then return mod end
		mod = setmetatable({},{__index = env})
		private[env] = mod
		private[mod] = mod
		public[mod] = env
		public[env] = env
		local ext = endow(env,mod)
		extra[env] = ext
		extra[mod] = ext
		return mod, ext
	end

	local function getfenv( fn )
		if type( fn ) ~= "function" then
			fn = debug.getinfo( ( fn or 1 ) + 1, "f" ).func
		end
		local i = 0
		repeat
			i = i + 1
			local name, val = debug.getupvalue( fn, i )
			if name == "_ENV" then
				return val
			end
		until not name
	end

	local function setfenv( fn, env )
		if type( fn ) ~= "function" then
			fn = debug.getinfo( ( fn or 1 ) + 1, "f" ).func
		end
		local i = 0
		repeat
			i = i + 1
			local name = debug.getupvalue( fn, i )
			if name == "_ENV" then
				debug.upvaluejoin( fn, i, ( function( )
					return env
				end ), 1 )
				return env
			end
		until not name
	end

	function auto(level)
		level = (level or 1) + 1
		local env = getfenv(level)
		local mod, ext = setup(env)
		setfenv(level, mod)
		if ext == nil then return end
		env._G = env
		mod._G = mod
		import_all(mod, ext)
		return ext
	end

	locals = export(function()
		-- environment
		return _ENV,
		-- binds
		getmetatable, setmetatable, type, getupvalue, setupvalue, upvaluejoin, getinfo, 
		-- tables
		binders, fallbacks, shared, 
		internal, private, public, extra,
		locals, exports_private, exports,
		-- functions
		getinternal, setinternal, nextinternal, endow,
		globals, export, import, import_all, import_as_fallback, import_as_shared, setup, auto, getfenv, setfenv
	end)

	exports = export(function()
		return globals, export, import, import_all, import_as_fallback, import_as_shared, setup, auto, getfenv, setfenv
	end)

end

-- extending itself

---@module 'SGG_Modding-ENVY-auto'
auto()

for k,v in pairs(exports) do
	public[k] = v
end

public.locals = locals