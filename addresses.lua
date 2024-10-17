local aicArrayBaseAddr = core.readInteger(core.AOBScan(
  "? ? ? ? e8 ? ? ? ? 89 1d ? ? ? ? 83 3d ? ? ? ? 00 75 44 6a 08 b9 ? ? ? ? e8 ? ? ? ? 85 c0 74 34 8b c5 2b 05"))

  local function getAIStartAddress(aiType)
    return aicArrayBaseAddr + 4 * 169 * aiType
  end

return {
    getAIStartAddress = getAIStartAddress,
}