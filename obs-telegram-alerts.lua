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

local EMOJI = {
    SUCCESS = "✅",
    ERROR = "❌",
    START = "🔴",
    STOP = "⚫"
}

local TG_BOT_STATUS = {
    CONNECTED = EMOJI.SUCCESS .. " Bot Connected: @",
    INVALID_TOKEN = EMOJI.ERROR .. " Invalid Bot Token",
    INVALID_RESPONSE = EMOJI.ERROR .. " Invalid Response",
    NETWORK_ERROR = EMOJI.ERROR .. " Network Error"
}

local TG_CHAT_STATUS = {
    FOUND = " | " .. EMOJI.SUCCESS .. " Chat: ",
    DM = " | " .. EMOJI.SUCCESS .. " Chat: Direct Message",
    NOT_FOUND = " | " .. EMOJI.ERROR .. " Chat Not Found",
    ERROR = " | " .. EMOJI.ERROR .. " Chat Error"
}

local TG_DEFAULTS = {
    bot_token = "",
    chat_id = ""
}

local TWITCH_DEFAULTS = {
    client_id = "",
    client_secret = "",
    channel_name = ""
}

local DEFAULTS = {
    enable_start = false,
    enable_stop = false,
    start_msg = EMOJI.START .. " Stream Started!",
    stop_msg = EMOJI.STOP .. " Stream Ended",
    enable_delete_start_msg = false
}

local tg_config = {
    bot_token = TG_DEFAULTS.bot_token,
    chat_id = TG_DEFAULTS.chat_id,
    status = TG_CONFIG_STATUS.NOT_CONFIGURED
}

local config = {
    enable_start = DEFAULTS.enable_start,
    enable_stop = DEFAULTS.enable_stop,
    start_msg = DEFAULTS.start_msg,
    stop_msg = DEFAULTS.stop_msg,
    enable_delete_start_msg = DEFAULTS.enable_delete_start_msg
}

