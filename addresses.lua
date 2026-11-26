local aicArrayBaseAddr = core.readInteger(core.AOBScan(
  "? ? ? ? e8 ? ? ? ? 89 1d ? ? ? ? 83 3d ? ? ? ? 00 75 44 6a 08 b9 ? ? ? ? e8 ? ? ? ? 85 c0 74 34 8b c5 2b 05"))

local stride = 4 * 169

  local function getAIStartAddress(aiType)
    return aicArrayBaseAddr + stride * aiType
  end

return {
    getAIStartAddress = getAIStartAddress,
    characters = 16,
    stride = stride,
}