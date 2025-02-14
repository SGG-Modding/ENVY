---@meta _
---@diagnostic disable

-- please update your mod to use LuaENVY-ENVY instead!

local envy = rom.mods['LuaENVY-ENVY']
envy.auto()

for k,v in pairs(envy) do
	public[k] = v
end