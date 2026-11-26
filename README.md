# Extension AIC Loader

This repository contains a module for the "Unofficial Crusader Patch Version 3" (UCP3), a modification for Stronghold Crusader.  
The module is a core component of the AI support of the UCP3 and allows modifying the parameters that decide how an AI acts.

### Usage

The module is part of the UCP3. Certain commits of the main branch of this repository are included as a git submodule.
It is therefore not needed to download additional content.  
However, should issues or suggestions arise that are related to this module, feel free to add a new GitHub issue.

### Options

These options are provided to be set in the GUI:

* **failureHandling** - Defines how the modules handles invalid AIC values.
    * *WARN_LOG*  
    A warning is printed to the console and game continues.
    * *ERROR_LOG*  
    An error is printed to the console and a message window with the error is shown. The game will continue.
    * *FATAL_LOG*  
    An error is printed to the console and a message window with the error is shown. The game will abort.

### Lua-Exports

The Lua exports are parameters and functions accessible through the module object. These are `self` calls and need to be called as `modules.aicloader:function(...)`.

* `void setAICValue(aiType, aicField, aicValue, failureHandlingOverride)`  
Sets a specific AIC value.  
The `aiType` can either be the AI slot name or the index. `aicField` needs to be one of the supported AIC value names and `aicValue` a valid value. `failureHandlingOverride` is optional and can be one of the values of `failureHandling`.  
This function is available for plugins.

* `void overwriteAIC(aiType, aicSpec, failureHandlingOverride)`  
Overwrites multiple AIC values of an AI.  
Similar to `setAICValue`, but `aicSpec` is a table of `aicField` and `aicValue` pairs.  
This function is available for plugins.

* `void overwriteAICsFromFile(aicFilePath, failureHandlingOverride)`  
Overwrites multiple AIC values from a file.  
The functions expects a path to a YAML-file containing an `AICharacters` object with AI entries of objects that need to contain a field `Name` and a field `Personality` where `Name` is one of the supported AI slot names and `Personality` is a table of `aicField` and `aicValue` pairs.  
This function is available for plugins.

* `void resetAIC(aiType)`  
Resets the given AI to its default values.  
This function is available for plugins.

* `void setAICValueOverride(aicField, index, valueFunction, resetFunction)`  
Overrides an already existing AIC value.  
`aicField` functions as an identifier for this setting, while `index` is the index of the real AIC value. If it is set to `nil`, the override is removed. `valueFunction` receives the value to set and needs to return the actual value to write in the form of an integer. `resetFunction` receives the index of the AI slot and needs to return the default value for this slot as integer.  
Not recommended to use. An index might get overridden multiple times. Try to use `setAdditionalAICValue` instead and handle the values in your code.

* `void setAdditionalAICValue(aicField, handlerFunction, resetFunction)`  
Adds an completely new AIC value for the loader to handle.  
`aicField` functions as an identifier for this setting, while `handlerFunction` receives the AI slot index and the provided value. The actual value handling needs to happen at the side of the provider. If the `handlerFunction` is set to `nil`, the new AIC value is removed. `resetFunction` will always receive an AI slot index starting from 1 (Rat) to 16 (Abbot) and needs to reset the value to the default for this slot.


### Exclusive additional field registration

New modules can use `registerAdditionalAICValue(owner, aicField, handlerFunction,
resetFunction)` to claim a field exclusively. Use the module name as `owner`.
Registration rejects native names (including aliases), registered overrides,
and any existing additional handler, including another registration by the same
owner. Register once during module setup. This API is available to modules,
not plugins; personality application continues through the existing public APIs.

The provider owns the storage and validation. Its handler receives the AI
character slot (1–16) and the value on set; on get it receives nil and must return
the current authored value without changing state. Its reset callback restores
that slot's default. Slots are personality configuration, not player runtime
state: two players using the same character share configuration only.

`getAdditionalAICValueOwner(aicField)` returns the registered module name, or nil
for an unknown/native field or a handler registered with the older API.
`unregisterAdditionalAICValue(owner, aicField)` removes only a matching exclusive
registration. It does not reset or migrate provider state; the provider must use
a safe lifecycle boundary. Owner names coordinate modules; they are not a
security boundary against privileged code.

Neither `setAdditionalAICValue` (including its nil removal form) nor
`setAICValueOverride` can replace or remove an exclusively claimed name. Existing
unclaimed additional fields retain their original replacement/removal behavior.
Native field indices, values, validation and layout are unchanged. Existing AIC
files require no conversion. To migrate a module, replace its registration call
with the exclusive API and implement the nil getter if missing. Do not rewrite
personality files. Rolling back the module requires its original loader API call;
declare a loader version with this capability in the module's package dependency
once that loader version is released.

This registration API does **not** make `overwriteAIC` atomic or authorize live
simulation changes. Its existing per-field failure handling remains in effect.
Whole-row probability validation and synchronized save/replay state are separate
prerequisites for extended recruitment policies.

### Special Thanks

To all of the UCP Team, the [Ghidra project](https://github.com/NationalSecurityAgency/ghidra) and
of course to [Firefly Studios](https://fireflyworlds.com/), the creators of Stronghold Crusader.
