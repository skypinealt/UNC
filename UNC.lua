local running, passes, fails, undefined = 0, 0, 0, 0

local function getGlobal(path: string)
    local value = getgenv()
    for part in path:gmatch("[^%.]+") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[part]
    end
    return value
end

local function test(name: string, aliases: {string}, callback: (() -> any)?)
    running += 1

    task.spawn(function()
        local exists = getGlobal(name) ~= nil

        if not callback then
            if exists then
                passes += 1
                print("✅ " .. name)
            else
                fails += 1
                warn("⛔ " .. name .. " (not found)")
            end
        else
            if not exists then
                fails += 1
                warn("⛔ " .. name .. " (not found)")
            else
                local ok, result = pcall(callback)
                if ok then
                    passes += 1
                    local msg = result ~= nil and tostring(result) or ""
                    print("✅ " .. name .. (msg ~= "" and " • " .. msg or ""))
                else
                    fails += 1
                    warn("⛔ " .. name .. " failed: " .. tostring(result))
                end
            end
        end

        local missing = {}
        for _, alias in ipairs(aliases) do
            if getGlobal(alias) == nil then
                missing[#missing+1] = alias
            end
        end
        if #missing > 0 then
            undefined += 1
            warn("⚠️ Missing aliases: " .. table.concat(missing, ", "))
        end

        running -= 1
    end)
end

print("====== Unified Naming Convention ======")
print("======    Version: 1.0.0-Beta    ======")

test("checkcaller", {}, function()
    local isMainThread = checkcaller()
    assert(isMainThread, "Expected checkcaller() to return true in main thread context")
end)

test("clonefunction", {}, function()
    local function original_function()
        return "success"
    end
    local cloned_function = clonefunction(original_function)
    assert(original_function() == cloned_function(), "Cloned function must produce identical output to original")
    assert(original_function ~= cloned_function, "Cloned function should be a separate memory reference")
    assert(getfenv(original_function) == getfenv(cloned_function), "Cloned function environment must match original")
end)

test("getfunctionhash", {}, function()
    local function is_sha384_hex(hash)
        return #hash == 96 and hash:match("^[0-9a-fA-F]+$") ~= nil
    end
    local function func_empty() end
    local function func_args(...) end
    local function func_same_empty() end
    local function func_const() return "value" end
    local function func_const_different() return "different_value" end
    local hash_empty = getfunctionhash(func_empty)
    assert(is_sha384_hex(hash_empty), "Hash format invalid: Expected 96-character SHA384 hex string")
    assert(getfunctionhash(func_empty) == getfunctionhash(func_same_empty), "Identical functions should produce identical hashes")
    assert(getfunctionhash(func_empty) ~= getfunctionhash(func_args), "Functions with different code should have different hashes")
    assert(getfunctionhash(func_const) ~= getfunctionhash(func_const_different), "Functions with different constants should have different hashes")
    local success, _ = pcall(function()
        getfunctionhash(print)
    end)
    assert(not success, "Should throw error when hashing C closures")
end)

test("hookfunction", {"replaceclosure"}, function()
    local function original_function()
        return true
    end
    assert(original_function(), "Original function should return true before hooking")
    local hook_function = function()
        return false
    end
    local original_reference = hookfunction(original_function, hook_function)
    assert(not original_function(), "Hooked function should return false after replacement")
    assert(original_reference(), "Original reference should maintain pre-hook behavior")
    assert(original_function ~= original_reference, "Hooked function should be a distinct reference from original")
end)

test("hookmetamethod", {}, function()
    local object = setmetatable({}, {
        __index = newcclosure(function()
            return false
        end),
        __metatable = "Locked"
    })
    assert(object.test == false, "Original __index should return false")
    local hook = newcclosure(function()
        return true
    end)
    local original_index = hookmetamethod(object, "__index", hook)
    assert(object.test == true, "Hooked __index metamethod should return true")
    assert(original_index() == false, "Original metamethod reference must retain initial behavior")
    assert(hook ~= original_index, "Hook and original reference should be distinct functions")
end)

test("iscclosure", {}, function()
    assert(iscclosure(print), "Built-in function 'print' should be recognized as C closure")
    local lua_closure = function()
        return "executor Lua closure"
    end
    assert(not iscclosure(lua_closure), "Standard Lua closures must return false")
    local c_closure = newcclosure(function()
        return "executor C closure"
    end)
    assert(iscclosure(c_closure), "newcclosure-created functions must return true")
end)

test("isexecutorclosure", {"checkclosure", "isourclosure"}, function()
    assert(isexecutorclosure(isexecutorclosure), "Executor global functions should return true")
    local executor_c_closure = newcclosure(function()
        return "executor C closure"
    end)
    assert(isexecutorclosure(executor_c_closure), "newcclosure-generated functions must be recognized as executor closures")
    local executor_lua_closure = function()
        return "executor Lua closure"
    end
    assert(isexecutorclosure(executor_lua_closure), "Standard executor-created Lua closures should return true")
    assert(not isexecutorclosure(print), "Roblox/C-builtin functions like 'print' must return false")
end)

test("islclosure", {}, function()
    local lua_closure = function()
        return "executor Lua closure"
    end
    assert(islclosure(lua_closure), "Standard Lua closures must return true")
    local c_closure = newcclosure(function()
        return "executor C closure"
    end)
    assert(not islclosure(c_closure), "newcclosure-generated functions should return false")
    assert(not islclosure(print), "C-implemented functions like 'print' must return false")
end)

test("newcclosure", {}, function()
    local function original_func()
        return "success"
    end
    local wrapped_func = newcclosure(original_func)
    assert(original_func() == wrapped_func(), "Wrapped C closure must maintain original function's output")
    assert(original_func ~= wrapped_func, "newcclosure should create new function reference")
    assert(iscclosure(wrapped_func), "newcclosure-produced function must register as C closure")
    local yield_check = false
    local yielding_func = newcclosure(function()
        yield_check = true
        task.wait()
    end)
    local co = coroutine.create(yielding_func)
    coroutine.resume(co)
    assert(yield_check, "newcclosure-wrapped functions must support yielding")
    local function upvalue_test()
        local up = "test"
        return function() return up end
    end
    local stripped_func = newcclosure(upvalue_test())
    local upvalues = debug.getupvalues(stripped_func)
    assert(#upvalues == 0, "newcclosure must eliminate all upvalues")
end)

test("crypt.base64decode", {"crypt.base64.decode", "crypt.base64_decode", "base64.decode", "base64_decode"}, function()
    local encoded_data = "dGVzdA=="
    local expected_result = "test"
    assert(crypt.base64decode(encoded_data) == expected_result, ("Decoding failed: Expected '%s' from '%s'"):format(expected_result, encoded_data))
    assert(crypt.base64decode("") == "", "Empty input should produce empty output")
end)

test("crypt.base64encode", {"crypt.base64.encode", "crypt.base64_encode", "base64.encode", "base64_encode"}, function()
    local plaintext = "test"
    local expected_encoded = "dGVzdA=="
    assert(crypt.base64encode(plaintext) == expected_encoded, ("Encoding failed: Expected '%s' got '%s'"):format(expected_encoded, crypt.base64encode(plaintext)))
    local special_case = "DummyString\0\2"
    assert(crypt.base64encode(special_case) == "RHVtbXLTdHJpbmcAAg==", "Special character encoding failed")
    assert(crypt.base64encode("") == "", "Empty input should produce empty output")
end)

test("debug.getconstant", {}, function()
    local function test_func()
        print("Hello, world!")
    end
    assert(debug.getconstant(test_func, 1) == "print", "First constant should reference 'print' function")
    assert(debug.getconstant(test_func, 2) == "Hello, world!", "Second constant should contain message string")
    assert(debug.getconstant(test_func, 3) == nil, "Third constant index should be out of range")
    local success, _ = pcall(function()
        debug.getconstant(print, 1)
    end)
    assert(not success, "Should throw error when accessing C closure constants")
end)

test("debug.getconstants", {}, function()
    local function test_func()
        local num_part1 = 5000
        local num_part2 = 50000
        print("Hello, world!", num_part1 + num_part2, warn)
    end
    local constants = debug.getconstants(test_func)
    assert(constants[1] == 5000, "First constant should be initial numeric literal 5000")
    assert(constants[2] == 50000, "Second constant should be secondary numeric literal 50000")
    assert(constants[3] == "print", "Third constant should reference 'print' function")
    assert(constants[4] == "Hello, world!", "Fourth constant should contain message string")
    assert(constants[5] == "warn", "Fifth constant should reference 'warn' function")
    local success, _ = pcall(function()
        debug.getconstants(print)
    end)
    assert(not success, "Should throw error when accessing C closure constants")
end)

test("debug.getproto", {}, function()
    local function parent_func()
        local function nested_proto()
            return "activated_proto_value"
        end
        return nested_proto
    end
    local real_active_proto = parent_func()
    local retrieved_active_proto = debug.getproto(parent_func, 1, true)[1]
    assert(retrieved_active_proto, "Should retrieve activated function prototype")
    assert(retrieved_active_proto() == "activated_proto_value", "Activated prototype must execute and return expected value")
    assert(real_active_proto == retrieved_active_proto, "Retrieved prototype should match active reference")
    local inactive_proto = debug.getproto(parent_func, 1)
    local success, _ = pcall(inactive_proto)
    assert(not success, "Inactive prototypes should not be directly callable")
    local cclosure_success, _ = pcall(function()
        debug.getproto(print, 1)
    end)
    assert(not cclosure_success, "Should throw error when accessing C closure prototypes")
end)

test("debug.getprotos", {}, function()
    local function parent_func()
        local function proto1() end
        local function proto2() end
        local function proto3() end
    end
    local protos = debug.getprotos(parent_func)
    assert(#protos == 3, "Expected 3 nested prototypes")
    for index, proto in ipairs(protos) do
        local expected_name = "proto"..index
        assert(debug.info(proto, "n") == expected_name, ("Proto %d should be named '%s'"):format(index, expected_name))
        local activated_proto = debug.getproto(parent_func, index, true)[1]
        assert(pcall(activated_proto), ("Activated proto '%s' should be callable"):format(expected_name))
        local inactive_proto = debug.getproto(parent_func, index)
        assert(not pcall(inactive_proto), ("Inactive proto '%s' must not be directly executable"):format(expected_name))
    end
    local success, _ = pcall(function()
        debug.getprotos(print)
    end)
    assert(not success, "Should throw error when accessing C closure protos")
end)

test("debug.getstack", {}, function()
    local var1 = "a".."b"
    local var2 = 42
    local var3 = {key = "value"}
    assert(debug.getstack(1, 1) == var1, "First stack entry should match first local variable")
    local stack_table = debug.getstack(1)
    assert(stack_table[1] == var1 and stack_table[2] == var2 and stack_table[3] == var3, "Stack table should preserve declaration order: var1, var2, var3")
    local success, _ = pcall(function()
        debug.getstack(0)
    end)
    assert(not success, "Should throw error when accessing C closure stack level")
end)

test("debug.getupvalue", {}, function()
    local upvalue_func = function()
        return "upvalue_output"
    end
    local function test_func()
        upvalue_func()
    end
    local retrieved_upvalue = debug.getupvalue(test_func, 1)
    assert(retrieved_upvalue == upvalue_func, "Retrieved upvalue should match original reference")
    assert(retrieved_upvalue() == "upvalue_output", "Retrieved upvalue must maintain original functionality")
    local success, _ = pcall(function()
        debug.getupvalue(test_func, 0)
    end)
    assert(not success, "Should throw error for invalid upvalue index")
    local cclosure_success, _ = pcall(function()
        debug.getupvalue(print, 1)
    end)
    assert(not cclosure_success, "Should throw error when accessing C closure upvalues")
end)

test("debug.getupvalues", {}, function()
    local var1 = "first_value"
    local var2 = "second_value"
    local function test_func()
        print(var1, var2)
    end
    local upvalues = debug.getupvalues(test_func)
    assert(upvalues[1] == var1 and upvalues[2] == var2, "Upvalues should match declaration order: var1, var2")
    local function no_up_func()
        return 123
    end
    local empty_upvalues = debug.getupvalues(no_up_func)
    assert(next(empty_upvalues) == nil, "Function with no upvalues should return empty table")
    local success, _ = pcall(function()
        debug.getupvalues(print)
    end)
    assert(not success, "Should throw error when accessing C closure upvalues")
end)

test("debug.setconstant", {}, function()
    local function test_func()
        return "original_value"
    end
    assert(test_func() == "original_value", "Initial function behavior incorrect")
    debug.setconstant(test_func, 1, "modified_value")
    assert(test_func() == "modified_value", "Function output not updated after constant modification")
    local success, _ = pcall(function()
        debug.setconstant(print, 1, "should_error")
    end)
    assert(not success, "Should throw error when modifying C closure constants")
end)

test("debug.setstack", {}, function()
    local target_value = 10
    local function modifier_function()
        debug.setstack(2, 1, 100)
    end
    modifier_function()
    assert(target_value == 100, "Failed to modify parent scope variable via stack manipulation")
    local function original_func()
        return "original"
    end
    local replacement = function()
        return "replaced"
    end
    debug.setstack(1, 1, replacement)
    assert(original_func() == "replaced", "Function reference replacement failed")
    local success, _ = pcall(function()
        debug.setstack(0, 1, "invalid")
    end)
    assert(not success, "Should throw error when modifying C closure stack")
end)

test("debug.setupvalue", {}, function()
    local base_value = 90
    local function test_func()
        base_value += 1
        return base_value
    end
    test_func()
    debug.setupvalue(test_func, 1, 99)
    assert(test_func() == 100, "Upvalue modification failed: Expected 100 after replacement")
    local original_func = function() return "fail" end
    local function wrapper_func()
        return original_func()
    end
    debug.setupvalue(wrapper_func, 1, function() return "success" end)
    assert(wrapper_func() == "success", "Function upvalue replacement failed")
    local success, _ = pcall(function()
        debug.setupvalue(print, 1, "exploit")
    end)
    assert(not success, "Should throw error when modifying C closure upvalues")
end)

test("cleardrawcache", {}, function()
    local line = Drawing.new("Line")
    line.From = Vector2.new(0, 0)
    line.To = Vector2.new(100, 100)
    line.Visible = true
    assert(line.__OBJECT_EXISTS, "Drawing object should exist before cleanup")
    cleardrawcache()
    task.wait()
    assert(not line.__OBJECT_EXISTS, "Drawing object should be removed after cleardrawcache")
    local circle = Drawing.new("Circle")
    local text = Drawing.new("Text")
    cleardrawcache()
    task.wait()
    assert(not circle.__OBJECT_EXISTS and not text.__OBJECT_EXISTS, "All drawing objects should be cleared")
end)

test("getrenderproperty", {}, function()
    local circle = Drawing.new("Circle")
    circle.Radius = 50
    circle.Visible = true
    assert(getrenderproperty(circle, "Radius") == 50, "Failed to retrieve Radius property value")
    assert(getrenderproperty(circle, "Visible") == true, "Failed to retrieve Visible property state")
    assert(type(getrenderproperty(circle, "Visible")) == "boolean", "Visible property should return boolean")
    local success, _ = pcall(function()
        getrenderproperty(circle, "InvalidProperty")
    end)
    assert(not success, "Should throw error for non-existent properties")
    cleardrawcache()
end)

test("isrenderobj", {}, function()
    local square = Drawing.new("Square")
    assert(isrenderobj(square), "Drawing objects should return true")
    assert(not isrenderobj(workspace), "Instance types must return false")
    assert(not isrenderobj("not a draw"), "Primitive types must return false")
    assert(not isrenderobj({}), "Tables should return false")
    cleardrawcache()
end)

test("setrenderproperty", {}, function()
    local circle = Drawing.new("Circle")
    setrenderproperty(circle, "Radius", 50)
    setrenderproperty(circle, "Visible", true)
    assert(circle.Radius == 50, "Failed to set numeric property: Radius")
    assert(circle.Visible == true, "Failed to set boolean property: Visible")
    setrenderproperty(circle, "Color", Color3.fromRGB(255, 0, 0))
    assert(circle.Color == Color3.fromRGB(255, 0, 0), "Failed to set Color property")
    local success, _ = pcall(function()
        setrenderproperty(circle, "InvalidProp", 123)
    end)
    assert(not success, "Should throw error for non-existent properties")
    cleardrawcache()
end)

test("getgc", {}, function()
    local dummy_func = function() end
    local dummy_table = {}
    task.wait(0.05)
    local gc_default = getgc()
    assert(type(gc_default) == "table", "getgc() should return table")
    assert(#gc_default > 0, "getgc() returned empty table in live environment")
    local function_found, table_found = false, false
    for _, obj in pairs(gc_default) do
        if obj == dummy_func then function_found = true end
        if obj == dummy_table then table_found = true end
    end
    assert(function_found, "Functions should appear in default getgc() scan")
    assert(not table_found, "Tables shouldn't appear in getgc() without includeTables=true")
    local gc_incl_tables = getgc(true)
    local func_incl_found, table_incl_found = false, false
    for _, obj in pairs(gc_incl_tables) do
        if obj == dummy_func then func_incl_found = true end
        if obj == dummy_table then table_incl_found = true end
    end
    assert(func_incl_found and table_incl_found, "Both functions and tables should be found with includeTables=true")
end)

test("getgenv", {}, function()
    getgenv().test_value = "persistent"
    assert(test_value == "persistent", "getgenv values should be globally accessible")
    getfenv().test_value = "temporary"
    assert(getgenv().test_value == "persistent", "Local environment changes shouldn't affect getgenv")
    test_value = nil
    assert(getgenv().test_value == "persistent", "getgenv values should persist despite local nil assignments")
    getgenv().test_value = nil
end)

test("getrenv", {}, function()
    local original_game = game
    getrenv().game = nil
    assert(game == nil, "getrenv modifications should affect executor globals")
    getrenv().game = original_game
    assert(_G ~= getrenv()._G, "Executor _G should be separate from Roblox environment _G")
    getrenv().custom_global = "test_value"
    assert(custom_global == "test_value", "getrenv-injected values should be globally accessible")
    getrenv().custom_global = nil
end)

test("cloneref", {}, function()
    local original = Instance.new("Part")
    original.Name = "OriginalPart"
    local clone = cloneref(original)
    assert(original ~= clone, "Clone should be distinct reference from original")
    assert(clone.Name == "OriginalPart", "Clone should inherit original properties")
    clone.Name = "ClonedPart"
    assert(original.Name == "OriginalPart", "Clone modifications shouldn't affect original instance")
    clone.Parent = workspace
    assert(clone:IsDescendantOf(workspace), "Clone should behave like normal Instance")
end)

test("fireclickdetector", {}, function()
    local detector = Instance.new("ClickDetector")
    local eventFired = false
    detector.MouseHoverEnter:Connect(function(player)
        eventFired = true
    end)
    fireclickdetector(detector, 50, "MouseHoverEnter")
    assert(eventFired, "MouseHoverEnter event should fire with explicit parameters")
    eventFired = false
    fireclickdetector(detector)
    assert(not eventFired, "Default parameters shouldn't trigger HoverEnter event")
    detector:Destroy()
end)

test("getcallbackvalue", {}, function()
    local bindable = Instance.new("BindableFunction")
    local callback_triggered = false
    local test_callback = function()
        callback_triggered = true
    end
    bindable.OnInvoke = test_callback
    local retrieved = getcallbackvalue(bindable, "OnInvoke")
    assert(retrieved == test_callback, "Should retrieve exact callback reference")
    retrieved()
    assert(callback_triggered, "Retrieved callback should execute normally")
    local remote = Instance.new("RemoteFunction")
    assert(getcallbackvalue(remote, "OnClientInvoke") == nil, "Unset callback properties should return nil")
    local success, _ = pcall(function()
        getcallbackvalue(bindable, "InvalidProperty")
    end)
    assert(not success, "Should throw error for non-existent properties")
    bindable:Destroy()
    remote:Destroy()
end)

test("gethui", {}, function()
    local container = gethui()
    assert(container:IsA("Folder") or container:IsA("BasePlayerGui"), "gethui should return Folder or BasePlayerGui instance")
    local test_gui = Instance.new("ScreenGui")
    test_gui.Name = "TestGUI"
    test_gui.Parent = container
    assert(container:FindFirstChild("TestGUI") == test_gui, "GUI elements should be parentable to gethui container")
    assert(gethui() == container, "gethui should consistently return the same container")
    test_gui:Destroy()
end)

test("getinstances", {}, function()
    local test_part = Instance.new("Part")
    test_part.Parent = nil
    local found = false
    for _, instance in pairs(getinstances()) do
        assert(instance:IsA("Instance"), "All returned values must be Instances")
        if instance == test_part then
            found = true
        end
    end
    assert(found, "Nil-parented instances should appear in getinstances() results")
    test_part:Destroy()
end)

test("getnilinstances", {}, function()
    local test_part = Instance.new("Part")
    test_part.Parent = nil
    local found = false
    for _, instance in pairs(getnilinstances()) do
        assert(instance.Parent == nil, "All returned instances must be unparented")
        if instance == test_part then
            found = true
        end
    end
    assert(found, "Newly created nil-parented instance should appear in results")
    test_part.Parent = workspace
    for _, instance in pairs(getnilinstances()) do
        if instance == test_part then
            error("Parented instance should be removed from nil instances list")
        end
    end
    test_part:Destroy()
end)

test("getrawmetatable", {}, function()
    local test_table = {}
    local test_metatable = {
        __index = function(t, k)
            return "Intercepted "..k
        end,
        __metatable = "Locked Metatable"
    }
    setmetatable(test_table, test_metatable)
    local raw_mt = getrawmetatable(test_table)
    assert(raw_mt == test_metatable, "Should retrieve original metatable despite __metatable lock")
    assert(test_table.TestKey == "Intercepted TestKey", "Metatable __index should function normally")
    local plain_object = newproxy(false)
    assert(getrawmetatable(plain_object) == nil, "Should return nil for objects without metatables")
    assert(getmetatable(test_table) == "Locked Metatable", "Standard getmetatable should respect __metatable lock")
end)

test("isreadonly", {}, function()
    assert(not isreadonly({}), "Regular tables should not be read-only")
    assert(isreadonly(getrawmetatable(game)), "Game's raw metatable should be read-only")
    local frozen_table = table.freeze({})
    assert(isreadonly(frozen_table), "Frozen tables should be recognized as read-only")
end)

test("setrawmetatable", {}, function()
    local original_mt = {
        __index = function() return "original" end,
        __metatable = "Locked!"
    }
    local object = setmetatable({}, original_mt)
    local new_mt = {
        __index = function() return "overridden" end
    }
    local return_value = setrawmetatable(object, new_mt)
    assert(return_value == object, "Should return original object reference")
    assert(getrawmetatable(object) == new_mt, "Failed to override protected metatable")
    assert(object.NonExistentKey == "overridden", "New metatable __index should be active")
    setrawmetatable(object, nil)
    assert(getrawmetatable(object) == nil, "Should allow setting nil metatable")
    local test_string = "test"
    setrawmetatable(test_string, {__index = string})
    assert(test_string.upper() == "TEST", "Should enable string method access via metatable")
end)

test("identifyexecutor", {}, function()
    local name, version = identifyexecutor()
    assert(type(name) == "string", "Executor name must be a string")
    assert(type(version) == "string", "Executor version must be a string")
    assert(#name > 0, "Executor name should not be empty")
    assert(#version > 0, "Executor version should not be empty")
    assert(name:match("%S+") and version:match("%d+%.%d+%.%d+"), "Version should follow semantic format (e.g., '1.0.0')")
end)

test("request", {"http.request", "http_request"}, function()
    local response = request({
        Url = "https://httpbin.org/user-agent",
        Method = "GET"
    })
    assert(type(response) == "table", "Response must return a table")
    assert(response.Success == true, "Request should be successful")
    assert(response.StatusCode == 200, "Expected status code 200, got "..tostring(response.StatusCode))
    local decoded = game:GetService("HttpService"):JSONDecode(response.Body)
    assert(type(decoded) == "table" and type(decoded["user-agent"]) == "string", "Response body missing valid User-Agent data")
    assert(response.Headers["User-Agent"] == decoded["user-agent"], "User-Agent header should match body data")
    return "User-Agent Header: "..response.Headers["User-Agent"]..
           "\nExecutor Version: "..decoded["user-agent"]
end)

test("gethiddenproperty", {}, function()
    local part = Instance.new("Part")
    local name_value, is_hidden = gethiddenproperty(part, "Name")
    assert(name_value == "Part", "Should retrieve standard property value")
    assert(not is_hidden, "Name property should not be marked as hidden")
    local data_cost, is_hidden = gethiddenproperty(part, "DataCost")
    assert(type(data_cost) == "number", "Should retrieve numeric DataCost value")
    assert(is_hidden, "DataCost should be recognized as hidden property")
    local success, _ = pcall(function()
        gethiddenproperty(part, "NonExistentProperty")
    end)
    assert(not success, "Should throw error for invalid properties")
end)

test("getthreadidentity", {}, function()
    local original_identity = getthreadidentity()
    assert(type(original_identity) == "number", "Should return numeric thread identity")
    assert(original_identity >= 0 and original_identity <= 8, "Identity should be within valid Roblox range (0-8)")
    setthreadidentity(2)
    assert(getthreadidentity() == 2, "Should reflect updated thread identity")
    setthreadidentity(original_identity)
    assert(getthreadidentity() == original_identity, "Failed to restore original thread identity")
end)

test("sethiddenproperty", {}, function()
    local part = Instance.new("Part")
    local initial_value, is_hidden = gethiddenproperty(part, "DataCost")
    assert(is_hidden, "DataCost should be a hidden property")
    local success = sethiddenproperty(part, "DataCost", 100)
    assert(success, "Should return true for successful hidden property modification")
    assert(gethiddenproperty(part, "DataCost") == 100, "Failed to update hidden property value")
    local name_success = sethiddenproperty(part, "Name", "TestPart")
    assert(not name_success, "Should return false when modifying non-hidden property")
    assert(part.Name == "TestPart", "Should still update non-hidden property value")
    local invalid_success, err = pcall(function()
        sethiddenproperty(part, "InvalidProperty", 123)
    end)
    assert(not invalid_success, "Should throw error for invalid properties")
end)

test("setscriptable", {}, function()
    local part = Instance.new("Part")
    local success_before, _ = pcall(function()
        return part.BottomParamA
    end)
    assert(not success_before, "Property should be non-scriptable initially")
    setscriptable(part, "BottomParamA", true)
    assert(pcall(function() return part.BottomParamA end), "Property should be accessible after enabling scriptability")
    assert(type(part.BottomParamA) == "number", "Should retrieve numeric value for BottomParamA")
    setscriptable(part, "BottomParamA", false)
    local success_after, _ = pcall(function()
        return part.BottomParamA
    end)
    assert(not success_after, "Property should become inaccessible after disabling scriptability")
    local new_part = Instance.new("Part")
    assert(pcall(function() return new_part.BottomParamA end) == false, "Scriptability changes should not persist across instances")
end)

test("setthreadidentity", {}, function()
    local original_identity = getthreadidentity()
    setthreadidentity(8)
    assert(getthreadidentity() == 8, "Failed to set thread identity to privileged level")
    local success = pcall(function()
        return game:GetService("CoreGui")
    end)
    assert(success, "Should allow access to protected services at identity 8")
    setthreadidentity(2)
    local restricted_success = pcall(function()
        return game:GetService("CoreGui")
    end)
    assert(not restricted_success, "Should restrict access at lower identity levels")
    setthreadidentity(original_identity)
end)

test("getloadedmodules", {}, function()
    local loaded_module = Instance.new("ModuleScript")
    local unloaded_module = Instance.new("ModuleScript")
    pcall(require, loaded_module)
    local modules = getloadedmodules()
    assert(type(modules) == "table", "Should return table")
    local found_loaded, found_unloaded = false, false
    for _, module in ipairs(modules) do
        if module == loaded_module then
            found_loaded = true
        elseif module == unloaded_module then
            found_unloaded = true
        end
        assert(module:IsA("ModuleScript"), "All returned items must be ModuleScripts")
    end
    assert(found_loaded, "Required module should appear in results")
    assert(not found_unloaded, "Unrequired module should not appear in results")
    loaded_module:Destroy()
    unloaded_module:Destroy()
end)

test("getrunningscripts", {}, function()
    local active_script = Instance.new("LocalScript")
    local inactive_script = Instance.new("LocalScript")
    active_script.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    local running_scripts = getrunningscripts()
    assert(type(running_scripts) == "table", "Should return table")
    local found_active, found_inactive = false, false
    for _, script in ipairs(running_scripts) do
        assert(script:IsA("LuaSourceContainer"), "All entries should be Script/LocalScript/ModuleScript")
        if script == active_script then
            found_active = true
        elseif script == inactive_script then
            found_inactive = true
        end
    end
    assert(found_active, "Actively running script should appear in results")
    assert(not found_inactive, "Inactive script should not appear in results")
    active_script:Destroy()
    inactive_script:Destroy()
end)

test("getscripts", {}, function()
    local test_scripts = {
        LocalScript = Instance.new("LocalScript"),
        ModuleScript = Instance.new("ModuleScript"),
        Script = Instance.new("Script")
    }
    for _, script in pairs(test_scripts) do
        script.Parent = workspace
    end
    local scripts = getscripts()
    assert(type(scripts) == "table", "Should return table")
    for script_type, script in pairs(test_scripts) do
        local found = false
        for _, s in ipairs(scripts) do
            if s == script then
                found = true
                break
            end
        end
        assert(found, ("%s should appear in getscripts() results"):format(script_type))
    end
    for _, script in ipairs(scripts) do
        assert(script:IsA("LuaSourceContainer"), "All entries must be Script/LocalScript/ModuleScript")
    end
    for _, script in pairs(test_scripts) do
        script:Destroy()
    end
end)

test("loadstring", {}, function()
    local func = loadstring([[return "Hello "..(...)]], "GreetingChunk")
    assert(type(func) == "function", "Should return function for valid source")
    assert(func("World") == "Hello World", "Compiled function should execute correctly")
    local err_func, err_msg = loadstring("1 ++ 2", "InvalidSyntaxChunk")
    assert(err_func == nil, "Should return nil for invalid syntax")
    assert(type(err_msg) == "string" and err_msg:find("syntax error"), "Should return meaningful error message")
    local test_script = Instance.new("LocalScript")
    test_script.Source = "return 123"
    local bytecode = getscriptbytecode(test_script)
    if bytecode then
        assert(loadstring(bytecode) == nil, "Should prevent loading raw Luau bytecode")
    end
    test_script:Destroy()
end)

test("firesignal", {}, function()
    local part = Instance.new("Part")
    local test_folder = Instance.new("Folder")
    local captured_args = {}
    local fire_count = 0
    part.ChildAdded:Connect(function(arg)
        table.insert(captured_args, arg)
        fire_count += 1
    end)
    firesignal(part.ChildAdded)
    assert(captured_args[1] == nil, "First fire should pass nil argument")
    firesignal(part.ChildAdded, test_folder)
    assert(captured_args[2] == test_folder, "Second fire should pass Folder instance")
    assert(fire_count == 2, "Signal should trigger all connected handlers twice")
    local second_counter = 0
    part.ChildAdded:Connect(function()
        second_counter += 1
    end)
    firesignal(part.ChildAdded)
    assert(second_counter == 1, "New connection should also fire")
    part:Destroy()
    test_folder:Destroy()
end)

test("getconnections", {}, function()
    local folder = Instance.new("Folder")
    local connection
    folder.ChildAdded:Connect(function()
        return "Triggered"
    end)
    connection = getconnections(folder.ChildAdded)[1]
    assert(type(connection.Function) == "function", "Luau connection should have callable Function")
    assert(type(connection.Thread) == "thread", "Luau connection should reference execution thread")
    assert(pcall(connection.Fire), "Luau connection should be fireable")
    local player = game:GetService("Players").LocalPlayer
    local idle_connection = getconnections(player.Idled)[1]
    assert(idle_connection.Function == nil, "Foreign connection Function should be nil")
    assert(idle_connection.Thread == nil, "Foreign connection Thread should be nil")
    assert(type(connection.Disconnect) == "function", "All connections should have Disconnect method")
end)

test("replicatesignal", {}, function()
    local part = Instance.new("Part")
    part.Name = "TestReplicatePart"
    part.Parent = workspace
    local clickDetector = Instance.new("ClickDetector")
    clickDetector.Parent = part
    local success = pcall(function()
        replicatesignal(clickDetector.MouseClick, game.Players.LocalPlayer, 0)
    end)
    assert(success, "Valid arguments should replicate without error")
    local function test_arg_error(args)
        local s, _ = pcall(replicatesignal, clickDetector.MouseClick, unpack(args or {}))
        return not s
    end
    assert(test_arg_error(), "Should throw error for missing arguments")
    assert(test_arg_error({game.Players.LocalPlayer}), "Should throw error for incomplete arguments")
    part:Destroy()
end)

test("WebSocket.connect", {}, function()
    local ws = WebSocket.connect("ws://echo.websocket.events")
    assert(typeof(ws) == "userdata" or typeof(ws) == "table", "WebSocket instance should be userdata/table")
    assert(type(ws.Send) == "function", "WebSocket should have Send method")
    assert(type(ws.Close) == "function", "WebSocket should have Close method")
    assert(typeof(ws.OnMessage) == "RBXScriptSignal", "OnMessage should be an event signal")
    assert(typeof(ws.OnClose) == "RBXScriptSignal", "OnClose should be an event signal")
    local received = false
    ws.OnMessage:Connect(function(msg)
        received = (msg == "TEST_MESSAGE")
    end)
    ws:Send("TEST_MESSAGE")
    local timeout = os.clock() + 5
    repeat task.wait() until received or os.clock() > timeout
    assert(received, "Did not receive echo response")
    ws:Close()
end)

task.defer(function()
    repeat task.wait() until running == 0

    local total = passes + fails
    local rate = total > 0 and math.round(passes / total * 100) or 0

    print("====== UNC Test Results ======")
    print(("✅ Passed: %d/%d (%d%%)"):format(passes, total, rate))
    print(("⛔ Failed: %d"):format(fails))
    print(("⚠️ Missing aliases in %d tests"):format(undefined))
end)