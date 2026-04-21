local CadLinkCache = {}
local CadLinkSessions = {}
local LinkCodeReuseWindowMs = 5 * 60 * 1000

local function is_non_empty_string(value)
    return type(value) == "string" and value ~= ""
end

local function trim_string(value)
    if type(value) ~= "string" then
        return nil
    end
    local trimmed = value:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end
    return trimmed
end

local function looks_like_uuid(value)
    return is_non_empty_string(value) and value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

local function get_link_command_name()
    if type(Config.linkCommand) == "string" and Config.linkCommand ~= "" then
        return Config.linkCommand
    end
    return "link"
end

local function get_link_poll_interval_ms()
    local interval = tonumber(Config.linkPollIntervalMs) or 10000
    if interval < 1000 then
        interval = 1000
    end
    return math.floor(interval)
end

local function get_link_popup_title_text()
    if type(Config.linkPopupTitleText) == "string" and Config.linkPopupTitleText ~= "" then
        return Config.linkPopupTitleText
    end
    return "Press the button to link your CAD account to this FiveM server"
end

local function get_link_button_text()
    if type(Config.linkButtonText) == "string" and Config.linkButtonText ~= "" then
        return Config.linkButtonText
    end
    return "Link CAD"
end

local function should_allow_popup_close_when_unlinked()
    if Config.freezeUntilLinked == true then
        return false
    end
    return Config.allowPopupCloseWhenUnlinked ~= false
end

local function get_cad_ui_base_url()
    if Config.mode == "development" then
        return "https://staging.dev.sonorancad.com"
    end
    return "https://sonorancad.com"
end

local function log_link_debug(message)
    debugLog(("[link] %s"):format(message))
end

local function get_player_link_identifier(player)
    local identifiers = GetIdentifiers(player)
    if Config.primaryIdentifier ~= nil and identifiers[Config.primaryIdentifier] ~= nil then
        return identifiers[Config.primaryIdentifier], tostring(Config.primaryIdentifier)
    end
    if identifiers.license ~= nil then
        return identifiers.license, "license"
    end

    for id_type, identifier in pairs(identifiers) do
        if identifier ~= nil then
            return identifier, tostring(id_type)
        end
    end

    return nil, tostring(Config.primaryIdentifier or "license")
end

function GetPlayerLinkIdentifier(player)
    return get_player_link_identifier(player)
end

local function build_link_payload(identifier, identifier_type, code, community_user_id)
    local payload = {
        serverId = tonumber(Config.serverId) or tonumber(GetConvar("sonoran_serverId", "1")) or 1,
        communityIdentifier = identifier,
        identifier = identifier,
        linkIdentifier = identifier,
        identifierType = identifier_type,
        communityIdentifierType = identifier_type,
        platform = "fivem",
        source = "fivem"
    }

    if is_non_empty_string(code) then
        payload.code = code
        payload.linkCode = code
    end

    if is_non_empty_string(community_user_id) then
        payload.communityUserId = community_user_id
        payload.userId = community_user_id
        payload.ssoId = community_user_id
    end

    return payload
end

local function coerce_link_data(data)
    if type(data) == "table" and next(data) == nil then
        return {}
    end
    if type(data) ~= "table" then
        return {
            raw = data
        }
    end

    if type(data.data) == "table" then
        return data.data
    end
    if type(data.link) == "table" then
        return data.link
    end
    if type(data.result) == "table" then
        return data.result
    end

    return data
end

local function parse_link_response(data)
    local parsed = coerce_link_data(data)
    local code = parsed.code or parsed.linkCode or parsed.link_code or parsed.idCode
    local url = parsed.url or parsed.linkUrl or parsed.linkURL or parsed.link or parsed.redirectUrl
    local community_user_id = parsed.communityUserId or parsed.userId or parsed.accountId or parsed.id
    local linked = parsed.linked

    if linked == nil then
        if parsed.exists ~= nil then
            linked = parsed.exists == true
        elseif parsed.success ~= nil and community_user_id ~= nil then
            linked = parsed.success == true
        elseif community_user_id ~= nil then
            linked = true
        else
            linked = false
        end
    end

    if not is_non_empty_string(url) and is_non_empty_string(code) then
        url = ("%s/id?code=%s"):format(get_cad_ui_base_url(), code)
    end

    return {
        linked = linked == true,
        code = code,
        url = url,
        communityUserId = community_user_id,
        raw = parsed
    }
end

local function update_link_cache(identifier, identifier_type, parsed)
    local existing = CadLinkCache[identifier] or {}
    CadLinkCache[identifier] = {
        identifier = identifier,
        identifierType = identifier_type or existing.identifierType or tostring(Config.primaryIdentifier or "license"),
        linked = parsed.linked == true,
        code = parsed.code or existing.code,
        url = parsed.url or existing.url,
        communityUserId = parsed.communityUserId or existing.communityUserId,
        updatedAt = GetGameTimer(),
        raw = parsed.raw or existing.raw
    }
    return CadLinkCache[identifier]