local twitch_config = {
    client_id = TWITCH_DEFAULTS.client_id,
    client_secret = TWITCH_DEFAULTS.client_secret,
    channel_name = TWITCH_DEFAULTS.channel_name,
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
    local cmd = "curl -s --max-time 30"
    
    if method == "POST" then
        cmd = cmd .. " -X POST -H " .. q .. "Content-Type: application/x-www-form-urlencoded" .. q .. " -d " .. data
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
    local form_parts = {}
    for key, value in pairs(body_table) do
        table.insert(form_parts, key .. "=" .. url_encode(value))
    end
    local form_data = table.concat(form_parts, "&")
    local escaped_data = escape_shell_json(form_data)
    
    local cmd = build_curl_command(url, "POST", escaped_data)
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

function tg_send_msg(text)
    if tg_config.bot_token == "" or tg_config.chat_id == "" then
        obs.script_log(obs.LOG_ERROR, "Telegram credentials not configured")
        return false, nil
    end
    
    local url = TELEGRAM_API_BASE .. tg_config.bot_token .. "/sendMessage"
    local body = {
        chat_id = tg_config.chat_id,
        text = text,
        parse_mode = "HTML"
    }
    
    local response = http_post(url, body)
    
    if response.status == 200 then
        local msg_id = response.body:match('"message_id":(%d+)')
        return true, msg_id
    end
    
    if response.status == 401 then
        obs.script_log(obs.LOG_ERROR, "Telegram API error (401): Unauthorized")
        return false, nil
    end
    
    if response.status == 400 then
        local description = response.body:match('"description":"([^"]+)"') or "Bad Request"
        obs.script_log(obs.LOG_ERROR, "Telegram API error (400): " .. description)
        return false, nil
    end
    
    if response.status == 429 then
        obs.script_log(obs.LOG_ERROR, "Telegram API error (429): Rate limit exceeded")
        return false, nil
    end
    
    if response.status == 0 then
        obs.script_log(obs.LOG_ERROR, "Failed to send Telegram message: network timeout or DNS failure")
        return false, nil
    end
    
    obs.script_log(obs.LOG_ERROR, "Telegram API error (" .. response.status .. "): Unknown error")
    return false, nil
end

function script_description()
    return [[<b>OBS Telegram Stream Alerts</b> v]] .. VERSION .. [[<br>
<br>
Send Telegram notifications when your stream starts and stops.<br>
<br>
<i>Configure your Telegram bot credentials and message templates below.</i>]]
end

function notify_stream_start()
    if tg_config.bot_token == "" or tg_config.chat_id == "" then
        return
    end
    
    tg_send_msg(config.start_msg)
end

function notify_stream_stop()
    if tg_config.bot_token == "" or tg_config.chat_id == "" then
        return
    end

    tg_send_msg(config.stop_msg)
end

function test_stream_start(props, p)
    notify_stream_start()
    return true
end

function test_stream_stop(props, p)
    notify_stream_stop()
    return true
end

function stream_start()
    if not config.enable_start then
        return
    end
    
    notify_stream_start()
end

function stream_stop()
    if not config.enable_stop then
        return
    end

    notify_stream_stop()
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
    
    local notifications_props = obs.obs_properties_create()
    obs.obs_properties_add_text(notifications_props, "start_msg", "Start Message", obs.OBS_TEXT_MULTILINE)
    obs.obs_properties_add_text(notifications_props, "stop_msg", "Stop Message", obs.OBS_TEXT_MULTILINE)
    obs.obs_properties_add_bool(notifications_props, "enable_start", "Stream Start")
    obs.obs_properties_add_bool(notifications_props, "enable_stop", "Stream Stop")
    obs.obs_properties_add_group(props, "notifications_group", "Notifications", obs.OBS_GROUP_NORMAL, notifications_props)
    
    local testing_props = obs.obs_properties_create()
    obs.obs_properties_add_button(testing_props, "btn_test_start", "Test Stream Start", test_stream_start)
    obs.obs_properties_add_button(testing_props, "btn_test_stop", "Test Stream Stop", test_stream_stop)
    obs.obs_properties_add_group(props, "testing_group", "Testing", obs.OBS_GROUP_NORMAL, testing_props)
    
    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_bool(settings, "enable_start", DEFAULTS.enable_start)
    obs.obs_data_set_default_bool(settings, "enable_stop", DEFAULTS.enable_stop)
    obs.obs_data_set_default_string(settings, "start_msg", DEFAULTS.start_msg)
    obs.obs_data_set_default_string(settings, "stop_msg", DEFAULTS.stop_msg)
    obs.obs_data_set_default_bool(settings, "enable_delete_start_msg", DEFAULTS.enable_delete_start_msg)
    obs.obs_data_set_default_string(settings, "tg_bot_token", TG_DEFAULTS.bot_token)
    obs.obs_data_set_default_string(settings, "tg_chat_id", TG_DEFAULTS.chat_id)
    obs.obs_data_set_default_string(settings, "twitch_client_id", TWITCH_DEFAULTS.client_id)
    obs.obs_data_set_default_string(settings, "twitch_client_secret", TWITCH_DEFAULTS.client_secret)
    obs.obs_data_set_default_string(settings, "twitch_channel_name", TWITCH_DEFAULTS.channel_name)
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
    
    config.enable_start = obs.obs_data_get_bool(settings, "enable_start")
    config.enable_stop = obs.obs_data_get_bool(settings, "enable_stop")
    
    local start_msg = obs.obs_data_get_string(settings, "start_msg")
    config.start_msg = start_msg ~= "" and start_msg or DEFAULTS.start_msg
    
    local stop_msg = obs.obs_data_get_string(settings, "stop_msg")
    config.stop_msg = stop_msg ~= "" and stop_msg or DEFAULTS.stop_msg
    
    if tg_config.bot_token == "" and tg_config.chat_id == "" then
        tg_config.status = TG_CONFIG_STATUS.NOT_CONFIGURED
    elseif tg_config.bot_token ~= "" or tg_config.chat_id ~= "" then
        if not tg_config.status:find(EMOJI.SUCCESS) and not tg_config.status:find(EMOJI.ERROR) then
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
