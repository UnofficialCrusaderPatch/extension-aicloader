local Personality = require("personality")
local getAIStartAddress = require("addresses").getAIStartAddress

local writeInteger = core.writeInteger
local readInteger = core.readInteger

local INT_MIN = -(2^31)
local INT_MAX = 2^31 - 1

local function handleDefSiegeEngineGoldThreshold(value)
  -- not full integer range, since the value needs to be negatable and still fit in signed 32 bit integer range
  local value = isIntegerValue(value, INT_MIN + 1, INT_MAX)
  -- negate value
  return -value
end

return {
  DefSiegeEngineGoldThreshold_Inversed = {
    handlerFunction = function(aiType, aicValue)
      local aicAddr = getAIStartAddress(aiType)
      local fieldIndex, fieldValue = Personality.getAndValidateAicValue("DefSiegeEngineGoldThreshold", aicValue)
      writeInteger(aicAddr + (4 * fieldIndex), handleDefSiegeEngineGoldThreshold(fieldValue))
    end,
    resetFunction = function(aiType)
      log(WARNING, "resetFunction not implemented for custom 'DefSiegeEngineGoldThreshold'")
    end,
  }
}