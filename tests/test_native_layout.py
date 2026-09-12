from test_additional_ownership import lua  # noqa: F401


def test_native_layout_uses_the_same_storage_as_loader_writes(lua):
    lua.execute('''
      local layout=loader:getNativeAICLayout()
      assert(layout.version==1 and layout.characters==16 and layout.stride==676)
      for ai=1,16 do
        loader:setAICValue(ai,'RecruitProbDefDefault',ai)
        local write=writes[#writes]
        assert(write[1]>=layout.address+(ai-1)*layout.stride)
        assert(write[1]<layout.address+ai*layout.stride)
        assert(loader:getAICValue(ai,'RecruitProbDefDefault')==ai)
      end
      layout.address=0;layout.stride=0
      assert(loader:getNativeAICLayout().address~=0)
      assert(loader:getNativeAICLayout().stride==676)
    ''')
