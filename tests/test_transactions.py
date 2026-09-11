"""Configuration transaction tests, not an implementation of recruitment."""
import pytest
from lupa import LuaError

from test_additional_ownership import lua  # noqa: F401 -- shared real-loader fixture


@pytest.fixture
def policy(lua):
    lua.execute("""
        loader:setAICValue(1, 'RecruitProbDefDefault', 40)
        loader:setAICValue(1, 'RecruitProbRaidDefault', 20)
        loader:setAICValue(1, 'RecruitProbAttackDefault', 40)
        states = {}
        getter = function(ai, value)
          assert(value == nil, 'Atomic fields must use their update provider')
          return states[ai] and states[ai].mode or 'Native'
        end
        loader:registerAdditionalAICValue('tactics', 'RecruitPolicy', getter, reset)
        loader:registerAdditionalAICValue('tactics', 'SortieWeight', function(ai, value)
          assert(value == nil)
          return states[ai] and states[ai].sortie or 0
        end, reset)
        commitCount, rollbackCount = 0, 0
        loader:registerAICUpdateProvider('tactics', {
          handles = function(ai, spec, resetting)
            return states[ai] ~= nil or spec.RecruitPolicy ~= nil or spec.SortieWeight ~= nil
          end,
          prepare = function(ai, spec, native, resetting)
            local old = states[ai]
            local candidate = {
              mode = spec.RecruitPolicy or (old and old.mode) or 'Native',
              sortie = spec.SortieWeight or (old and old.sortie) or 0,
            }
            if resetting then candidate = nil end
            if candidate then
              assert(candidate.mode == 'Native' or candidate.mode == 'WeightedRoles', 'Invalid policy')
              assert(type(candidate.sortie) == 'number' and candidate.sortie >= 0 and candidate.sortie <= 100)
              if candidate.mode == 'WeightedRoles' then
                assert(native('RecruitProbDefDefault') + native('RecruitProbRaidDefault')
                  + native('RecruitProbAttackDefault') + candidate.sortie == 100, 'Invalid row sum')
              end
            end
            return {
              commit = function()
                commitCount = commitCount + 1
                states[ai] = candidate
                if failCommit then error('Injected commit failure') end
              end,
              rollback = function()
                rollbackCount = rollbackCount + 1
                states[ai] = old
                if failRollback then error('Injected rollback failure') end
              end,
            }
          end,
        })
        writes = {}
    """)
    return lua


def activate(policy):
    policy.execute("""
        assert(loader:overwriteAIC(1, {RecruitPolicy='WeightedRoles', SortieWeight=10,
          RecruitProbDefDefault=35, RecruitProbRaidDefault=15, RecruitProbAttackDefault=40}))
    """)


def test_complete_row_commits_before_exposing_values(policy):
    activate(policy)
    policy.execute("""
        assert(commitCount == 1)
        assert(loader:getAICValue(1, 'RecruitPolicy') == 'WeightedRoles')
        assert(loader:getAICValue(1, 'SortieWeight') == 10)
        assert(loader:getAICValue(1, 'RecruitProbDefDefault') == 35)
        assert(loader:getAICValue(2, 'RecruitPolicy') == 'Native')
        assert(#writes == 3)
    """)


def test_invalid_row_does_not_write_even_other_valid_native_fields(policy):
    policy.execute("""
        local ok, reason = loader:overwriteAIC(1, {RecruitPolicy='WeightedRoles', SortieWeight=10,
          RecruitProbDefDefault=34, RecruitProbRaidDefault=15, TaxesMin=2})
        assert(ok == false and reason:find('Invalid row sum'))
        assert(#writes == 0 and commitCount == 0)
        assert(loader:getAICValue(1, 'RecruitPolicy') == 'Native')
        assert(loader:getAICValue(1, 'RecruitProbDefDefault') == 40)
    """)


def test_single_set_and_partial_update_validate_against_committed_values(policy):
    activate(policy)
    policy.execute("""
        writes = {}
        loader:setAICValue(1, 'RecruitProbDefDefault', 36)
        assert(#writes == 0 and loader:getAICValue(1, 'RecruitProbDefDefault') == 35)
        assert(loader:overwriteAIC(1, {RecruitProbDefDefault=36, RecruitProbRaidDefault=14}))
        assert(loader:getAICValue(1, 'RecruitProbDefDefault') == 36)
        assert(loader:getAICValue(1, 'SortieWeight') == 10)
    """)


def test_declined_native_personality_keeps_best_effort_validation(policy):
    policy.execute("""
        loader:overwriteAIC(2, {RecruitProbDefDefault=30, RecruitProbRaidDefault=101})
        assert(loader:getAICValue(2, 'RecruitProbDefDefault') == 30)
        assert(loader:getAICValue(2, 'RecruitProbRaidDefault') == 0)
        assert(commitCount == 0)
    """)


def test_reset_restores_provider_and_original_native_values(policy):
    activate(policy)
    policy.execute("""
        loader:resetAIC(1)
        assert(loader:getAICValue(1, 'RecruitPolicy') == 'Native')
        assert(loader:getAICValue(1, 'SortieWeight') == 0)
        assert(loader:getAICValue(1, 'RecruitProbDefDefault') == 0)
        assert(commitCount == 2)
    """)


def test_failed_commit_restores_native_and_provider_state(policy):
    activate(policy)
    policy.execute("""
        failCommit = true
        assert(loader:overwriteAIC(1, {RecruitProbDefDefault=36, RecruitProbRaidDefault=14}) == false)
        assert(rollbackCount == 1)
        assert(loader:getAICValue(1, 'RecruitProbDefDefault') == 35)
        assert(loader:getAICValue(1, 'RecruitProbRaidDefault') == 15)
        failCommit = false
        assert(loader:overwriteAIC(1, {RecruitProbDefDefault=36, RecruitProbRaidDefault=14}))
    """)