end

local function refresh_link_status_by_identifier(identifier, identifier_type, code)
    if not is_non_empty_string(identifier) then
        return {
            linked = false
        }
    end

    local cached = CadLinkCache[identifier]
    if code == nil and cached ~= nil then
        code = cached.code
    end

    local response = CadApiCheckCommunityLink(build_link_payload(identifier, identifier_type, code))
    if not response.success then
        warnLog(("CAD link status check failed for %s (%s): %s"):format(
            tostring(identifier),
            tostring(identifier_type),
            tostring(response.reason)
        ))
        return update_link_cache(identifier, identifier_type, {
            linked = false,
            code = code,
            url = cached and cached.url or nil,
            communityUserId = cached and cached.communityUserId or nil,
            raw = response.reason
        })
    end

    return update_link_cache(identifier, identifier_type, parse_link_response(response.data))
end

local function create_link_session_by_identifier(identifier, identifier_type, community_user_id)
    if not is_non_empty_string(identifier) then
        return nil, "Missing player identifier."
    end

    log_link_debug(("request link code for %s (%s)"):format(tostring(identifier), tostring(identifier_type)))
    local response = CadApiCreateCommunityLink(build_link_payload(identifier, identifier_type, nil, community_user_id))
    if not response.success then
        warnLog(("CAD link creation failed for %s (%s): %s"):format(
            tostring(identifier),
            tostring(identifier_type),
            tostring(response.reason)
        ))
        return nil, response.reason
    end

    local parsed = parse_link_response(response.data)
    local cached = update_link_cache(identifier, identifier_type, parsed)
    if not cached.linked and is_non_empty_string(cached.code) then
        cached = refresh_link_status_by_identifier(identifier, identifier_type, cached.code)
    end

    return cached
end

local function build_player_session(identifier, identifier_type, status, existing_session)
    local session = existing_session or {}
    session.identifier = identifier
    session.identifierType = identifier_type
    session.linkCode = status.code or session.linkCode
    session.linkUrl = status.url or session.linkUrl
    session.popupOpen = session.popupOpen == true
    session.lastCheckAt = session.lastCheckAt or 0
    session.linked = status.linked == true
    session.communityUserId = status.communityUserId or session.communityUserId
    session.updatedAt = GetGameTimer()
    session.createdAt = session.createdAt or session.updatedAt
    return session
end

local function should_reuse_link_session(session, identifier)
    if type(session) ~= "table" then
        return false
    end
    if session.identifier ~= identifier or session.linked == true then
        return false
    end
    if not is_non_empty_string(session.linkCode) or not is_non_empty_string(session.linkUrl) then
        return false
    end
    if type(session.createdAt) ~= "number" then
        return false
    end
    return (GetGameTimer() - session.createdAt) < LinkCodeReuseWindowMs
end

local function get_or_create_player_session(player, force_refresh)
    local identifier, identifier_type = get_player_link_identifier(player)
    if not is_non_empty_string(identifier) then
        return nil, "Missing player identifier."
    end

    local existing = CadLinkSessions[player]
    if type(existing) == "table" and existing.identifier == identifier and existing.linked == true and is_non_empty_string(existing.communityUserId) then
        existing.popupOpen = true
        return existing
    end

    if not force_refresh and should_reuse_link_session(existing, identifier) then
        existing.popupOpen = true
        log_link_debug(("reuse link code for player %s"):format(tostring(player)))
        return existing
    end

    local status, err = create_link_session_by_identifier(identifier, identifier_type)
    if status == nil then
        return nil, err
    end

    local session = build_player_session(identifier, identifier_type, status, existing)
    session.popupOpen = true
    CadLinkSessions[player] = session
    return session
end

local function set_session_popup_state(player, popup_open)
    local session = CadLinkSessions[player]
    if type(session) ~= "table" then
        return
    end
    session.popupOpen = popup_open == true
end

local function sanitize_sso_id(value)
    local sanitized = trim_string(value)
    if sanitized == nil then
        return nil, "Missing SSO ID."
    end
    if #sanitized > 128 then
        return nil, "SSO ID is too long."
    end
    if sanitized:match("^[%w%-%._:@/]+$") == nil then
        return nil, "SSO ID format is invalid."
    end
    return sanitized
end

local function get_session_status_text(linked)
    if linked == true then
        return "Linked successfully."
    end
    return "Waiting for account link..."
end

