-- ============================================================================
-- OBS Telegram Stream Alerts
-- Version: 1.0.0
-- Description: Send Telegram notifications when OBS streaming starts/stops
-- ============================================================================

obs = obslua

VERSION = "1.0.0"
TELEGRAM_API_BASE = "https://api.telegram.org/bot"

local TG_CONFIG_STATUS = {
    NOT_CONFIGURED = "⚪ Not Configured",
    NOT_VALIDATED = "⚪ Not Validated"
}

local TG_BOT_STATUS = {
    CONNECTED = "✅ Bot Connected: @",
    INVALID_TOKEN = "❌ Invalid Bot Token",
    INVALID_RESPONSE = "❌ Invalid Response",
    NETWORK_ERROR = "❌ Network Error"
}

local TG_CHAT_STATUS = {
    FOUND = " | ✅ Chat: ",
    DM = " | ✅ Chat: Direct Message",
    NOT_FOUND = " | ❌ Chat Not Found",
    ERROR = " | ❌ Chat Error"
}

local tg_config = {
    bot_token = "",
    chat_id = "",
    status = TG_CONFIG_STATUS.NOT_CONFIGURED,
    start_msg_id = nil
}

local config = {
    enable_start = true,
    enable_stop = true,
    start_template = "🔴 Stream Started!",
    stop_template = "⚫ Stream Ended",
    enable_delete_start_msg = false,
    debug_mode = false
}

local twitch_config = {
    client_id = "",
    client_secret = "",
    channel_name = "",
    oauth_token = nil,
    token_expires_at = nil,
    status = TG_CONFIG_STATUS.NOT_CONFIGURED
}

function detect_platform()
    return package.config:sub(1,1) == "\\" and "windows" or "unix"
end