def test_failed_reset_rolls_back(policy):
    activate(policy)
    policy.execute("failCommit = true")
    with pytest.raises(LuaError, match='Injected commit failure'):
        policy.execute('loader:resetAIC(1)')
    policy.execute("assert(loader:getAICValue(1, 'RecruitPolicy') == 'WeightedRoles'); assert(loader:getAICValue(1, 'RecruitProbDefDefault') == 35)")


def test_rollback_failure_requires_clean_restart(policy):
    activate(policy)
    policy.execute('failCommit = true; failRollback = true')
    with pytest.raises(LuaError, match='clean restart required'):
        policy.execute("loader:overwriteAIC(1, {TaxesMin=1})")
    with pytest.raises(LuaError, match='clean restart'):
        policy.execute("loader:setAICValue(2, 'TaxesMin', 1)")


def test_nontransactional_callback_is_rejected_before_any_write(policy):
    policy.execute("loader:setAdditionalAICValue('Other', function() error('must not run') end, reset)")
    policy.execute("""
        assert(loader:overwriteAIC(1, {RecruitPolicy='WeightedRoles', Other=1}) == false)
        assert(#writes == 0 and commitCount == 0)
    """)
    activate(policy)
    with pytest.raises(LuaError, match='Cannot atomically reset'):
        policy.execute('loader:resetAIC(1)')


def test_conflicting_aliases_are_rejected_only_in_atomic_path(policy):
    activate(policy)
    policy.execute("""
        writes = {}
        assert(loader:overwriteAIC(1, {RaidRetargetDelay=5, Unknown124=6}) == false)
        assert(#writes == 0)
        assert(loader:overwriteAIC(1, {RaidRetargetDelay=5, Unknown124=5}))
        assert(#writes == 1 and loader:getAICValue(1, 'Unknown124') == 5)
    """)


def test_provider_order_is_stable_and_all_prepare_before_commit(policy):
    policy.execute("""
        order = {}
        for _, owner in ipairs({'zeta','alpha'}) do
          loader:registerAICUpdateProvider(owner, {
            handles=function() return true end,
            prepare=function()
              order[#order+1]='prepare-'..owner
              assert(#writes == 0)
              return {commit=function() order[#order+1]='commit-'..owner end, rollback=function() end}
            end,
          })
        end
        assert(loader:overwriteAIC(2, {TaxesMin=1}))
        assert(table.concat(order, ',') == 'prepare-alpha,prepare-zeta,commit-alpha,commit-zeta')
    """)


def test_reentrant_mutation_is_rejected_before_write(policy):
    policy.execute("""
        loader:registerAICUpdateProvider('bad', {
          handles=function() return true end,
          prepare=function() loader:setAICValue(2, 'TaxesMin', 1) end,
        })
        assert(loader:overwriteAIC(2, {TaxesMin=2}) == false)
        assert(#writes == 0)
    """)


def test_registration_copies_callbacks_and_rejects_duplicates(policy):
    with pytest.raises(LuaError, match='already registered'):
        policy.execute("loader:registerAICUpdateProvider('tactics', {})")
    policy.execute("""
        local provider = {handles=function() return false end, prepare=function() error('must not run') end}
        loader:registerAICUpdateProvider('copy', provider)
        provider.handles = function() error('mutated callback') end
        loader:overwriteAIC(2, {TaxesMin=1})
        assert(loader:getAICValue(2, 'TaxesMin') == 1)
    """)


def test_changes_are_detached_for_each_provider_and_the_caller(policy):
    policy.execute("""
        loader:registerAICUpdateProvider('alpha', {
          handles=function(_, spec) spec.TaxesMin=9; return true end,
          prepare=function(_, spec, native)
            assert(spec.TaxesMin == 2 and native('TaxesMin') == 2)
            spec.TaxesMin=10
            return {commit=function() end, rollback=function() end}
          end,
        })
        loader:registerAICUpdateProvider('zeta', {
          handles=function(_, spec) assert(spec.TaxesMin == 2); return true end,
          prepare=function(_, spec)
            assert(spec.TaxesMin == 2)
            return {commit=function() end, rollback=function() end}
          end,
        })
        local authored={TaxesMin=2}
        assert(loader:overwriteAIC(2, authored))
        assert(authored.TaxesMin == 2 and loader:getAICValue(2, 'TaxesMin') == 2)
    """)


def test_later_prepare_failure_never_commits_earlier_provider(policy):
    activate(policy)
    policy.execute("""
        writes = {}
        loader:registerAICUpdateProvider('zeta', {
          handles=function() return true end,
          prepare=function() error('Late rejection') end,
        })
        local ok, reason=loader:overwriteAIC(1, {TaxesMin=1})
        assert(ok == false and reason:find('Late rejection'))
        assert(#writes == 0 and commitCount == 1 and rollbackCount == 0)
    """)


def test_failing_later_commit_rolls_back_providers_in_reverse_order(policy):
    policy.execute("""
        local order={}
        for _, owner in ipairs({'zeta','alpha'}) do
          loader:registerAICUpdateProvider(owner, {
            handles=function() return true end,
            prepare=function() return {
              commit=function() order[#order+1]='commit-'..owner; if owner=='zeta' then error('fail') end end,
              rollback=function() order[#order+1]='rollback-'..owner end,
            } end,
          })
        end
        assert(loader:overwriteAIC(2, {TaxesMin=1}) == false)
        assert(table.concat(order, ',') == 'commit-alpha,commit-zeta,rollback-zeta,rollback-alpha')
        assert(loader:getAICValue(2, 'TaxesMin') == 0)
    """)
