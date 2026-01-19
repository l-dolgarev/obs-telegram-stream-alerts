-- ============================================================================
-- OBS Telegram Stream Alerts
-- Version: 1.0.0
-- Description: Send Telegram notifications when OBS streaming starts/stops
-- ============================================================================

obs = obslua

VERSION = "1.0.0"
TELEGRAM_API_BASE = "https://api.telegram.org/bot"
TWITCH_OAUTH_URL = "https://id.twitch.tv/oauth2/token"
TWITCH_HELIX_API = "https://api.twitch.tv/helix"

local EMOJI = {
    SUCCESS = "✅",
    ERROR = "❌",
    WARNING = "⚠️",
    ONLINE = "🔴",
    OFFLINE = "⚪"
}

local TG_STATUS = {
    NOT_CONFIGURED = EMOJI.OFFLINE .. " Not Configured",
    NOT_VALIDATED = EMOJI.OFFLINE .. " Not Validated",
    BOT_CONNECTED = EMOJI.SUCCESS .. " Bot Connected: @",
    BOT_INVALID_TOKEN = EMOJI.ERROR .. " Invalid Bot Token",
    BOT_INVALID_RESPONSE = EMOJI.ERROR .. " Invalid Response",
    BOT_NETWORK_ERROR = EMOJI.ERROR .. " Network Error",
    BOT_RATE_LIMITED = EMOJI.WARNING .. " Rate Limited",
    CHAT_FOUND = " | " .. EMOJI.SUCCESS .. " Chat: ",
    CHAT_DM = " | " .. EMOJI.SUCCESS .. " Chat: Direct Message",
    CHAT_NOT_FOUND = " | " .. EMOJI.ERROR .. " Chat Not Found",
    CHAT_ERROR = " | " .. EMOJI.ERROR .. " Chat Error",
    CHAT_RATE_LIMITED = " | " .. EMOJI.WARNING .. " Rate Limited"
}

local TWITCH_STATUS = {
    NOT_CONFIGURED = EMOJI.OFFLINE .. " Not Configured",
    NOT_VALIDATED = EMOJI.OFFLINE .. " Not Validated",
    CONNECTED = EMOJI.SUCCESS .. " Connected: ",
    AUTH_FAILED = EMOJI.ERROR .. " Auth Failed: ",
    CHANNEL_OFFLINE = EMOJI.OFFLINE .. " Channel Offline"
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
    start_msg = EMOJI.ONLINE .. " <i>Stream started:</i> {stream_title}\nNow playing <b>{category}</b>",
    stop_msg = EMOJI.OFFLINE .. " <i>Stream offline:</i> {stream_title}\nThanks to all <code>{viewer_count}</code> viewers for watching!",
    start_delay = 0,
    preview_url = "",
    enable_start = false,
    enable_stop = false,
    enable_delete_start_msg = false
}

local tg_config = {
    bot_token = TG_DEFAULTS.bot_token,
    chat_id = TG_DEFAULTS.chat_id,
    status = TG_STATUS.NOT_CONFIGURED
}

local config = {
    start_msg = DEFAULTS.start_msg,
    stop_msg = DEFAULTS.stop_msg,
    start_msg_id = nil,
    start_delay = DEFAULTS.start_delay,
    preview_url = DEFAULTS.preview_url,
    enable_start = DEFAULTS.enable_start,
    enable_stop = DEFAULTS.enable_stop,
    enable_delete_start_msg = DEFAULTS.enable_delete_start_msg
}

