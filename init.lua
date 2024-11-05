local writeInteger = core.writeInteger
local readInteger = core.readInteger

local AICharacterName = require("characters")

local Personality = require("personality")

local getAIStartAddress = require("addresses").getAIStartAddress

local FailureHandling = {
  WARN_LOG = "WARN_LOG",
  ERROR_LOG = "ERROR_LOG",
  FATAL_LOG = "FATAL_LOG",
  CHAT_TEXT = "CHAT_TEXT",
}

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
  local vanillaStartAddr = getAIStartAddress(1)
  local vanillaEndAddr = getAIStartAddress(16) + 4 * 168
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
        local resetValues = Personality.receiveResetOfOverridenValues(aiType)
        if next(resetValues) ~= nil then
          local vanillaStartAddr = getAIStartAddress(aiType)

          for index, resetValue in pairs(resetValues) do
            writeInteger(vanillaStartAddr + index * 4, resetValue)
          end
        end
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

      local aicAddr = getAIStartAddress(aiType)
      local fieldIndex, fieldValue = Personality.getAndValidateAicValue(aicField, aicValue)
      writeInteger(aicAddr + (4 * fieldIndex), fieldValue)
      --TODO: optimize by writing a longer array of bytes... (would only apply to native AIC structure)
    end)

    if not status then
      local message = string.format("Error for AI '%s' while setting '%s': %s", aiType, aicField, err)

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
    aiType = receiveValidAiType(aiType)

    local vanillaStartAddr = getAIStartAddress(aiType)
    local vanillaEndAddr = vanillaStartAddr + 4 * 168
    for addr = vanillaStartAddr, vanillaEndAddr, 4 do
      writeInteger(addr, vanillaAIC[addr])
    end

    for index, resetValue in pairs(Personality.receiveResetOfOverridenValues(aiType)) do
      writeInteger(vanillaStartAddr + index * 4, resetValue)
    end

    for _, additional in pairs(additionalAIC) do
      additional.resetFunction(aiType)
    end
  end,

  setAICValueOverride = function(self, aicField, index, valueFunction, resetFunction)
    Personality.setAICValueOverride(aicField, index, valueFunction, resetFunction)
  end,

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
