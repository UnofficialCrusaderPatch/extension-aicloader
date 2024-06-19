local writeInteger = core.writeInteger
local readInteger = core.readInteger

local AICharacterName = require("characters")

local Personality = require("personality")

local FailureHandling = {
  WARN_LOG = "WARN_LOG",
  ERROR_LOG = "ERROR_LOG",
  FATAL_LOG = "FATAL_LOG",
  CHAT_TEXT = "CHAT_TEXT",
}

local aicArrayBaseAddr = core.readInteger(core.AOBScan(
  "? ? ? ? e8 ? ? ? ? 89 1d ? ? ? ? 83 3d ? ? ? ? 00 75 44 6a 08 b9 ? ? ? ? e8 ? ? ? ? 85 c0 74 34 8b c5 2b 05"))

local failureHandlingSetting = FailureHandling.ERROR_LOG
local commandsActive = false

local isInitialized = false
local vanillaAIC = {}

local additionalAIC = {}


local function receiveValidAiType(aiType)
  if type(aiType) == "string" then
    local aiInteger = AICharacterName[string.upper(aiType)]
    if aiInteger ~= nil then
      return aiInteger
    end
    error("no ai exists with the name: " .. aiType)
  end

  if aiType < 1 or aiType > 16 then
    error("AI types must be between 1 and 16. Provided AI type: " .. aiType)
  end
  return aiType
end

local function initializedCheck()
  if isInitialized then
    return true
  end

  log(WARN, "AIC loader not yet initialized. Call ignored.")
  return false
end

local function saveVanillaAIC()
  local vanillaStartAddr = aicArrayBaseAddr + 4 * 169
  local vanillaEndAddr = aicArrayBaseAddr + 4 * 169 * 16 + 4 * 168
  for addr = vanillaStartAddr, vanillaEndAddr, 4 do
    vanillaAIC[addr] = readInteger(addr)
  end
end

-- You can consider this a forward declaration
local namespace = {}

-- available only for the command module and not part of the documentation until the command module is fully added
local commands = {
  onCommandSetAICValue = function(command)
    if not initializedCheck() then
      return
    end

    local aiType, fieldName, value = command:match("^/setAICValue ([A-Za-z0-9_]+) ([A-Za-z0-9_]+) ([A-Za-z0-9_]+)$")
    if aiType == nil or fieldName == nil or value == nil then
      modules.commands:displayChatText(
        "invalid command: " .. command .. " usage: " ..
        "/setAICValue [aiType: 1-16 or AI character type] [field name] [value]"
      )
    else
      namespace:setAICValue(aiType, fieldName, value, FailureHandling.CHAT_TEXT)
    end
  end,

  onCommandLoadAICsFromFile = function(command)
    if not initializedCheck() then
      return
    end

    local path = command:match("^/loadAICsFromFile ([A-Za-z0-9_ /.:-]+)$")
    if path == nil then
      modules.commands:displayChatText(
        "invalid command: " .. command .. " usage: " ..
        "/loadAICsFromFile [path]"
      )
    else
      namespace:overwriteAICsFromFile(path, FailureHandling.CHAT_TEXT)
    end
  end,
}

-- functions you want to expose to the outside world
namespace = {
  enable = function(self, config)

    if config["failureHandling"] then
      failureHandlingSetting = FailureHandling[config["failureHandling"]]
    end

    commandsActive = not not modules.commands
    if commandsActive then
      modules.commands:registerCommand("setAICValue", commands.onCommandSetAICValue)
      modules.commands:registerCommand("loadAICsFromFile", commands.onCommandLoadAICsFromFile)
    end

    hooks.registerHookCallback("afterInit", function()
      saveVanillaAIC()

      isInitialized = true

      -- call override reset here, since initialization is through
      for _, aiType in pairs(AICharacterName) do
        Personality.resetOverridenValues(aiType)
      end

      if config.aicFiles then
        if type(config.aicFiles) == "table" then
          for _, fileName in pairs(config.aicFiles) do
            if fileName:len() > 0 then
              log(INFO, "Overwritten AIC values from file: " .. fileName)
              namespace:overwriteAICsFromFile(fileName)
            end
          end
        else
          error("aicFiles should be a yaml array")
        end
      end

      log(INFO, "AIC loader initialized.")
    end)
  end,

  disable = function(self)
    if not initializedCheck() then
      return
    end
    log(DEBUG, "AIC loader disable called. Does nothing.")
  end,