local twitch_config = {
    client_id = TWITCH_DEFAULTS.client_id,
    client_secret = TWITCH_DEFAULTS.client_secret,
    channel_name = TWITCH_DEFAULTS.channel_name,
    oauth_token = nil,
    token_expires_at = nil,
    status = TWITCH_STATUS.NOT_CONFIGURED
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

function escape_html(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("&", "&amp;")
    str = str:gsub("<", "&lt;")
    str = str:gsub(">", "&gt;")
    str = str:gsub('"', "&quot;")
    str = str:gsub("'", "&#39;")
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
        tg_config.status = TG_STATUS.NOT_CONFIGURED
        return false
    end
    
    local url = TELEGRAM_API_BASE .. tg_config.bot_token .. "/getMe"
    local response = http_get(url)
    
    if response.status == 401 or response.status == 404 then
        tg_config.status = TG_STATUS.BOT_INVALID_TOKEN
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Invalid bot token")
        return false
    end
    
    if response.status == 429 then
        tg_config.status = TG_STATUS.BOT_RATE_LIMITED
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Rate limited - wait before retrying")
        return false
    end
    
    if response.status ~= 200 then
        tg_config.status = TG_STATUS.BOT_NETWORK_ERROR
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Network error (status " .. response.status .. ")")
        return false
    end
    
    local username = response.body:match('"username":"([^"]+)"')
    if not username then
        tg_config.status = TG_STATUS.BOT_INVALID_RESPONSE
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Unable to parse bot username")
        return false
    end
    
    tg_config.status = TG_STATUS.BOT_CONNECTED .. username
    return true
end

function tg_validate_chat_id()
    if tg_config.chat_id == "" then
        return false
    end
    
    local url = TELEGRAM_API_BASE .. tg_config.bot_token .. "/getChat?chat_id=" .. url_encode(tg_config.chat_id)
    local response = http_get(url)
    
    if response.status == 400 or response.status == 404 then
        tg_config.status = tg_config.status .. TG_STATUS.CHAT_NOT_FOUND
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Chat not found")
        return false
    end
    
    if response.status == 429 then
        tg_config.status = tg_config.status .. TG_STATUS.CHAT_RATE_LIMITED
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Rate limited - wait before retrying")
        return false
    end
    
    if response.status ~= 200 then
        tg_config.status = tg_config.status .. TG_STATUS.CHAT_ERROR
        obs.script_log(obs.LOG_ERROR, "Telegram validation failed: Network error (status " .. response.status .. ")")
        return false
    end
    
    local title = response.body:match('"title":"([^"]+)"')
    if title then
        tg_config.status = tg_config.status .. TG_STATUS.CHAT_FOUND .. title
    else
        tg_config.status = tg_config.status .. TG_STATUS.CHAT_DM
    end
    
    return true
end

function substitute_placeholders(template, metadata)
    if not template then return "" end
    
    if not metadata then
        template = template:gsub("{stream_title}", "")
        template = template:gsub("{category}", "")
        template = template:gsub("{viewer_count}", "")
        return template
    end
    
    if metadata.stream_title then
        template = template:gsub("{stream_title}", escape_html(metadata.stream_title))
    else
        template = template:gsub("{stream_title}", "")
    end
    
    if metadata.category then
        template = template:gsub("{category}", escape_html(metadata.category))
    else
        template = template:gsub("{category}", "")
    end
    
    if metadata.viewer_count then
        template = template:gsub("{viewer_count}", tostring(metadata.viewer_count))
    else
        template = template:gsub("{viewer_count}", "")
    end
    
    return template
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

function tg_send_photo(photo_url, caption)
    if tg_config.bot_token == "" or tg_config.chat_id == "" then
        obs.script_log(obs.LOG_ERROR, "Telegram credentials not configured")
        return false, nil
    end
    
    local url = TELEGRAM_API_BASE .. tg_config.bot_token .. "/sendPhoto"
    local body = {
        chat_id = tg_config.chat_id,
        photo = photo_url,
        caption = caption,
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
        obs.script_log(obs.LOG_ERROR, "Failed to send Telegram photo: network timeout or DNS failure")
        return false, nil
    end
    
    obs.script_log(obs.LOG_ERROR, "Telegram API error (" .. response.status .. "): Unknown error")
    return false, nil
end

function tg_delete_msg(message_id)
    if not message_id or message_id == "" then
        return false
    end
    
    local url = TELEGRAM_API_BASE .. tg_config.bot_token .. "/deleteMessage"
    local body = {
        chat_id = tg_config.chat_id,
        message_id = message_id
    }
    
    local response = http_post(url, body)
    
    if response.status == 200 then
        return true
    end
    
    if response.status == 429 then
        obs.script_log(obs.LOG_ERROR, "Failed to delete message: Rate limit exceeded")
        return false
    end
    
    local description = response.body:match('"description":"([^"]+)"') or "Unknown error"
    obs.script_log(obs.LOG_ERROR, "Failed to delete message: " .. description)
    return false
end

function get_twitch_oauth_token()
    if twitch_config.client_id == "" or twitch_config.client_secret == "" then
        return nil, "Credentials not configured"
    end
    
    local body = {
        client_id = twitch_config.client_id,
        client_secret = twitch_config.client_secret,
        grant_type = "client_credentials"
    }
    
    local response = http_post(TWITCH_OAUTH_URL, body)
    
    if response.status == 401 or response.status == 400 then
        obs.script_log(obs.LOG_ERROR, "Twitch OAuth failed: Invalid credentials")
        return nil, "Invalid credentials"
    end
    
    if response.status == 0 then
        obs.script_log(obs.LOG_ERROR, "Twitch OAuth failed: Network error")
        return nil, "Network error"
    end
    
    if response.status ~= 200 then
        obs.script_log(obs.LOG_ERROR, "Twitch OAuth failed: HTTP " .. response.status)
        return nil, "HTTP " .. response.status
    end
    
    local access_token = response.body:match('"access_token":"([^"]+)"')
    local expires_in = response.body:match('"expires_in":(%d+)')
    
    if not access_token then
        obs.script_log(obs.LOG_ERROR, "Twitch OAuth failed: Unable to parse token")
        return nil, "Invalid response"
    end
    
    return access_token, expires_in
end

function get_twitch_stream_status(oauth_token)
    if twitch_config.channel_name == "" then
        return nil, "Channel name not configured"
    end
    
    local url = TWITCH_HELIX_API .. "/streams?user_login=" .. url_encode(twitch_config.channel_name)
    local platform = detect_platform()
    local is_windows = platform == "windows"
    local q = is_windows and '"' or "'"
    
    local cmd = "curl -s --max-time 30"
    cmd = cmd .. " -H " .. q .. "Authorization: Bearer " .. oauth_token .. q
    cmd = cmd .. " -H " .. q .. "Client-ID: " .. twitch_config.client_id .. q
    cmd = cmd .. " -w " .. q .. "\\n%{http_code}" .. q
    cmd = cmd .. " " .. q .. url .. q
    
    local handle = io.popen(cmd)
    if not handle then
        obs.script_log(obs.LOG_ERROR, "Twitch stream status failed: Unable to execute curl")
        return nil, "Unable to execute curl"
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local response = parse_curl_response(output)
    
    if response.status == 401 then
        obs.script_log(obs.LOG_ERROR, "Twitch stream status failed: Invalid token")
        return nil, "Invalid token"
    end
    
    if response.status == 404 then
        obs.script_log(obs.LOG_ERROR, "Twitch channel not found: " .. twitch_config.channel_name)
        return nil, "Channel not found"
    end
    
    if response.status == 0 then
        obs.script_log(obs.LOG_ERROR, "Twitch stream status failed: Network error")
        return nil, "Network error"
    end
    
    if response.status ~= 200 then
        obs.script_log(obs.LOG_ERROR, "Twitch stream status failed: HTTP " .. response.status)
        return nil, "HTTP " .. response.status
    end
    
    local data_empty = response.body:match('"data":%[%]')
    if data_empty then
        return "offline", nil
    end
    
    local user_login = response.body:match('"user_login":"([^"]+)"')
    local game_name = response.body:match('"game_name":"([^"]+)"')
    local title = response.body:match('"title":"([^"]+)"')
    local viewer_count = response.body:match('"viewer_count":(%d+)')
    
    if user_login then
        local metadata = {
            user_login = user_login,
            game_name = game_name or "Unknown",
            title = title or "Untitled",
            viewer_count = viewer_count or "0"
        }
        return "live", metadata
    end
    
    return "offline", nil
end

function get_twitch_live_metadata(oauth_token)
    local url = TWITCH_HELIX_API .. "/streams?user_login=" .. url_encode(twitch_config.channel_name)
    local platform = detect_platform()
    local is_windows = platform == "windows"
    local q = is_windows and '"' or "'"
    
    local cmd = "curl -s --max-time 30"
    cmd = cmd .. " -H " .. q .. "Authorization: Bearer " .. oauth_token .. q
    cmd = cmd .. " -H " .. q .. "Client-ID: " .. twitch_config.client_id .. q
    cmd = cmd .. " -w " .. q .. "\\n%{http_code}" .. q
    cmd = cmd .. " " .. q .. url .. q
    
    local handle = io.popen(cmd)
    if not handle then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch live stream data: Unable to execute curl")
        return nil
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local response = parse_curl_response(output)
    
    if response.status ~= 200 then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch live stream data: HTTP " .. response.status)
        return nil
    end
    
    local data_empty = response.body:match('"data":%[%]')
    if data_empty then
        return nil
    end
    
    local title = response.body:match('"title":"([^"]+)"')
    local game_name = response.body:match('"game_name":"([^"]+)"')
    local viewer_count = response.body:match('"viewer_count":(%d+)')
    local thumbnail_url = response.body:match('"thumbnail_url":"([^"]+)"')
    
    if not title then
        return nil
    end
    
    local metadata = {
        stream_title = title,
        category = game_name or "Unknown",
        viewer_count = viewer_count or "0"
    }
    
    if thumbnail_url then
        metadata.preview_url = thumbnail_url:gsub("{width}", "1920"):gsub("{height}", "1080")
    end
    
    return metadata
end

function get_twitch_user_id(oauth_token)
    local url = TWITCH_HELIX_API .. "/users?login=" .. url_encode(twitch_config.channel_name)
    local platform = detect_platform()
    local is_windows = platform == "windows"
    local q = is_windows and '"' or "'"
    
    local cmd = "curl -s --max-time 30"
    cmd = cmd .. " -H " .. q .. "Authorization: Bearer " .. oauth_token .. q
    cmd = cmd .. " -H " .. q .. "Client-ID: " .. twitch_config.client_id .. q
    cmd = cmd .. " -w " .. q .. "\\n%{http_code}" .. q
    cmd = cmd .. " " .. q .. url .. q
    
    local handle = io.popen(cmd)
    if not handle then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch user ID: Unable to execute curl")
        return nil
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local response = parse_curl_response(output)
    
    if response.status ~= 200 then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch user ID: HTTP " .. response.status)
        return nil
    end
    
    local user_id = response.body:match('"id":"([^"]+)"')
    if not user_id then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch user ID: Unable to parse response")
        return nil
    end
    
    return user_id
end

function get_twitch_channel_by_id(oauth_token, user_id)
    local url = TWITCH_HELIX_API .. "/channels?broadcaster_id=" .. url_encode(user_id)
    local platform = detect_platform()
    local is_windows = platform == "windows"
    local q = is_windows and '"' or "'"
    
    local cmd = "curl -s --max-time 30"
    cmd = cmd .. " -H " .. q .. "Authorization: Bearer " .. oauth_token .. q
    cmd = cmd .. " -H " .. q .. "Client-ID: " .. twitch_config.client_id .. q
    cmd = cmd .. " -w " .. q .. "\\n%{http_code}" .. q
    cmd = cmd .. " " .. q .. url .. q
    
    local handle = io.popen(cmd)
    if not handle then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch channel data: Unable to execute curl")
        return nil
    end
    
    local output = handle:read("*a")
    handle:close()
    
    local response = parse_curl_response(output)
    
    if response.status ~= 200 then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch channel data: HTTP " .. response.status)
        return nil
    end
    
    local title = response.body:match('"title":"([^"]+)"')
    local game_name = response.body:match('"game_name":"([^"]+)"')
    
    if not title then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch channel data: Unable to parse response")
        return nil
    end
    
    return {
        stream_title = title,
        category = game_name or "Unknown",
        viewer_count = "0"
    }
end

function get_twitch_channel_info(oauth_token)
    local user_id = get_twitch_user_id(oauth_token)
    if not user_id then
        return nil
    end
    
    return get_twitch_channel_by_id(oauth_token, user_id)
end

function get_twitch_metadata()
    if twitch_config.client_id == "" or twitch_config.client_secret == "" or twitch_config.channel_name == "" then
        return nil
    end
    
    local oauth_token = twitch_config.oauth_token
    
    if not oauth_token or not twitch_config.token_expires_at or os.time() >= twitch_config.token_expires_at then
        local new_token, expires_in = get_twitch_oauth_token()
        if not new_token then
            obs.script_log(obs.LOG_ERROR, "Failed to fetch Twitch metadata: OAuth token unavailable")
            return nil
        end
        
        oauth_token = new_token
        twitch_config.oauth_token = new_token
        twitch_config.token_expires_at = os.time() + tonumber(expires_in or 5184000)
    end
    
    local metadata = get_twitch_live_metadata(oauth_token)
    if metadata then
        return metadata
    end
    
    return get_twitch_channel_info(oauth_token)
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
    
    local metadata = get_twitch_metadata()
    local message = substitute_placeholders(config.start_msg, metadata)
    local preview_url = nil
    
    if metadata and metadata.preview_url then
        preview_url = metadata.preview_url
    elseif config.preview_url ~= "" then
        preview_url = config.preview_url
    end
    
    local success, message_id
    
    if preview_url then
        success, message_id = tg_send_photo(preview_url, message)
    else
        success, message_id = tg_send_msg(message)
    end
    
    if success and message_id then
        config.start_msg_id = message_id
    end
end

function notify_stream_stop()
    if tg_config.bot_token == "" or tg_config.chat_id == "" then
        return
    end
    
    local metadata = get_twitch_metadata()
    local message = substitute_placeholders(config.stop_msg, metadata)
    local preview_url = nil
    
    if metadata and metadata.preview_url then
        preview_url = metadata.preview_url
    elseif config.preview_url ~= "" then
        preview_url = config.preview_url
    end
    
    if preview_url then
        tg_send_photo(preview_url, message)
    else
        tg_send_msg(message)
    end
    
    if config.enable_delete_start_msg and config.start_msg_id and config.start_msg_id ~= "" then
        tg_delete_msg(config.start_msg_id)
        config.start_msg_id = nil
    end
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
    
    local delay_ms = config.start_delay * 1000
    
    if delay_ms == 0 then
        notify_stream_start()
    else
        obs.timer_add(function()
            obs.remove_current_callback()
            notify_stream_start()
        end, delay_ms)
    end
end

function stream_stop()
    if not config.enable_stop then
        return
    end

    notify_stream_stop()
end

function tg_validate_config_callback(props, prop)
    tg_validate_bot_token()
    if tg_config.bot_token ~= "" and tg_config.status:find(TG_STATUS.BOT_CONNECTED, 1, true) then
        tg_validate_chat_id()
    end
    
    local status_prop = obs.obs_properties_get(props, "tg_config_status")
    if status_prop then
        obs.obs_property_set_description(status_prop, tg_config.status)
    end
    
    return true
end

function validate_twitch_config_callback(props, prop)
    if twitch_config.client_id == "" or twitch_config.client_secret == "" or twitch_config.channel_name == "" then
        twitch_config.status = TWITCH_STATUS.NOT_CONFIGURED
        local status_prop = obs.obs_properties_get(props, "twitch_status_display")
        if status_prop then
            obs.obs_property_set_description(status_prop, twitch_config.status)
        end
        return true
    end
    
    local oauth_token, err = get_twitch_oauth_token()
    if not oauth_token then
        twitch_config.status = TWITCH_STATUS.AUTH_FAILED .. err
        local status_prop = obs.obs_properties_get(props, "twitch_status_display")
        if status_prop then
            obs.obs_property_set_description(status_prop, twitch_config.status)
        end
        return true
    end
    
    local stream_status, metadata = get_twitch_stream_status(oauth_token)
    if not stream_status then
        twitch_config.status = TWITCH_STATUS.AUTH_FAILED .. metadata
        local status_prop = obs.obs_properties_get(props, "twitch_status_display")
        if status_prop then
            obs.obs_property_set_description(status_prop, twitch_config.status)
        end
        return true
    end
    
    if stream_status == "offline" then
        twitch_config.status = TWITCH_STATUS.CHANNEL_OFFLINE
    elseif stream_status == "live" and metadata then
        twitch_config.status = TWITCH_STATUS.CONNECTED .. twitch_config.channel_name
    end
    
    local status_prop = obs.obs_properties_get(props, "twitch_status_display")
    if status_prop then
        obs.obs_property_set_description(status_prop, twitch_config.status)
    end
    
    return true
end

function script_properties()
    local props = obs.obs_properties_create()
    
    local tg_props = obs.obs_properties_create()
    obs.obs_properties_add_text(tg_props, "tg_bot_token", "Bot Token", obs.OBS_TEXT_PASSWORD)
    obs.obs_properties_add_text(tg_props, "tg_chat_id", "Chat ID", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_button(tg_props, "btn_tg_config_validate", "Validate", tg_validate_config_callback)
    local tg_status_prop = obs.obs_properties_add_text(tg_props, "tg_config_status", "Status", obs.OBS_TEXT_INFO)
    obs.obs_property_set_enabled(tg_status_prop, false)
    obs.obs_property_set_description(tg_status_prop, tg_config.status)
    obs.obs_properties_add_group(props, "tg_config_group", "Telegram", obs.OBS_GROUP_NORMAL, tg_props)
    
    local notifications_props = obs.obs_properties_create()
    obs.obs_properties_add_text(notifications_props, "start_msg", "Start Message", obs.OBS_TEXT_MULTILINE)
    obs.obs_properties_add_text(notifications_props, "stop_msg", "Stop Message", obs.OBS_TEXT_MULTILINE)
    obs.obs_properties_add_int(notifications_props, "start_delay", "Start Notification Delay (sec)", 0, 300, 1)
    obs.obs_properties_add_text(notifications_props, "preview_url", "Preview URL", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_bool(notifications_props, "enable_start", "Stream Start")
    obs.obs_properties_add_bool(notifications_props, "enable_stop", "Stream Stop")
    obs.obs_properties_add_bool(notifications_props, "enable_delete_start_msg", "Delete Start Message on Stop")
    obs.obs_properties_add_group(props, "notifications_group", "Notifications", obs.OBS_GROUP_NORMAL, notifications_props)
    
    local twitch_props = obs.obs_properties_create()
    obs.obs_properties_add_text(twitch_props, "twitch_client_id", "Client ID", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(twitch_props, "twitch_client_secret", "Client Secret", obs.OBS_TEXT_PASSWORD)
    obs.obs_properties_add_text(twitch_props, "twitch_channel_name", "Channel Name", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_button(twitch_props, "btn_validate_twitch", "Validate", validate_twitch_config_callback)
    local twitch_status_prop = obs.obs_properties_add_text(twitch_props, "twitch_status_display", "Status", obs.OBS_TEXT_INFO)
    obs.obs_property_set_enabled(twitch_status_prop, false)
    obs.obs_property_set_description(twitch_status_prop, twitch_config.status)
    obs.obs_properties_add_group(props, "twitch_group", "Twitch (optional)", obs.OBS_GROUP_NORMAL, twitch_props)
    
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
    obs.obs_data_set_default_int(settings, "start_delay", DEFAULTS.start_delay)
    obs.obs_data_set_default_bool(settings, "enable_delete_start_msg", DEFAULTS.enable_delete_start_msg)
    obs.obs_data_set_default_string(settings, "preview_url", DEFAULTS.preview_url)
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
    config.enable_delete_start_msg = obs.obs_data_get_bool(settings, "enable_delete_start_msg")
    config.start_msg = obs.obs_data_get_string(settings, "start_msg")
    config.stop_msg = obs.obs_data_get_string(settings, "stop_msg")
    config.start_delay = obs.obs_data_get_int(settings, "start_delay")
    config.preview_url = obs.obs_data_get_string(settings, "preview_url")
    
    tg_config.status = (tg_config.bot_token == "" and tg_config.chat_id == "") and TG_STATUS.NOT_CONFIGURED or TG_STATUS.NOT_VALIDATED
    
    twitch_config.client_id = obs.obs_data_get_string(settings, "twitch_client_id")
    twitch_config.client_secret = obs.obs_data_get_string(settings, "twitch_client_secret")
    twitch_config.channel_name = obs.obs_data_get_string(settings, "twitch_channel_name")
    
    twitch_config.status = (twitch_config.client_id == "" and twitch_config.client_secret == "" and twitch_config.channel_name == "") and TWITCH_STATUS.NOT_CONFIGURED or TWITCH_STATUS.NOT_VALIDATED
end

function script_load(settings)
    obs.obs_frontend_add_event_callback(on_event)
end

function script_unload()
    obs.obs_frontend_remove_event_callback(on_event)
end