local function build_link_client_payload(session)
    local status = session or {}
    local linked = status.linked == true
    return {
        linked = linked,
        code = status.linkCode,
        url = status.linkUrl,
        communityUserId = status.communityUserId,
        statusText = get_session_status_text(linked),
        pollIntervalMs = get_link_poll_interval_ms(),
        titleText = get_link_popup_title_text(),
        buttonText = get_link_button_text(),
        linkCommand = get_link_command_name(),
        allowClose = linked or should_allow_popup_close_when_unlinked()
    }
end

-- Read-only export for third-party resources that need the configured CAD community ID.
function GetCommunityId()
    if not is_non_empty_string(Config.communityID) then
        warnLog("getCommunityId export returned nil because Config.communityID is not configured.")
        return nil
    end
    return Config.communityID
end

-- Read-only export for third-party resources that need the configured CAD server ID.
function GetServerId()
    local server_id = tonumber(Config.serverId) or tonumber(GetConvar("sonoran_serverId", ""))
    if server_id == nil then
        warnLog("getServerId export returned nil because Config.serverId is not configured.")
        return nil
    end
    return server_id
end

function GetCadCommunityId()
    return GetCommunityId()
end

function GetCadServerId()
    return GetServerId()
end

function GetCommunityUserIdFromIdentifier(identifier, identifier_type)
    if not is_non_empty_string(identifier) then
        return nil
    end
    if looks_like_uuid(identifier) then
        return identifier
    end

    local cached = CadLinkCache[identifier]
    if cached ~= nil and cached.linked and is_non_empty_string(cached.communityUserId) then
        return cached.communityUserId
    end

    local refreshed = refresh_link_status_by_identifier(identifier, identifier_type)
    if refreshed.linked and is_non_empty_string(refreshed.communityUserId) then
        return refreshed.communityUserId
    end

    return nil
end

function GetPlayerCommunityUserId(player)
    local identifier, identifier_type = get_player_link_identifier(player)
    if not identifier then
        return nil
    end
    return GetCommunityUserIdFromIdentifier(identifier, identifier_type)
end

function IsIdentifierLinkedToCad(identifier, identifier_type)
    return GetCommunityUserIdFromIdentifier(identifier, identifier_type) ~= nil
end

function IsPlayerLinkedToCad(player)
    return GetPlayerCommunityUserId(player) ~= nil
end

exports("getCommunityId", GetCommunityId)
exports("getServerId", GetServerId)
exports("getCadCommunityId", GetCadCommunityId)
exports("getCadServerId", GetCadServerId)
exports("getPlayerCommunityUserId", GetPlayerCommunityUserId)

local function send_tablet_link_status(player, linked)
    if linked then
        TriggerClientEvent("SonoranCAD::Tablet::LinkFound", player)
    else
        TriggerClientEvent("SonoranCAD::Tablet::LinkMissing", player)
    end
end

local function send_link_status_to_client(player, session)
    TriggerClientEvent("SonoranCAD::links:Status", player, build_link_client_payload(session))
end

-- Associates a CAD SSO/community user identifier with the player's FiveM identifier.
local function associate_sso_with_player(player, sso_id)
    local identifier, identifier_type = get_player_link_identifier(player)
    if not is_non_empty_string(identifier) then
        return nil, "Missing player link identifier."
    end

    local sanitized_sso_id, sanitize_err = sanitize_sso_id(sso_id)
    if sanitized_sso_id == nil then
        return nil, sanitize_err
    end

    log_link_debug(("associate SSO for player %s using %s"):format(tostring(player), tostring(identifier_type)))
    local link_status, err = create_link_session_by_identifier(identifier, identifier_type, sanitized_sso_id)
    if link_status == nil then
        warnLog(("Failed SSO association for player %s: %s"):format(tostring(player), tostring(err)))
        return nil, type(err) == "string" and err or "Failed to associate the SSO account."
    end

    local session = build_player_session(identifier, identifier_type, link_status, CadLinkSessions[player])
    session.popupOpen = false
    CadLinkSessions[player] = session

    if session.linked then
        infoLog(("Player %s linked CAD account via tablet/SSO flow."):format(tostring(player)))
    end

    return session
end

local function check_tablet_link_status(player)
    send_tablet_link_status(player, IsPlayerLinkedToCad(player))
end

local function associate_tablet_sso_data(player, session, username)
    local sso_id = session
    if not is_non_empty_string(sso_id) then
        sso_id = username
    end

    local link_session, err = associate_sso_with_player(player, sso_id)
    if link_session == nil then
        TriggerClientEvent("sonoran:tablet:failed", player, type(err) == "string" and err or "Failed to associate the SSO account.")
        return
    end

    send_tablet_link_status(player, link_session.linked == true)
end

