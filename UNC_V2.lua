local totalPasses = 0
local totalFails = 0
local totalUndefined = 0
local testsRunning = 0

local function getGlobalValue(path)
    local value = getgenv and getgenv() or getfenv(2)

    while value ~= nil and path ~= "" do
        local name, nextPath = string.match(path, "^([^.]+)%.?(.*)$")
        value = value[name]
        path = nextPath
    end

    return value
end

local function runTest(testName, aliases, testCallback, target)
    testsRunning = testsRunning + 1

    task.spawn(function()
        if not testCallback then
            print("🚫 " .. testName)
        elseif not getGlobalValue(testName) then
            totalFails = totalFails + 1
            warn("❌ " .. testName)
        else
            local success, message = pcall(testCallback)
            testName = tostring(testName)
            message = tostring(message)
            if success then
                totalPasses = totalPasses + 1
                print("✅ " .. testName .. (message and " • " .. message or ""))
            else
                totalFails = totalFails + 1
                warn("❌ " .. testName .. " failed: " .. message)
            end
        end

        local undefinedAliases = {}
        for _, alias in ipairs(aliases) do
            if getGlobalValue(alias) == nil then
                table.insert(undefinedAliases, alias)
            end
        end

        if #undefinedAliases > 0 then
            totalUndefined = totalUndefined + 1
            warn("⚠️ " .. table.concat(undefinedAliases, ", "))
        end

        testsRunning = testsRunning - 1
    end)
end

local function printSummary()
    print("\n")
    print("UNC V2 Environment Check")
    print("✅ - Pass, ❌ - Fail, 🚫 - No test, ⚠️ - Missing aliases\n")

    task.defer(function()
        repeat task.wait() until testsRunning == 0
        local successRate = math.round(totalPasses / (totalPasses + totalFails) * 100)
        local outOf = totalPasses .. " out of " .. (totalPasses + totalFails)

        print("\n")
        print("UNC V2 Summary")
        print("✅ Pass with a " .. successRate .. "% success rate (" .. outOf .. ")")
        print("⛔ " .. totalFails .. " tests failed")
        print("⚠️ " .. totalUndefined .. " missing aliases")
    end)
end

-- Cache Tests
runTest("cache.invalidate", {}, function()
    local container = Instance.new("Folder")
    local part = Instance.new("Part", container)
    cache.invalidate(container:FindFirstChild("Part"))
    assert(part ~= container:FindFirstChild("Part"), "Reference `part` could not be invalidated")
end)

runTest("cache.iscached", {}, function()
    local part = Instance.new("Part")
    assert(cache.iscached(part), "Part should be cached")
    cache.invalidate(part)
    assert(not cache.iscached(part), "Part should not be cached")
end)

runTest("cache.replace", {}, function()
    local part = Instance.new("Part")
    local fire = Instance.new("Fire")
    cache.replace(part, fire)
    assert(part ~= fire, "Part was not replaced with Fire")
end)

runTest("cloneref", {}, function()
    local part = Instance.new("Part")
    local clone = cloneref(part)
    assert(part ~= clone, "Clone should not be equal to original")
    clone.Name = "Test"
    assert(part.Name == "Test", "Clone should have updated the original")
end)

runTest("compareinstances", {}, function()
    local part = Instance.new("Part")
    local clone = cloneref(part)
    assert(part ~= clone, "Clone should not be equal to original")
    assert(compareinstances(part, clone), "Clone should be equal to original when using compareinstances()")
end)

-- Closures Tests
local function shallowEqual(table1, table2)
    if table1 == table2 then
        return true
    end

    local uniqueTypes = {
        ["function"] = true,
        ["table"] = true,
        ["userdata"] = true,
        ["thread"] = true,
    }

    for key, value in pairs(table1) do
        if uniqueTypes[type(value)] then
            if type(table2[key]) ~= type(value) then
                return false
            end
        elseif table2[key] ~= value then
            return false
        end
    end

    for key, value in pairs(table2) do
        if uniqueTypes[type(value)] then
            if type(table1[key]) ~= type(value) then
                return false
            end
        elseif table1[key] ~= value then
            return false
        end
    end

    return true
end

runTest("checkcaller", {}, function()
    assert(checkcaller(), "Main scope should return true")
end)

