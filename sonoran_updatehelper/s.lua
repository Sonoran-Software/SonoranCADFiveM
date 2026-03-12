ManagedResources = { "wk_wars2x", "tablet", "sonorancad"}

CreateThread(function()
    local helperSignalKey = "sonoran_updatehelper_action"
    local action = GetConvar(helperSignalKey, "")
    local res = GetCurrentResourceName()
    local runLock = LoadResourceFile(res, "run.lock")
    local hasCoreRunLock = runLock and runLock:match("^core")
    local hasPluginRunLock = runLock and runLock:match("^plugin")

    -- Check both convar and run.lock for backward compatibility.
    -- Older updater versions signal only with run.lock.
    if action == "core" or action == "plugin" or hasCoreRunLock or hasPluginRunLock then
        SetConvar(helperSignalKey, "")
        os.remove(GetResourcePath(res).."/run.lock")

        local restartAction = action
        if restartAction ~= "core" and restartAction ~= "plugin" then
            if hasCoreRunLock then
                restartAction = "core"
            elseif hasPluginRunLock then
                restartAction = "plugin"
            end
        end

        ExecuteCommand("refresh")
        Wait(1000)
        if restartAction == "core" then
            for k, v in pairs(ManagedResources) do
                if GetResourceState(v) ~= "started" then
                    print(("Not restarting resource %s as it is not started. This may be fine. State: %s"):format(v, GetResourceState(v)))
                else
                    ExecuteCommand("restart "..v)
                    Wait(1000)
                end
            end
        elseif restartAction == "plugin" then
            print("Restarting sonorancad resource for plugin updates...")
            if GetResourceState("sonorancad") ~= "started" then
                print(("Not restarting resource %s as it is not in the started state to avoid server crashing. State: %s"):format("sonorancad", GetResourceState("sonorancad")))
                print("If you are seeing this message, you have started sonoran_updatehelper in your configuration which is incorrect. Please do not start sonoran_updatehelper manually.")
                return
            else
                ExecuteCommand("restart sonorancad")
            end
        end
    else
        os.remove(GetResourcePath(GetCurrentResourceName()).."/run.lock")
        print("sonoran_updatehelper is for internal use and should not be started as a resource.")
    end
    os.remove(GetResourcePath(GetCurrentResourceName()).."/run.lock")
end)
