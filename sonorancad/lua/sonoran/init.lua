local function load_module(path)
  if LoadResourceFile and GetCurrentResourceName then
    local resource_name = GetCurrentResourceName()
    local source = LoadResourceFile(resource_name, path)
    if not source then
      error(("Unable to load module: %s"):format(path))
    end

    local chunk, load_error = load(source, ("@@%s/%s"):format(resource_name, path))
    if not chunk then
      error(load_error)
    end

    return chunk()
  end

  local module_name = path:gsub("^lua/", ""):gsub("%.lua$", ""):gsub("/", ".")
  return require(module_name)
end

local create_client = load_module("lua/sonoran/client.lua")
local create_fivem_adapter = load_module("lua/sonoran/adapters/fivem.lua")

local Sonoran = {}
Sonoran.productEnums = {
  CAD = 0,
  CMS = 1,
  RADIO = 2
}
Sonoran.logLevels = {
  OFF = "OFF",
  DEBUG = "DEBUG"
}

function Sonoran.createClient(config)
  return create_client(config or {}, create_fivem_adapter())
end

if exports then
  exports("createClient", Sonoran.createClient)
end

return Sonoran