runTest("clonefunction", {}, function()
    local function test()
        return "success"
    end
    local copy = clonefunction(test)
    assert(test() == copy(), "The clone should return the same value as the original")
    assert(test ~= copy, "The clone should not be equal to the original")
end)

runTest("getscriptclosure", {"getscriptfunction"}, function()
    local module = game:GetService("CoreGui").RobloxGui.Modules.Common.Constants
    local constants = getrenv().require(module)
    local generated = getscriptclosure(module)()
    assert(constants ~= generated, "Generated module should not match the original")
    assert(shallowEqual(constants, generated), "Generated constant table should be shallow equal to the original")
end)

runTest("hookfunction", {"replaceclosure"}, function()
    local function test()
        return true
    end
    local ref = hookfunction(test, function()
        return false
    end)
    assert(test() == false, "Function should return false")
    assert(ref() == true, "Original function should return true")
    assert(test ~= ref, "Original function should not be same as the reference")
end)

runTest("iscclosure", {}, function()
    assert(iscclosure(print) == true, "Function 'print' should be a C closure")
    assert(iscclosure(function() end) == false, "Executor function should not be a C closure")
end)

runTest("islclosure", {}, function()
    assert(islclosure(print) == false, "Function 'print' should not be a Lua closure")
    assert(islclosure(function() end) == true, "Executor function should be a Lua closure")
end)

runTest("isexecutorclosure", {"checkclosure", "isourclosure"}, function()
    assert(isexecutorclosure(isexecutorclosure) == true, "Did not return true for an executor global")
    assert(isexecutorclosure(newcclosure(function() end)) == true, "Did not return true for an executor C closure")
    assert(isexecutorclosure(function() end) == true, "Did not return true for an executor Luau closure")
    assert(isexecutorclosure(print) == false, "Did not return false for a Roblox global")
end)

runTest("loadstring", {}, function()
    local animate = game:GetService("Players").LocalPlayer.Character.Animate
    local bytecode = getscriptbytecode(animate)
    local func = loadstring(bytecode)
    assert(type(func) ~= "function", "Luau bytecode should not be loadable!")
    assert(assert(loadstring("return ... + 1"))(1) == 2, "Failed to do simple math")
    assert(type(select(2, loadstring("f"))) == "string", "Loadstring did not return anything for a compiler error")
end)

runTest("newcclosure", {}, function()
    local function test()
        return true
    end
    local testC = newcclosure(test)
    assert(test() == testC(), "New C closure should return the same value as the original")
    assert(test ~= testC, "New C closure should not be same as the original")
    assert(iscclosure(testC), "New C closure should be a C closure")
end)

-- Crypt Tests
runTest("crypt.base64encode", {"crypt.base64.encode", "crypt.base64_encode", "base64.encode", "base64_encode"}, function()
    assert(crypt.base64encode("test") == "dGVzdA==", "Base64 encoding failed")
end)

runTest("crypt.base64decode", {"crypt.base64.decode", "crypt.base64_decode", "base64.decode", "base64_decode"}, function()
    assert(crypt.base64decode("dGVzdA==") == "test", "Base64 decoding failed")
end)

runTest("crypt.encrypt", {}, function()
    local key = crypt.generatekey()
    local encrypted, iv = crypt.encrypt("test", key, nil, "CBC")
    assert(iv, "crypt.encrypt should return an IV")
    local decrypted = crypt.decrypt(encrypted, key, iv, "CBC")
    assert(decrypted == "test", "Failed to decrypt raw string from encrypted data")
end)

runTest("crypt.decrypt", {}, function()
    local key, iv = crypt.generatekey(), crypt.generatekey()
    local encrypted = crypt.encrypt("test", key, iv, "CBC")
    local decrypted = crypt.decrypt(encrypted, key, iv, "CBC")
    assert(decrypted == "test", "Failed to decrypt raw string from encrypted data")
end)