function url_encode(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

function escape_shell_json(json_str)
    local platform = detect_platform()
    if platform == "windows" then
        return '"' .. json_str:gsub('"', '\\"') .. '"'
    else
        return "'" .. json_str:gsub("'", "'\\''") .. "'"
    end
end

function parse_curl_response(output)
    if not output or output == "" then
        return {status = 0, body = "", ok = false}
    end
    
    local lines = {}
    for line in output:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    
    local status_code = tonumber(lines[#lines]) or 0
    table.remove(lines, #lines)
    local body = table.concat(lines, "\n")
    
    local ok = status_code >= 200 and status_code < 300
    
    return {status = status_code, body = body, ok = ok}
end

function build_curl_command(url, method, data)
    local platform = detect_platform()
    local is_windows = platform == "windows"
    local q = is_windows and '"' or "'"
    local cmd_prefix = is_windows and "cmd /c " or ""
    local cmd = cmd_prefix .. "curl -s --max-time 30"
    if method == "POST" then
        cmd = cmd .. " -X POST -H " .. q .. "Content-Type: application/json" .. q .. " -d " .. data
    end
    cmd = cmd .. " -w " .. q .. "\\n%{http_code}" .. q .. " " .. q .. url .. q
    
    return cmd
end

function http_get(url)
    local cmd = build_curl_command(url, "GET", nil)
    local handle = io.popen(cmd)
    if not handle then
        obs.script_log(obs.LOG_ERROR, "HTTP GET failed: Unable to execute curl (check if curl is installed)")
        return {success = false, status = 0, body = ""}
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local response = parse_curl_response(output)
    if not response.ok and response.status == 0 then
        obs.script_log(obs.LOG_ERROR, "HTTP GET failed: Network timeout or DNS failure")
    end
    
    return {success = response.ok, status = response.status, body = response.body}
end

function http_post(url, body_table)
    local json_parts = {}
    for key, value in pairs(body_table) do
        table.insert(json_parts, '"' .. key .. '":"' .. tostring(value) .. '"')
    end
    local json_body = "{" .. table.concat(json_parts, ",") .. "}"
    local escaped_json = escape_shell_json(json_body)
    local cmd = build_curl_command(url, "POST", escaped_json)
    
    local handle = io.popen(cmd)
    if not handle then
        obs.script_log(obs.LOG_ERROR, "HTTP POST failed: Unable to execute curl (check if curl is installed)")
        return {success = false, status = 0, body = ""}
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local response = parse_curl_response(output)
    if not response.ok and response.status == 0 then
        obs.script_log(obs.LOG_ERROR, "HTTP POST failed: Network timeout or DNS failure")
    end
    
    return {success = response.ok, status = response.status, body = response.body}
end

function tg_validate_bot_token()
    if tg_config.bot_token == "" then
        tg_config.status = TG_CONFIG_STATUS.NOT_CONFIGURED
        return false
    end
    
    local url = TELEGRAM_API_BASE .. tg_config.bot_token .. "/getMe"
    local response = http_get(url)
    
    if response.status == 401 or response.status == 404 then
        tg_config.status = TG_BOT_STATUS.INVALID_TOKEN
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Invalid bot token")
        return false
    end
    
    if response.status == 429 then
        tg_config.status = "⚠️ Rate Limited"
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Rate limited - wait before retrying")
        return false
    end
    
    if response.status ~= 200 then
        tg_config.status = TG_BOT_STATUS.NETWORK_ERROR
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Network error (status " .. response.status .. ")")
        return false
    end
    
    local username = response.body:match('"username":"([^"]+)"')
    if not username then
        tg_config.status = TG_BOT_STATUS.INVALID_RESPONSE
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Unable to parse bot username")
        return false
    end
    
    tg_config.status = TG_BOT_STATUS.CONNECTED .. username
    return true
end

function tg_validate_chat_id()
    if tg_config.chat_id == "" then
        return false
    end
    
    local url = TELEGRAM_API_BASE .. tg_config.bot_token .. "/getChat?chat_id=" .. url_encode(tg_config.chat_id)
    local response = http_get(url)
    
    if response.status == 400 or response.status == 404 then
        tg_config.status = tg_config.status .. TG_CHAT_STATUS.NOT_FOUND
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Chat not found")
        return false
    end
    
    if response.status == 429 then
        tg_config.status = tg_config.status .. " | ⚠️ Rate Limited"
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Rate limited - wait before retrying")
        return false
    end
    
    if response.status ~= 200 then
        tg_config.status = tg_config.status .. TG_CHAT_STATUS.ERROR
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Network error (status " .. response.status .. ")")
        return false
    end
    
    local title = response.body:match('"title":"([^"]+)"')
    if title then
        tg_config.status = tg_config.status .. TG_CHAT_STATUS.FOUND .. title
    else
        tg_config.status = tg_config.status .. TG_CHAT_STATUS.DM
    end
    
    return true
end

function script_description()
    return [[<b>OBS Telegram Stream Alerts</b> v]] .. VERSION .. [[<br>
<br>
Send Telegram notifications when your stream starts and stops.<br>
<br>
<i>Configure your Telegram bot credentials and message templates below.</i>]]
end

function stream_start()
    obs.script_log(obs.LOG_ERROR, "Streaming started")
end

function stream_stop()
    obs.script_log(obs.LOG_ERROR, "Streaming stopped")
end

function test_stream_start(props, p)
    on_event(obs.OBS_FRONTEND_EVENT_STREAMING_STARTED)
    return true
end

function test_stream_stop(props, p)
    on_event(obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED)
    return true
end

function tg_validate_config_callback(props, prop)
    tg_validate_bot_token()
    if tg_config.bot_token ~= "" and tg_config.status:find(TG_BOT_STATUS.CONNECTED, 1, true) then
        tg_validate_chat_id()
    end
    
    local status_prop = obs.obs_properties_get(props, "tg_config_status")
    if status_prop then
        obs.obs_property_set_description(status_prop, tg_config.status)
    end
    
    return true
end

function script_properties()
    local props = obs.obs_properties_create()
    
    local tg_config_props = obs.obs_properties_create()
    obs.obs_properties_add_text(tg_config_props, "tg_bot_token", "Bot Token", obs.OBS_TEXT_PASSWORD)
    obs.obs_properties_add_text(tg_config_props, "tg_chat_id", "Chat ID", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_button(tg_config_props, "btn_tg_config_validate", "Validate", tg_validate_config_callback)
    local tg_config_status_prop = obs.obs_properties_add_text(tg_config_props, "tg_config_status", "Status", obs.OBS_TEXT_INFO)
    obs.obs_property_set_enabled(tg_config_status_prop, false)
    obs.obs_property_set_description(tg_config_status_prop, tg_config.status)
    obs.obs_properties_add_group(props, "tg_config_group", "Telegram", obs.OBS_GROUP_NORMAL, tg_config_props)
    
    local testing_props = obs.obs_properties_create()
    obs.obs_properties_add_button(testing_props, "btn_test_start", "Test Stream Start", test_stream_start)
    obs.obs_properties_add_button(testing_props, "btn_test_stop", "Test Stream Stop", test_stream_stop)
    obs.obs_properties_add_group(props, "testing_group", "Testing", obs.OBS_GROUP_NORMAL, testing_props)
    
    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_bool(settings, "enable_start", true)
    obs.obs_data_set_default_bool(settings, "enable_stop", true)
    obs.obs_data_set_default_string(settings, "start_template", "🔴 Stream Started!")
    obs.obs_data_set_default_string(settings, "stop_template", "⚫ Stream Ended")
    obs.obs_data_set_default_bool(settings, "enable_delete_start_msg", false)
    obs.obs_data_set_default_bool(settings, "debug_mode", false)
    obs.obs_data_set_default_string(settings, "tg_bot_token", "")
    obs.obs_data_set_default_string(settings, "tg_chat_id", "")
    obs.obs_data_set_default_string(settings, "twitch_client_id", "")
    obs.obs_data_set_default_string(settings, "twitch_client_secret", "")
    obs.obs_data_set_default_string(settings, "twitch_channel_name", "")
end

function on_event(event)
    if event == obs.OBS_FRONTEND_EVENT_STREAMING_STARTED then
        stream_start()
    elseif event == obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED then
        stream_stop()
    end
end

function script_update(settings)
    tg_config.bot_token = obs.obs_data_get_string(settings, "tg_bot_token")
    tg_config.chat_id = obs.obs_data_get_string(settings, "tg_chat_id")
    
    if tg_config.bot_token == "" and tg_config.chat_id == "" then
        tg_config.status = TG_CONFIG_STATUS.NOT_CONFIGURED
    elseif tg_config.bot_token ~= "" or tg_config.chat_id ~= "" then
        if not tg_config.status:find("✅") and not tg_config.status:find("❌") then
            tg_config.status = TG_CONFIG_STATUS.NOT_VALIDATED
        end
    end
end

function script_load(settings)
    obs.obs_frontend_add_event_callback(on_event)
end

function script_unload()
    obs.obs_frontend_remove_event_callback(on_event)
end
