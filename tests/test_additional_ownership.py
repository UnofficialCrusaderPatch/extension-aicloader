"""Exercise the real loader and personality validator with an in-memory core.

Run: python -m pytest tests (requires pytest and lupa).
These tests do not run Stronghold Crusader or certify native compatibility.
"""
from pathlib import Path

import pytest
from lupa import LuaRuntime, LuaError


ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def lua():
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.globals().module_path = ROOT.as_posix()
    runtime.execute("""
        package.path = module_path .. '/?.lua;' .. package.path
        memory, writes, messages = {}, {}, {}
        core = {
          readInteger = function(address) return memory[address] or 0 end,
          writeInteger = function(address, value)
            memory[address] = value
            writes[#writes + 1] = {address, value}
          end,
        }
        package.loaded.addresses = {getAIStartAddress = function(ai) return 10000 + ai * 676 end}
        log = function(level, message) messages[#messages + 1] = message end
        hooks = {registerHookCallback = function(_, callback) afterInit = callback end}
        modules = {}
        loader = dofile(module_path .. '/init.lua')
        loader:enable({})
        afterInit()
        values = {}
        handler = function(ai, value)
          if value ~= nil then values[ai] = value end
          return values[ai] or 0
        end
        reset = function(ai) values[ai] = 0 end
    """)
    return runtime


def test_get_set_reset_remain_per_character(lua):
    lua.execute("""
        loader:registerAdditionalAICValue('tactics', 'Policy', handler, reset)
        loader:setAICValue('rat', 'Policy', 4)
        loader:setAICValue('snake', 'Policy', 7)
        assert(loader:getAICValue(1, 'Policy') == 4)
        assert(loader:getAICValue(1, 'Policy') == 4)
        assert(loader:getAdditionalAICValueOwner('Policy') == 'tactics')
        assert(#writes == 0)
        loader:resetAIC(1)
        assert(loader:getAICValue(1, 'Policy') == 0)
        assert(loader:getAICValue(2, 'Policy') == 7)
    """)


@pytest.mark.parametrize('attempt', [
    "loader:registerAdditionalAICValue('other', 'Policy', handler, reset)",
    "loader:registerAdditionalAICValue('tactics', 'Policy', handler, reset)",
    "loader:setAdditionalAICValue('Policy', handler, reset)",
    "loader:setAdditionalAICValue('Policy', nil)",
    "loader:setAICValueOverride('Policy', 1, handler, reset)",
    "loader:setAICValueOverride('Policy', nil)",
    "loader:unregisterAdditionalAICValue('other', 'Policy')",
    "loader:unregisterAdditionalAICValue(nil, 'Policy')",
])
def test_conflicts_preserve_owner_and_value(lua, attempt):
    lua.execute("loader:registerAdditionalAICValue('tactics', 'Policy', handler, reset); handler(1, 9)")
    with pytest.raises(LuaError):
        lua.execute(attempt)
    lua.execute("assert(loader:getAdditionalAICValueOwner('Policy') == 'tactics'); assert(loader:getAICValue(1, 'Policy') == 9)")


@pytest.mark.parametrize('field', ['TargetChoice', 'Unknown124', 'RaidRetargetDelay'])
def test_native_names_and_aliases_cannot_be_claimed(lua, field):
    with pytest.raises(LuaError):
        lua.globals().loader.registerAdditionalAICValue(lua.globals().loader, 'tactics', field,
                                                       lua.globals().handler, lua.globals().reset)


def test_reverse_registration_order(lua):
    lua.execute("""
        loader:setAdditionalAICValue('OldField', handler, reset)
        loader:setAICValueOverride('OldOverride', 1, function(v) return v end, reset)
    """)
    for field in ('OldField', 'OldOverride'):
        with pytest.raises(LuaError):
            lua.execute(f"loader:registerAdditionalAICValue('tactics', '{field}', handler, reset)")
    lua.execute("assert(loader:getAdditionalAICValueOwner('OldField') == nil); assert(#writes == 0)")


def test_old_unclaimed_registration_remains_replaceable(lua):
    lua.execute("""
        loader:setAdditionalAICValue('OldField', handler, reset)
        loader:setAdditionalAICValue('OldField', function() return 12 end, reset)
        assert(loader:getAICValue(1, 'OldField') == 12)
        loader:setAdditionalAICValue('OldField', nil)
        assert(not pcall(function() loader:getAICValue(1, 'OldField') end))
    """)


def test_unregister_is_explicit_and_does_not_reset_provider(lua):
    lua.execute("""
        loader:registerAdditionalAICValue('tactics', 'Policy', handler, reset)
        handler(1, 9)
        loader:unregisterAdditionalAICValue('tactics', 'Policy')
        assert(values[1] == 9)
        assert(loader:getAdditionalAICValueOwner('Policy') == nil)
        loader:registerAdditionalAICValue('other', 'Policy', handler, reset)
        assert(loader:getAICValue(1, 'Policy') == 9)
    """)


@pytest.mark.parametrize('arguments', [
    "nil, 'Policy', handler, reset", "'', 'Policy', handler, reset",
    "'tactics', nil, handler, reset", "'tactics', '', handler, reset",
    "'tactics', 'Policy', nil, reset", "'tactics', 'Policy', handler, nil",
])
def test_invalid_registration_does_not_reserve_name(lua, arguments):
    with pytest.raises(LuaError):
        lua.execute(f"loader:registerAdditionalAICValue({arguments})")
    lua.execute("loader:registerAdditionalAICValue('tactics', 'Policy', handler, reset)")


def test_native_fields_keep_existing_validation_and_partial_update_behavior(lua):
    lua.execute("""
        loader:registerAdditionalAICValue('tactics', 'Policy', handler, reset)
        loader:setAICValue(1, 'RecruitProbDefDefault', 35)
        loader:setAICValue(1, 'RecruitProbDefDefault', 101)
        assert(loader:getAICValue(1, 'RecruitProbDefDefault') == 35)
        loader:overwriteAIC(1, {Policy = 2, RecruitProbDefDefault = 101, RecruitProbRaidDefault = 15})
        assert(loader:getAICValue(1, 'RecruitProbDefDefault') == 35)
        assert(loader:getAICValue(1, 'RecruitProbRaidDefault') == 15)
        assert(loader:getAICValue(1, 'Policy') == 2)
    """)