runTest("crypt.generatebytes", {}, function()
    local size = math.random(10, 100)
    local bytes = crypt.generatebytes(size)
    assert(#crypt.base64decode(bytes) == size, "The decoded result should be " .. size .. " bytes long (got " .. #crypt.base64decode(bytes) .. " decoded, " .. #bytes .. " raw)")
end)

runTest("crypt.generatekey", {}, function()
    local key = crypt.generatekey()
    assert(#crypt.base64decode(key) == 32, "Generated key should be 32 bytes long when decoded")
end)

runTest("crypt.hash", {}, function()
    local algorithms = {'sha1', 'sha384', 'sha512', 'md5', 'sha256', 'sha3-224', 'sha3-256', 'sha3-512'}
    for _, algorithm in ipairs(algorithms) do
        local hash = crypt.hash("test", algorithm)
        assert(hash, "crypt.hash on algorithm '" .. algorithm .. "' should return a hash")
    end
end)

-- Debug Tests
runTest("debug.getconstant", {}, function()
    local function test()
        print("Hello, world!")
    end
    assert(debug.getconstant(test, 1) == "print", "First constant must be print")
    assert(debug.getconstant(test, 2) == nil, "Second constant must be nil")
    assert(debug.getconstant(test, 3) == "Hello, world!", "Third constant must be 'Hello, world!'")
end)

runTest("debug.getconstants", {}, function()
    local function test()
        local num = 5000 .. 50000
        print("Hello, world!", num, warn)
    end
    local constants = debug.getconstants(test)
    assert(constants[1] == 50000, "First constant must be 50000")
    assert(constants[2] == "print", "Second constant must be print")
    assert(constants[3] == nil, "Third constant must be nil")
    assert(constants[4] == "Hello, world!", "Fourth constant must be 'Hello, world!'")
    assert(constants[5] == "warn", "Fifth constant must be warn")
end)

runTest("debug.getinfo", {}, function()
    local types = {
        source = "string",
        short_src = "string",
        func = "function",
        what = "string",
        currentline = "number",
        name = "string",
        nups = "number",
        numparams = "number",
        is_vararg = "number",
    }
    local function test(...)
        print(...)
    end
    local info = debug.getinfo(test)
    for key, valueType in pairs(types) do
        assert(info[key] ~= nil, "Did not return a table with a '" .. key .. "' field")
        assert(type(info[key]) == valueType, "Did not return a table with " .. key .. " as a " .. valueType .. " (got " .. type(info[key]) .. ")")
    end
end)

runTest("debug.getproto", {}, function()
    local function test()
        local function proto()
            return true
        end
    end
    local proto = debug.getproto(test, 1, true)[1]
    local realproto = debug.getproto(test, 1)
    assert(proto, "Failed to get the inner function")
    assert(proto() == true, "The inner function did not return anything")
    if not realproto() then
        return "Proto return values are disabled on this executor"
    end
end)

runTest("debug.getprotos", {}, function()
    local function test()
        local function _1()
            return true
        end
        local function _2()
            return true
        end
        local function _3()
            return true
        end
    end
    for index in ipairs(debug.getprotos(test)) do
        local proto = debug.getproto(test, index, true)[1]
        local realproto = debug.getproto(test, index)
        assert(proto(), "Failed to get inner function " .. index)
        if not realproto() then
            return "Proto return values are disabled on this executor"
        end
    end
end)

runTest("debug.getstack", {}, function()
    local _ = "a" .. "b"
    assert(debug.getstack(1, 1) == "ab", "The first item in the stack should be 'ab'")
    assert(debug.getstack(1)[1] == "ab", "The first item in the stack table should be 'ab'")
end)

runTest("debug.getupvalue", {}, function()
    local upvalue = function() end
    local function test()
        print(upvalue)
    end
    assert(debug.getupvalue(test, 1) == upvalue, "Unexpected value returned from debug.getupvalue")
end)

runTest("debug.getupvalues", {}, function()
    local upvalue = function() end
    local function test()
        print(upvalue)
    end
    local upvalues = debug.getupvalues(test)
    assert(upvalues[1] == upvalue, "Unexpected value returned from debug.getupvalues")
end)

runTest("debug.setconstant", {}, function()
    local function test()
        return "fail"
    end
    debug.setconstant(test, 1, "success")
    assert(test() == "success", "debug.setconstant did not set the first constant")
end)

runTest("debug.setstack", {}, function()
    local function test()
        return "fail", debug.setstack(1, 1, "success")
    end
    assert(test() == "success", "debug.setstack did not set the first stack item")
end)

runTest("debug.setupvalue", {}, function()
    local function upvalue()
        return "fail"
    end
    local function test()
        return upvalue()
    end
    debug.setupvalue(test, 1, function()
        return "success"
    end)
    assert(test() == "success", "debug.setupvalue did not set the first upvalue")
end)

-- Filesystem Tests
if isfolder and makefolder and delfolder then
    if isfolder(".tests") then
        delfolder(".tests")
    end
    makefolder(".tests")
end

runTest("readfile", {}, function()
    writefile(".tests/readfile.txt", "success")
    assert(readfile(".tests/readfile.txt") == "success", "Did not return the contents of the file")
end)

runTest("listfiles", {}, function()
    makefolder(".tests/listfiles")
    writefile(".tests/listfiles/test_1.txt", "success")
    writefile(".tests/listfiles/test_2.txt", "success")
    local files = listfiles(".tests/listfiles")
    assert(#files == 2, "Did not return the correct number of files")
    assert(isfile(files[1]), "Did not return a file path")
    assert(readfile(files[1]) == "success", "Did not return the correct files")
    makefolder(".tests/listfiles_2")
    makefolder(".tests/listfiles_2/test_1")
    makefolder(".tests/listfiles_2/test_2")
    local folders = listfiles(".tests/listfiles_2")
    assert(#folders == 2, "Did not return the correct number of folders")
    assert(isfolder(folders[1]), "Did not return a folder path")
end)

runTest("writefile", {}, function()
    writefile(".tests/writefile.txt", "success")
    assert(readfile(".tests/writefile.txt") == "success", "Did not write the file")
    local requiresFileExt = pcall(function()
        writefile(".tests/writefile", "success")
        assert(isfile(".tests/writefile.txt"))
    end)
    if not requiresFileExt then
        return "This executor requires a file extension in writefile"
    end
end)

runTest("makefolder", {}, function()
    makefolder(".tests/makefolder")
    assert(isfolder(".tests/makefolder"), "Did not create the folder")
end)

runTest("appendfile", {}, function()
    writefile(".tests/appendfile.txt", "su")
    appendfile(".tests/appendfile.txt", "cce")
    appendfile(".tests/appendfile.txt", "ss")
    assert(readfile(".tests/appendfile.txt") == "success", "Did not append the file")
end)

runTest("isfile", {}, function()
    writefile(".tests/isfile.txt", "success")
    assert(isfile(".tests/isfile.txt") == true, "Did not return true for a file")
    assert(isfile(".tests") == false, "Did not return false for a folder")
    assert(isfile(".tests/doesnotexist.exe") == false, "Did not return false for a nonexistent path (got " .. tostring(isfile(".tests/doesnotexist.exe")) .. ")")
end)

runTest("isfolder", {}, function()
    assert(isfolder(".tests") == true, "Did not return false for a folder")
    assert(isfolder(".tests/doesnotexist.exe") == false, "Did not return false for a nonexistent path (got " .. tostring(isfolder(".tests/doesnotexist.exe")) .. ")")
end)

runTest("delfolder", {}, function()
    makefolder(".tests/delfolder")
    delfolder(".tests/delfolder")
    assert(isfolder(".tests/delfolder") == false, "Failed to delete folder (isfolder = " .. tostring(isfolder(".tests/delfolder")) .. ")")
end)

runTest("delfile", {}, function()
    writefile(".tests/delfile.txt", "Hello, world!")
    delfile(".tests/delfile.txt")
    assert(isfile(".tests/delfile.txt") == false, "Failed to delete file (isfile = " .. tostring(isfile(".tests/delfile.txt")) .. ")")
end)

-- Input Tests
runTest("isrbxactive", {"isgameactive"}, function()
    assert(type(isrbxactive()) == "boolean", "Did not return a boolean value")
end)

-- Instances Tests
runTest("fireclickdetector", {}, function()
    local detector = Instance.new("ClickDetector")
    fireclickdetector(detector, 50, "MouseHoverEnter")
end)

runTest("getcallbackvalue", {}, function()
    local bindable = Instance.new("BindableFunction")
    local function test()
    end
    bindable.OnInvoke = test
    assert(getcallbackvalue(bindable, "OnInvoke") == test, "Did not return the correct value")
end)

runTest("getconnections", {}, function()
    local types = {
        Enabled = "boolean",
        ForeignState = "boolean",
        LuaConnection = "boolean",
        Function = "function",
        Thread = "thread",
        Fire = "function",
        Defer = "function",
        Disconnect = "function",
        Disable = "function",
        Enable = "function",
    }
    local bindable = Instance.new("BindableEvent")
    bindable.Event:Connect(function() end)
    local connection = getconnections(bindable.Event)[1]
    for key, valueType in pairs(types) do
        assert(connection[key] ~= nil, "Did not return a table with a '" .. key .. "' field")
        assert(type(connection[key]) == valueType, "Did not return a table with " .. key .. " as a " .. valueType .. " (got " .. type(connection[key]) .. ")")
    end
end)

runTest("getcustomasset", {}, function()
    writefile(".tests/getcustomasset.txt", "success")
    local contentId = getcustomasset(".tests/getcustomasset.txt")
    assert(type(contentId) == "string", "Did not return a string")
    assert(#contentId > 0, "Returned an empty string")
    assert(string.match(contentId, "rbxasset://") == "rbxasset://", "Did not return an rbxasset url")
end)

runTest("gethiddenproperty", {}, function()
    local fire = Instance.new("Fire")
    local property, isHidden = gethiddenproperty(fire, "size_xml")
    assert(property == 5, "Did not return the correct value")
    assert(isHidden == true, "Did not return whether the property was hidden")
end)

runTest("sethiddenproperty", {}, function()
    local fire = Instance.new("Fire")
    local hidden = sethiddenproperty(fire, "size_xml", 10)
    assert(hidden, "Did not return true for the hidden property")
    assert(gethiddenproperty(fire, "size_xml") == 10, "Did not set the hidden property")
end)

runTest("gethui", {}, function()
    assert(typeof(gethui()) == "Instance", "Did not return an Instance")
end)

runTest("getinstances", {}, function()
    assert(getinstances()[1]:IsA("Instance"), "The first value is not an Instance")
end)

runTest("getnilinstances", {}, function()
    assert(getnilinstances()[1]:IsA("Instance"), "The first value is not an Instance")
    assert(getnilinstances()[1].Parent == nil, "The first value is not parented to nil")
end)

runTest("isscriptable", {}, function()
    local fire = Instance.new("Fire")
    assert(isscriptable(fire, "size_xml") == false, "Did not return false for a non-scriptable property (size_xml)")
    assert(isscriptable(fire, "Size") == true, "Did not return true for a scriptable property (Size)")
end)

runTest("setscriptable", {}, function()
    local fire = Instance.new("Fire")
    local wasScriptable = setscriptable(fire, "size_xml", true)
    assert(wasScriptable == false, "Did not return false for a non-scriptable property (size_xml)")
    assert(isscriptable(fire, "size_xml") == true, "Did not set the scriptable property")
    fire = Instance.new("Fire")
    assert(isscriptable(fire, "size_xml") == false, "⚠️⚠️ setscriptable persists between unique instances ⚠️⚠️")
end)

-- Metatable Tests
runTest("getrawmetatable", {}, function()
    local metatable = { __metatable = "Locked!" }
    local object = setmetatable({}, metatable)
    assert(getrawmetatable(object) == metatable, "Did not return the metatable")
end)

runTest("hookmetamethod", {}, function()
    local object = setmetatable({}, { __index = newcclosure(function() return false end), __metatable = "Locked!" })
    local ref = hookmetamethod(object, "__index", function() return true end)
    assert(object.test == true, "Failed to hook a metamethod and change the return value")
    assert(ref() == false, "Did not return the original function")
end)

runTest("getnamecallmethod", {}, function()
    local method
    local ref
    ref = hookmetamethod(game, "__namecall", function(...)
        if not method then
            method = getnamecallmethod()
        end
        return ref(...)
    end)
    game:GetService("Lighting")
    assert(method == "GetService", "Did not get the correct method (GetService)")
end)

runTest("isreadonly", {}, function()
    local object = {}
    table.freeze(object)
    assert(isreadonly(object), "Did not return true for a read-only table")
end)

runTest("setrawmetatable", {}, function()
    local object = setmetatable({}, { __index = function() return false end, __metatable = "Locked!" })
    local objectReturned = setrawmetatable(object, { __index = function() return true end })
    assert(object, "Did not return the original object")
    assert(object.test == true, "Failed to change the metatable")
    if objectReturned then
        return objectReturned == object and "Returned the original object" or "Did not return the original object"
    end
end)

runTest("setreadonly", {}, function()
    local object = { success = false }
    table.freeze(object)
    setreadonly(object, false)
    object.success = true
    assert(object.success, "Did not allow the table to be modified")
end)

-- Miscellaneous Tests
runTest("identifyexecutor", {"getexecutorname"}, function()
    local name, version = identifyexecutor()
    assert(type(name) == "string", "Did not return a string for the name")
    return type(version) == "string" and "Returns version as a string" or "Does not return version"
end)

runTest("lz4compress", {}, function()
    local raw = "Hello, world!"
    local compressed = lz4compress(raw)
    assert(type(compressed) == "string", "Compression did not return a string")
    assert(lz4decompress(compressed, #raw) == raw, "Decompression did not return the original string")
end)

runTest("lz4decompress", {}, function()
    local raw = "Hello, world!"
    local compressed = lz4compress(raw)
    assert(type(compressed) == "string", "Compression did not return a string")
    assert(lz4decompress(compressed, #raw) == raw, "Decompression did not return the original string")
end)

runTest("request", {"http.request", "http_request"}, function()
    local response = request({
        Url = "https://httpbin.org/user-agent",
        Method = "GET",
    })
    assert(type(response) == "table", "Response must be a table")
    assert(response.StatusCode == 200, "Did not return a 200 status code")
    local data = game:GetService("HttpService"):JSONDecode(response.Body)
    assert(type(data) == "table" and type(data["user-agent"]) == "string", "Did not return a table with a user-agent key")
    return "User-Agent: " .. data["user-agent"]
end)

runTest("setfpscap", {}, function()
    local renderStepped = game:GetService("RunService").RenderStepped
    local function step()
        renderStepped:Wait()
        local sum = 0
        for _ = 1, 5 do
            sum = sum + 1 / renderStepped:Wait()
        end
        return math.round(sum / 5)
    end
    setfpscap(60)
    local step60 = step()
    setfpscap(0)
    local step0 = step()
    return step60 .. "fps @60 • " .. step0 .. "fps @0"
end)

-- Scripts Tests
runTest("getgc", {}, function()
    local gc = getgc()
    assert(type(gc) == "table", "Did not return a table")
    assert(#gc > 0, "Did not return a table with any values")
end)

runTest("getgenv", {}, function()
    getgenv().__TEST_GLOBAL = true
    assert(__TEST_GLOBAL, "Failed to set a global variable")
    getgenv().__TEST_GLOBAL = nil
end)

runTest("getloadedmodules", {}, function()
    local modules = getloadedmodules()
    assert(type(modules) == "table", "Did not return a table")
    assert(#modules > 0, "Did not return a table with any values")
    assert(typeof(modules[1]) == "Instance", "First value is not an Instance")
    assert(modules[1]:IsA("ModuleScript"), "First value is not a ModuleScript")
end)

runTest("getrenv", {}, function()
    assert(_G ~= getrenv()._G, "The variable _G in the executor is identical to _G in the game")
end)

runTest("getrunningscripts", {}, function()
    local scripts = getrunningscripts()
    assert(type(scripts) == "table", "Did not return a table")
    assert(#scripts > 0, "Did not return a table with any values")
    assert(typeof(scripts[1]) == "Instance", "First value is not an Instance")
    assert(scripts[1]:IsA("ModuleScript") or scripts[1]:IsA("LocalScript"), "First value is not a ModuleScript or LocalScript")
end)

runTest("getscriptbytecode", {"dumpstring"}, function()
    local animate = game:GetService("Players").LocalPlayer.Character.Animate
    local bytecode = getscriptbytecode(animate)
    assert(type(bytecode) == "string", "Did not return a string for Character.Animate (a " .. animate.ClassName .. ")")
end)

runTest("getscripthash", {}, function()
    local animate = game:GetService("Players").LocalPlayer.Character.Animate:Clone()
    local hash = getscripthash(animate)
    local source = animate.Source
    animate.Source = "print('Hello, world!')"
    task.defer(function()
        animate.Source = source
    end)
    local newHash = getscripthash(animate)
    assert(hash ~= newHash, "Did not return a different hash for a modified script")
    assert(newHash == getscripthash(animate), "Did not return the same hash for a script with the same source")
end)

runTest("getscripts", {}, function()
    local scripts = getscripts()
    assert(type(scripts) == "table", "Did not return a table")
    assert(#scripts > 0, "Did not return a table with any values")
    assert(typeof(scripts[1]) == "Instance", "First value is not an Instance")
    assert(scripts[1]:IsA("ModuleScript") or scripts[1]:IsA("LocalScript"), "First value is not a ModuleScript or LocalScript")
end)

runTest("getsenv", {}, function()
    local animate = game:GetService("Players").LocalPlayer.Character.Animate
    local env = getsenv(animate)
    assert(type(env) == "table", "Did not return a table for Character.Animate (a " .. animate.ClassName .. ")")
    assert(env.script == animate, "The script global is not identical to Character.Animate")
end)

runTest("getthreadidentity", {"getidentity", "getthreadcontext"}, function()
    assert(type(getthreadidentity()) == "number", "Did not return a number")
end)

runTest("setthreadidentity", {"setidentity", "setthreadcontext"}, function()
    setthreadidentity(3)
    assert(getthreadidentity() == 3, "Did not set the thread identity")
end)

-- Drawing Tests
runTest("Drawing.new", {}, function()
    local drawing = Drawing.new("Square")
    drawing.Visible = false
    local canDestroy = pcall(function()
        drawing:Destroy()
    end)
    assert(canDestroy, "Drawing:Destroy() should not throw an error")
end)

runTest("Drawing.Fonts", {}, function()
    assert(Drawing.Fonts.UI == 0, "Did not return the correct id for UI")
    assert(Drawing.Fonts.System == 1, "Did not return the correct id for System")
    assert(Drawing.Fonts.Plex == 2, "Did not return the correct id for Plex")
    assert(Drawing.Fonts.Monospace == 3, "Did not return the correct id for Monospace")
end)

runTest("isrenderobj", {}, function()
    local drawing = Drawing.new("Image")
    drawing.Visible = true
    assert(isrenderobj(drawing) == true, "Did not return true for an Image")
    assert(isrenderobj(newproxy()) == false, "Did not return false for a blank table")
end)

runTest("getrenderproperty", {}, function()
    local drawing = Drawing.new("Image")
    drawing.Visible = true
    assert(type(getrenderproperty(drawing, "Visible")) == "boolean", "Did not return a boolean value for Image.Visible")
    local success, result = pcall(function()
        return getrenderproperty(drawing, "Color")
    end)
    if not success or not result then
        return "Image.Color is not supported"
    end
end)

runTest("setrenderproperty", {}, function()
    local drawing = Drawing.new("Square")
    drawing.Visible = true
    setrenderproperty(drawing, "Visible", false)
    assert(drawing.Visible == false, "Did not set the value for Square.Visible")
end)

runTest("cleardrawcache", {}, function()
    cleardrawcache()
end)

-- WebSocket Tests
runTest("WebSocket.connect", {}, function()
    local types = {
        Send = "function",
        Close = "function",
        OnMessage = {"table", "userdata"},
        OnClose = {"table", "userdata"},
    }
    local ws = WebSocket.connect("ws://echo.websocket.events")
    assert(type(ws) == "table" or type(ws) == "userdata", "Did not return a table or userdata")
    for key, valueType in pairs(types) do
        if type(valueType) == "table" then
            assert(table.find(valueType, type(ws[key])), "Did not return a " .. table.concat(valueType, ", ") .. " for " .. key .. " (a " .. type(ws[key]) .. ")")
        else
            assert(type(ws[key]) == valueType, "Did not return a " .. valueType .. " for " .. key .. " (a " .. type(ws[key]) .. ")")
        end
    end
    ws:Close()
end)

printSummary()
