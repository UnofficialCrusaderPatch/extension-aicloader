local aicArrayBaseAddr
local stride = 4 * 169

local function resolve()
  if aicArrayBaseAddr then return true end
  local site, reason = core.AOBScanUnique(
    "6A 0A 52 B9 ? ? ? ? E8 ? ? ? ? 89 1D ? ? ? ? 83 3D ? ? ? ? 00 75 44 6A 08 B9 ? ? ? ? E8 ? ? ? ? 85 C0 74 34 8B C5 2B 05")
  if not site then return nil, reason end
  local base = core.readInteger(site + 4)
  if base <= 0 or base ~= core.readInteger(site + 31) then
    return nil, "inconsistent AI personality table operands"
  end
  aicArrayBaseAddr = base
  return true
end

local function getAIStartAddress(aiType)
  return aicArrayBaseAddr and aicArrayBaseAddr + stride * aiType
end

return {
  resolve = resolve,
  getAIStartAddress = getAIStartAddress,
  characters = 16,
  stride = stride,
}
