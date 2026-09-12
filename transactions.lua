-- Opt-in configuration transactions. Providers retain their own storage.
local M = {}

local function copyData(value, copies)
  if type(value) ~= "table" then return value end
  copies = copies or {}
  if copies[value] then return copies[value] end
  local copy = {}
  copies[value] = copy
  for key, item in pairs(value) do copy[key] = copyData(item, copies) end
  return copy
end

local function sortedKeys(values)
  local keys = {}
  for key in pairs(values) do
    assert(type(key) == "string", "AIC update keys must be field names")
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

function M.new(deps)
  local providers = {}
  local busy, poisoned = false, false
  local api = {}

  function api.assertMutable()
    assert(not poisoned, "AIC rollback failed; a clean restart is required")
    assert(not busy, "AIC updates and registration cannot be reentered from provider callbacks")
  end

  function api.isPoisoned()
    return poisoned
  end

  function api.hasProviders()
    return next(providers) ~= nil
  end

  function api.register(owner, provider)
    api.assertMutable()
    assert(type(owner) == "string" and owner ~= "", "An AIC update provider requires a module name")
    assert(not providers[owner], "AIC update provider is already registered: " .. owner)
    assert(type(provider) == "table" and type(provider.handles) == "function"
      and type(provider.prepare) == "function", "AIC update provider requires handles and prepare functions")
    providers[owner] = {handles = provider.handles, prepare = provider.prepare}
  end

  -- Returns false when every provider declines, preserving the old write path.
  function api.update(aiType, spec, resetting)
    api.assertMutable()
    if next(providers) == nil then return false end
    busy = true
    local ok, result = pcall(function()
      local active, selected = {}, {}
      for _, owner in ipairs(sortedKeys(providers)) do
        local provider = providers[owner]
        if provider.handles(aiType, copyData(spec), resetting) then
          active[#active + 1] = owner
          selected[owner] = true
        end
      end
      if #active == 0 then return false end

      local staged, previous, operations = {}, {}, {}
      if resetting then
        staged = deps.defaults(aiType)
        for field, additional in pairs(deps.additional) do
          assert(additional.owner and selected[additional.owner],
            "Cannot atomically reset AIC field without an active update provider: " .. field)
        end
      else
        assert(type(spec) == "table", "An AIC update must be a table")
        for _, field in ipairs(sortedKeys(spec)) do
          local additional = deps.additional[field]
          if additional then
            assert(additional.owner and selected[additional.owner],
              "Cannot atomically update AIC field without an active update provider: " .. field)
          else
            local index, value = deps.validate(field, spec[field])
            assert(staged[index] == nil or staged[index] == value,
              "Conflicting AIC aliases in atomic update: " .. field)
            staged[index] = value
          end
        end
      end

      local indices = {}
      for index in pairs(staged) do indices[#indices + 1] = index end
      table.sort(indices)
      for _, index in ipairs(indices) do previous[index] = deps.read(aiType, index) end

      local function readNative(field)
        local index = deps.index(field)
        assert(index ~= nil, "Not a native AIC field: " .. tostring(field))
        if staged[index] ~= nil then return staged[index] end
        return deps.read(aiType, index)
      end

      for _, owner in ipairs(active) do
        local operation = providers[owner].prepare(aiType, copyData(spec), readNative, resetting)
        assert(type(operation) == "table" and type(operation.commit) == "function"
          and type(operation.rollback) == "function", "AIC provider must prepare commit and rollback: " .. owner)
        operations[#operations + 1] = operation
      end

      local committed, written = 0, 0
      local committedOK, reason = pcall(function()
        for i, index in ipairs(indices) do
          written = i
          deps.write(aiType, index, staged[index])
        end
        for i, operation in ipairs(operations) do
          committed = i
          operation.commit()
        end
      end)
      if not committedOK then
        local failures = {}
        for i = committed, 1, -1 do
          local restored, failure = pcall(operations[i].rollback)
          if not restored then failures[#failures + 1] = tostring(failure) end
        end
        for i = written, 1, -1 do
          local index = indices[i]
          local restored, failure = pcall(deps.write, aiType, index, previous[index])
          if not restored then failures[#failures + 1] = tostring(failure) end
        end
        if #failures > 0 then
          poisoned = true
          error(tostring(reason) .. "; AIC rollback failed; clean restart required: " .. table.concat(failures, "; "), 0)
        end
        error(reason, 0)
      end
      return true
    end)
    busy = false
    if not ok then error(result, 0) end
    return result
  end

  return api
end

return M