RegisterNetEvent("SonoranCAD::links:Open")
AddEventHandler("SonoranCAD::links:Open", function()
    local player = source
    log_link_debug(("open command used by player %s"):format(tostring(player)))

    local session, err = get_or_create_player_session(player, false)
    if session == nil then
        TriggerClientEvent("SonoranCAD::links:OpenResult", player, {
            ok = false,
            message = type(err) == "string" and err or "Failed to create a CAD link session."
        })
        return
    end

    TriggerClientEvent("SonoranCAD::links:OpenResult", player, {
        ok = true,
        code = session.linkCode,
        url = session.linkUrl,
        linked = session.linked == true,
        statusText = get_session_status_text(session.linked),
        pollIntervalMs = get_link_poll_interval_ms(),
        titleText = get_link_popup_title_text(),
        buttonText = get_link_button_text(),
        linkCommand = get_link_command_name(),
        allowClose = session.linked == true or should_allow_popup_close_when_unlinked()
    })
    send_link_status_to_client(player, session)
end)

RegisterNetEvent("SonoranCAD::links:PopupClosed")
AddEventHandler("SonoranCAD::links:PopupClosed", function()
    local player = source
    set_session_popup_state(player, false)
    log_link_debug(("popup closed for player %s"):format(tostring(player)))
end)

RegisterNetEvent("SonoranCAD::links:Poll")
AddEventHandler("SonoranCAD::links:Poll", function()
    local player = source
    local session = CadLinkSessions[player]
    local identifier, identifier_type = get_player_link_identifier(player)

    if session == nil then
        session = {
            identifier = identifier,
            identifierType = identifier_type,
            popupOpen = true
        }
        CadLinkSessions[player] = session
    else
        identifier = session.identifier or identifier
        identifier_type = session.identifierType or identifier_type
    end

    local interval = get_link_poll_interval_ms()
    local now = GetGameTimer()
    if type(session.lastCheckAt) == "number" and session.lastCheckAt > 0 and (now - session.lastCheckAt) < (interval - 250) then
        return
    end

    session.lastCheckAt = now
    session.popupOpen = true
    log_link_debug(("poll link status for player %s"):format(tostring(player)))

    local status = refresh_link_status_by_identifier(identifier, identifier_type, session.linkCode)
    local updated_session = build_player_session(identifier, identifier_type, status, session)
    updated_session.popupOpen = status.linked ~= true
    updated_session.lastCheckAt = now
    CadLinkSessions[player] = updated_session

    if updated_session.linked == true then
        infoLog(("Player %s linked CAD account successfully."):format(tostring(player)))
    end

    send_link_status_to_client(player, updated_session)
end)

RegisterNetEvent("SonoranCAD::links:AssociateSso")
AddEventHandler("SonoranCAD::links:AssociateSso", function(sso_id)
    local player = source
    local session, err = associate_sso_with_player(player, sso_id)
    if session == nil then
        TriggerClientEvent("SonoranCAD::links:SsoResult", player, {
            ok = false,
            message = type(err) == "string" and err or "Failed to associate the SSO account."
        })
        return
    end

    TriggerClientEvent("SonoranCAD::links:SsoResult", player, {
        ok = session.linked == true,
        communityUserId = session.communityUserId,
        url = session.linkUrl,
        code = session.linkCode
    })
end)

RegisterNetEvent("SonoranCAD::Tablet::AssociateSso")
AddEventHandler("SonoranCAD::Tablet::AssociateSso", function(sso_id)
    local player = source
    local session, err = associate_sso_with_player(player, sso_id)
    if session == nil then
        TriggerClientEvent("sonoran:tablet:failed", player, err)
        TriggerClientEvent("SonoranCAD::links:SsoResult", player, {
            ok = false,
            message = err
        })
        return
    end

    send_tablet_link_status(player, session.linked == true)

    TriggerClientEvent("SonoranCAD::links:SsoResult", player, {
        ok = session.linked == true,
        communityUserId = session.communityUserId,
        url = session.linkUrl,
        code = session.linkCode
    })
end)

RegisterNetEvent("SonoranCAD::Tablet::CheckLinkStatus")
AddEventHandler("SonoranCAD::Tablet::CheckLinkStatus", function()
    check_tablet_link_status(source)
end)

RegisterNetEvent("SonoranCAD::Tablet::AssociateSsoData")
AddEventHandler("SonoranCAD::Tablet::AssociateSsoData", function(session, username)
    log_link_debug(("tablet iframe submitted SSO data for player %s"):format(tostring(source)))
    associate_tablet_sso_data(source, session, username)
end)

AddEventHandler("playerDropped", function()
    log_link_debug(("clear link state for player %s"):format(tostring(source)))
    CadLinkSessions[source] = nil
end)