  setAICValue = function(self, aiType, aicField, aicValue, failureHandlingOverride)
    if not initializedCheck() then
      return
    end

    local status, err = pcall(function()
      aiType = receiveValidAiType(aiType)

      local additional = additionalAIC[aicField]
      if additional then
        additional.handlerFunction(aiType, aicValue)
        return
      end

      local aicAddr = aicArrayBaseAddr + ((4 * 169) * aiType)
      local fieldIndex, fieldValue = Personality.getAndValidateAicValue(aicField, aicValue)
      writeInteger(aicAddr + (4 * fieldIndex), fieldValue)
      --TODO: optimize by writing a longer array of bytes... (would only apply to native AIC structure)
    end)

    if not status then
      local message = string.format("Error while setting '%s': %s", aicField, err)

      local failureHandling = failureHandlingOverride or failureHandlingSetting
      if failureHandling == FailureHandling.WARN_LOG then
        log(WARNING, message)
      elseif failureHandling == FailureHandling.ERROR_LOG then
        log(ERROR, message)
      elseif failureHandling == FailureHandling.FATAL_LOG then
        log(FATAL, message)
      elseif commandsActive and failureHandling == FailureHandling.CHAT_TEXT then
        modules.commands:displayChatText(message)
      else
        log(ERROR, message) -- default handling
      end
    end
  end,

  overwriteAIC = function(self, aiType, aicSpec, failureHandlingOverride)
    if not initializedCheck() then
      return
    end

    for name, value in pairs(aicSpec) do
      namespace:setAICValue(aiType, name, value, failureHandlingOverride)
    end
  end,

  overwriteAICsFromFile = function(self, aicFilePath, failureHandlingOverride)
    if not initializedCheck() then
      return
    end

    local file = io.open(aicFilePath, "rb")
    local spec = file:read("*all")

    local aicSpec = yaml.parse(spec)
    local aics = aicSpec.AICharacters

    for _, aic in pairs(aics) do
      namespace:overwriteAIC(aic.Name, aic.Personality, failureHandlingOverride)
    end
  end,

  resetAIC = function(self, aiType)
    if not initializedCheck() then
      return
    end

    if type(aiType) == "string" then
      aiType = aiTypeToInteger(aiType)
    end

    local vanillaStartAddr = aicArrayBaseAddr + 4 * 169 * aiType
    local vanillaEndAddr = aicArrayBaseAddr + 4 * 169 * aiType + 4 * 168
    for addr = vanillaStartAddr, vanillaEndAddr, 4 do
      writeInteger(addr, vanillaAIC[addr])
    end

    Personality.resetOverridenValues(aiType)

    for _, additional in pairs(additionalAIC) do
      additional.resetFunction(aiType)
    end
  end,

  --[[
    NOT RECOMMENDED TO USE  
    `index == nil` removes override  
    `valueFunction` needs to return final integer to write  
    to allow renaming, there is no check if an index is overriden multiple times, so take care!  
    `resetFunction` will always receive an AI index starting from 1 (Rat) to 16 (Abbot)  
  ]]--
  setAICValueOverride = function(self, aicField, index, valueFunction, resetFunction)
    Personality.setAICValueOverride(aicField, index, valueFunction, resetFunction)
  end,

  --[[
    `handlerFunction == nil` removes additional AIC  
    `handlerFunction` only gets the provided value, nothing else is done  
    `resetFunction` will always reveive an AI index starting from 1 (Rat) to 16 (Abbot)
  ]]--
  setAdditionalAICValue = function(self, aicField, handlerFunction, resetFunction)
    if handlerFunction == nil then
      additionalAIC[aicField] = nil
      return
    end
    if not handlerFunction or type(handlerFunction) ~= "function" then
      error(string.format("Received no valid handler function for additional AIC with name '%s'.", aicField), 0)
    end
    if not resetFunction or type(resetFunction) ~= "function" then
      error(string.format("Received no valid reset function for additional AIC with name '%s'.", aicField), 0)
    end
    if additionalAIC[aicField] then
      log(WARNING,
        string.format("Replacing current handler for additional AIC with name %s. Is this intended?", aicField))
    end
    additionalAIC[aicField] = {
      handlerFunction = handlerFunction,
      resetFunction = resetFunction,
    }
  end,
}

return namespace, {
  public = {
    "setAICValue",
    "resetAIC",
    "overwriteAIC",
    "overwriteAICsFromFile",
  }
}
