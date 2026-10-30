-- Run from the repository root: lua tablet/tests/mini-cad.test.lua
local function harness(command)
    local s = { commands = {}, events = {}, nui = {}, keymaps = {}, messages = {},
        requests = {}, chat = {}, kvp = {}, suggestions = {}, focusChanges = 0, displayCloses = 0,
        time = 100 }
    local noop = function() end
    local env = setmetatable({
        Citizen = { CreateThread = noop }, CreateThread = noop,
        GetConvar = function(name, default)
            return name == 'sonorantablet_command' and command or default
        end,
        GetGameTimer = function() return s.time end,
        exports = noop, RegisterNetEvent = noop,
        AddEventHandler = function(name, callback) s.events[name] = callback end,
        RegisterCommand = function(name, callback) s.commands[name] = callback end,
        RegisterKeyMapping = function(name, label, device, key)
            s.keymaps[name] = { label = label, device = device, key = key }
        end,
        RegisterNUICallback = function(name, callback) s.nui[name] = callback end,
        TriggerServerEvent = function(name, ...) table.insert(s.requests, { name, ... }) end,
        TriggerEvent = function(name, ...)
            if name == 'chatMessage' then table.insert(s.chat, select(3, ...)) end
            if name == 'chat:addSuggestion' then table.insert(s.suggestions, { ... }) end
        end,
        SendNUIMessage = function(message) table.insert(s.messages, message) end,
        GetResourceKvpString = function(key) return s.kvp[key] end,
        SetResourceKvp = function(key, value) s.kvp[key] = value end,
        SetNuiFocus = function() s.focusChanges = s.focusChanges + 1 end,
        IsCadDisplayActive = function() return s.displayActive == true end,
        CloseCadDisplay = function() s.displayCloses = s.displayCloses + 1 end,
        print = noop
    }, { __index = _G })
    assert(loadfile('tablet/cl_main.lua', 't', env))()
    s.env = env
    function s:command(...)
        self.commands[command or 'tablet'](0, { ... }, '')
    end
    function s:key()
        self.commands['SonoranTablet::MiniOpen']()
    end
    function s:reply(authorized, requestId)
        if requestId == nil then requestId = self.requests[#self.requests][2] end
        self.events['SonoranCAD::mini:OpenMini:Return'](authorized, authorized and 42 or nil, requestId)
    end
    function s:callback(name, data)
        local response
        self.nui[name](data or {}, function(value) response = value end)
        assert(response and response.ok == true, name .. ' did not acknowledge its callback')
    end
    return s
end

local count = 0
local function test(name, callback)
    callback()
    count = count + 1
    print('PASS ' .. name)
end

test('explicit and bare mini open keep opening semantics and coalesce authorization', function()
    local s = harness()
    s:command('mini')
    s:command('mini', 'open')
    assert(#s.requests == 1 and s.requests[1][1] == 'SonoranCAD::mini:OpenMini')
    assert(not s.env.isMiniVisible)
    s:reply(true)
    assert(s.env.isMiniVisible and s.env.myident == 42)
    s:command('mini', 'open')
    assert(s.env.isMiniVisible and #s.requests == 1)
    assert(s.kvp.shownTutorial == 'yes')
    assert(s.chat[1]:find('/tablet mini close', 1, true))
end)

test('close is safe while hidden and only hides the Mini CAD', function()
    local s = harness()
    s.env.nuiFocused, s.env.usingTablet, s.displayActive = true, true, true
    s:command('mini', 'close')
    s:command('mini', 'close')
    assert(not s.env.isMiniVisible and #s.requests == 0)
    assert(s.env.nuiFocused and s.env.usingTablet and s.displayActive)
    assert(s.focusChanges == 0 and s.displayCloses == 0)
    for _, message in ipairs(s.messages) do
        assert(message.type == 'display' and message.module == 'hud' and message.enabled == false)
    end
end)

test('toggle command and existing optional keybind open and close without a cursor', function()
    local s = harness()
    local mapping = s.keymaps['SonoranTablet::MiniOpen']
    assert(mapping.label == 'Mini CAD' and mapping.device == 'keyboard' and mapping.key == '')
    s:command('mini', 'toggle')
    s:reply(true)
    assert(s.env.isMiniVisible)
    s:key()
    assert(not s.env.isMiniVisible and #s.requests == 1)
    s:key()
    assert(#s.requests == 2 and not s.env.isMiniVisible)
    s:reply(true)
    assert(s.env.isMiniVisible and s.focusChanges == 0)
end)

test('a delayed authorization cannot undo close', function()
    local s = harness()
    s:key()
    s:command('mini', 'close')
    s:reply(true)
    assert(not s.env.isMiniVisible and #s.chat == 0 and not s.kvp.shownTutorial)
    s:key()
    assert(#s.requests == 2)
    s:reply(true)
    assert(s.env.isMiniVisible)
end)

test('rapid toggles honor the latest intent using one pending authorization', function()
    local s = harness()
    s:key()
    s:key()
    s:key()
    assert(#s.requests == 1)
    s:reply(true)
    assert(s.env.isMiniVisible)
    s:key()
    assert(not s.env.isMiniVisible)
    -- A duplicate or unsolicited return must not reopen a closed Mini CAD.
    s:reply(true)
    assert(not s.env.isMiniVisible)
end)

test('an unanswered startup request can be retried after ten seconds', function()
    local s = harness()
    s:command('mini', 'open')
    s.time = s.time + 9999
    s:command('mini', 'open')
    assert(#s.requests == 1)
    s.time = s.time + 1
    s:command('mini', 'open')
    assert(#s.requests == 2)
    s:reply(true)
    assert(s.env.isMiniVisible)
end)

test('the keybind retries expired requests and late authorization still respects close', function()
    local s = harness()
    s:key()
    s.time = s.time + 10000
    s:key()
    assert(#s.requests == 2)
    s:key()
    s:reply(true)
    assert(not s.env.isMiniVisible)
    s:key()
    assert(#s.requests == 3)
    s:reply(true)
    assert(s.env.isMiniVisible)
end)

test('closing an expired pending request leaves the next open able to retry', function()
    local s = harness()
    s:key()
    s.time = s.time + 10000
    s:command('mini', 'close')
    s:command('mini', 'open')
    assert(#s.requests == 2)
    s:reply(true)
    assert(s.env.isMiniVisible)
end)

test('an expired request denial cannot consume the current authorization', function()
    local s = harness()
    s:key()
    local oldId = s.requests[1][2]
    s.time = s.time + 10000
    s:key()
    local currentId = s.requests[2][2]
    assert(currentId > oldId)
    s:reply(false, oldId)
    assert(not s.env.isMiniVisible and #s.chat == 0)
    s:reply(true, currentId)
    assert(s.env.isMiniVisible)
end)

test('an expired request allow cannot consume a retry or undo a close', function()
    local s = harness()
    s:key()
    local oldId = s.requests[1][2]
    s.time = s.time + 10000
    s:key()
    local currentId = s.requests[2][2]
    s:reply(true, oldId)
    assert(not s.env.isMiniVisible and #s.chat == 0)
    s:command('mini', 'close')
    s:reply(true, oldId)
    s:reply(true, currentId)
    assert(not s.env.isMiniVisible)
    s:key()
    s:reply(true)
    assert(s.env.isMiniVisible)
end)

test('an uncorrelated authorization is ignored while a matching reply still opens', function()
    local s = harness()
    s:key()
    s.events['SonoranCAD::mini:OpenMini:Return'](true, 42)
    assert(not s.env.isMiniVisible)
    s:reply(true)
    assert(s.env.isMiniVisible)
end)

test('denial preserves authorization and allows retry', function()
    local s = harness()
    s:key()
    s:reply(false)
    assert(not s.env.isMiniVisible and #s.chat == 1)
    assert(s.chat[1]:find('/link', 1, true))
    s:key()
    assert(#s.requests == 2)
    s:reply(true)
    assert(s.env.isMiniVisible)
end)

test('a canceled open does not report a late denial', function()
    local s = harness()
    s:command('mini', 'open')
    s:key()
    s:reply(false)
    assert(not s.env.isMiniVisible and #s.chat == 0)
end)

test('the header close synchronizes subsequent keybind toggles', function()
    local s = harness()
    s:command('mini', 'open')
    s:reply(true)
    s:callback('VisibleEvent', { module = 'hud', state = false })
    assert(not s.env.isMiniVisible)
    s:key()
    assert(#s.requests == 2)
    s:reply(true)
    assert(s.env.isMiniVisible)
    s:callback('VisibleEvent', { module = 'cad', state = false })
    assert(s.env.isMiniVisible)
end)

test('configured command help, suggestions and question-mark help include close and toggle', function()
    local s = harness('customtablet')
    s:command('help')
    assert(s.chat[2]:find('/customtablet mini open | close | toggle', 1, true))
    assert(s.suggestions[1][1] == '/customtablet')
    assert(s.suggestions[1][3][2].help:find('mini open|close|toggle', 1, true))
    s:callback('ShowHelp')
    assert(s.chat[3]:find('/customtablet mini close', 1, true))
    assert(s.chat[3]:find('/customtablet mini toggle', 1, true))
    assert(s.chat[3]:find('Mini CAD keybind again', 1, true))
end)

local function serverHarness()
    local s = { events = {}, responses = {}, syncs = 0, ident = { id = 42, data = {} }, linkedId = 'linked-user' }
    local noop = function() end
    local env = setmetatable({
        source = 7,
        CreateThread = function(callback) callback() end,
        Citizen = { CreateThread = noop },
        GetResourceState = function() return 'started' end,
        RegisterServerEvent = noop,
        RegisterNetEvent = function(name, callback) s.events[name] = callback end,
        AddEventHandler = function(name, callback) s.events[name] = callback end,
        exports = { sonorancad = {
            GetUnitByPlayerId = function() return s.ident end,
            getPlayerCommunityUserId = function() return s.linkedId end
        } },
        TriggerClientEvent = function(name, target, ...)
            if name == 'SonoranCAD::mini:OpenMini:Return' then
                table.insert(s.responses, { target = target, authorized = select(1, ...),
                    ident = select(2, ...), requestId = select(3, ...) })
            elseif name == 'SonoranCAD::mini:CallSync' then
                s.syncs = s.syncs + 1
            end
        end
    }, { __index = _G })
    assert(loadfile('tablet/sv_main.lua', 't', env))()
    function s:open(requestId)
        self.events['SonoranCAD::mini:OpenMini'](requestId)
        return self.responses[#self.responses]
    end
    return s
end

test('the actual server echoes request IDs on allow and both authorization denial paths', function()
    local s = serverHarness()
    local response = s:open(17)
    assert(response.target == 7 and response.authorized and response.ident == 42 and response.requestId == 17)
    assert(s.syncs == 1)
    s.ident = nil
    response = s:open(18)
    assert(not response.authorized and response.ident == nil and response.requestId == 18)
    s.ident, s.linkedId = { id = 42, data = {} }, nil
    response = s:open(19)
    assert(not response.authorized and response.ident == nil and response.requestId == 19)
    assert(s.syncs == 1)
end)

test('the server retains legacy opening and does not echo malformed optional IDs', function()
    local s = serverHarness()
    local response = s:open()
    assert(response.authorized and response.requestId == nil)
    for _, requestId in ipairs({ 0, -1, 1.5, 'token', {}, math.huge }) do
        response = s:open(requestId)
        assert(response.authorized and response.requestId == nil)
    end
end)

print(('Passed %d Mini CAD tests.'):format(count))
