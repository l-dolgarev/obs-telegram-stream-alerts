-- ============================================================================
-- OBS Telegram Stream Alerts
-- Version: 1.0.0
-- Description: Send Telegram notifications when OBS streaming starts/stops
-- ============================================================================

obs = obslua

VERSION = "1.0.0"
DESCRIPTION = [[<b>OBS Telegram Stream Alerts</b> v]] .. VERSION .. [[<br>
<br>
Send Telegram notifications when your stream starts and stops.<br>
<br>
<i>Configure your Telegram bot credentials and message templates below.</i>]]

TELEGRAM_BOT_API = "https://api.telegram.org/bot"
TWITCH_OAUTH_API = "https://id.twitch.tv/oauth2"
TWITCH_HELIX_API = "https://api.twitch.tv/helix"

PREVIEW_WIDTH = 1920
PREVIEW_HEIGHT = 1080

DEFAULT_START_MSG = "🔴 <i>Stream started:</i>\n{title}\nNow playing: <b>{category}</b>"
DEFAULT_STOP_MSG = "⚪ <i>Stream offline:</i>\n{title}\nThanks to all <code>{viewer_count}</code> viewers for watching!"
DEFAULT_START_DELAY = 0
DEFAULT_ENABLE_START = false
DEFAULT_ENABLE_STOP = false
DEFAULT_ENABLE_PREVIEW = false
DEFAULT_ENABLE_DELETE_START_MSG = false
DEFAULT_TG_BOT_TOKEN = ""
DEFAULT_TG_CHAT_ID = ""
DEFAULT_TWITCH_CLIENT_ID = ""
DEFAULT_TWITCH_CLIENT_SECRET = ""
DEFAULT_TWITCH_CHANNEL = ""

local start_msg = DEFAULT_START_MSG
local stop_msg = DEFAULT_STOP_MSG
local start_msg_id = nil
local start_delay = DEFAULT_START_DELAY
local enable_start = DEFAULT_ENABLE_START
local enable_stop = DEFAULT_ENABLE_STOP
local enable_preview = DEFAULT_ENABLE_PREVIEW
local enable_delete_start_msg = DEFAULT_ENABLE_DELETE_START_MSG
local tg_bot_token = DEFAULT_TG_BOT_TOKEN
local tg_chat_id = DEFAULT_TG_CHAT_ID
local twitch_client_id = DEFAULT_TWITCH_CLIENT_ID
local twitch_client_secret = DEFAULT_TWITCH_CLIENT_SECRET
local twitch_channel = DEFAULT_TWITCH_CHANNEL
local twitch_user_id = nil
local twitch_token = nil
local twitch_token_expires_at = nil

function is_windows()
    return package.config:sub(1,1) == "\\"
end

function url_encode(str)
    if not str or str == "" then return "" end

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

function build_curl()
    local q = is_windows() and '"' or "'"
    local cmd = "curl.exe -s --max-time 30"
    return cmd, q
end

function build_curl_headers(headers)
    local cmd, q = build_curl()
    if headers then
        for k, v in pairs(headers) do
            cmd = cmd .. " -H " .. q .. k .. ": " .. v .. q
        end
    end
    return cmd, q
end

function build_curl_url(url, q)
    return " -w " .. q .. "\\n%{http_code}" .. q .. " " .. q .. url .. q
end

function build_curl_get(url, headers)
    local cmd, q = build_curl_headers(headers)
    cmd = cmd .. build_curl_url(url, q)
    return cmd
end

function build_curl_output(url, output)
    local cmd, q = build_curl()
    if output then
        cmd = cmd .. " -o " .. q .. output .. q
    end
    cmd = cmd .. build_curl_url(url, q)
    return cmd
end

function build_curl_post_form(url, data)
    local cmd, q = build_curl()
    cmd = cmd .. " -X POST -H " .. q .. "Content-Type: application/x-www-form-urlencoded" .. q
    if data then
        cmd = cmd .. " -d " .. q .. data .. q
    end
    cmd = cmd .. build_curl_url(url, q)
    return cmd
end


function build_curl_post_multipart(url, fields)
    local cmd, q = build_curl()
    cmd = cmd .. " -X POST"
    if fields then
        for k, v in pairs(fields) do
            cmd = cmd .. " -F " .. q .. k .. "=" .. v .. q
        end
    end

    cmd = cmd .. build_curl_url(url, q)
    return cmd, q
end

function build_curl_encode_output(url, fields, caption)
    local cmd, q = build_curl_post_multipart(url, fields)
    cmd = "$OutputEncoding = [System.Text.Encoding]::UTF8\n$caption = @" .. q .. "\n" .. caption .. "\n" .. q .. "@\n\n" .. cmd .. "\n"
    return cmd, q
end

function http_empty_response()
    return {success = false, status = 0, body = ""}
end

function http_response_to_string(response)
    return response.status .. " " .. response.body
end

function parse_curl_response(output)
    if not output or output == "" then
        return http_empty_response()
    end
    
    local lines = {}
    for line in output:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    
    local status_code = tonumber(lines[#lines]) or 0
    table.remove(lines, #lines)
    local body = table.concat(lines, "\n")
    local success = status_code >= 200 and status_code < 300
    
    return {success = success, status = status_code, body = body}
end

function get_temp_file_path(ext)
    local tmp_path = os.tmpname()
    if ext then tmp_path = tmp_path .. ext end
    return tmp_path
end

function write_temp_file(content, ext)
    local tmp_path = get_temp_file_path(ext)
    local f = io.open(tmp_path, "w")
    if not f then return nil end
    f:write(content)
    f:close()
    return tmp_path
end

function download_image(url)
    local tmp_path = get_temp_file_path(".jpg")
    local cmd = build_curl_output(url, tmp_path)
    local result = os.execute(cmd)
    if result ~= 0 then
        obs.script_log(obs.LOG_ERROR, "Failed to download image from URL: " .. url)
        return nil
    end
    return tmp_path
end

function http_get(url, headers)
    local cmd = build_curl_get(url, headers)
    local handle = io.popen(cmd)
    if not handle then
        obs.script_log(obs.LOG_ERROR, "Unable to execute curl (check if curl is installed)")
        return http_empty_response()
    end

    local output = handle:read("*a")
    handle:close()
    return parse_curl_response(output)
end

function http_post(url, data)
    local form_parts = {}
    for k, v in pairs(data) do
        table.insert(form_parts, url_encode(k) .. "=" .. url_encode(v))
    end
    local form_data = table.concat(form_parts, "&")
    local cmd = build_curl_post_form(url, form_data)
    local handle = io.popen(cmd)
    if not handle then
        obs.script_log(obs.LOG_ERROR, "Unable to execute curl (check if curl is installed)")
        return http_empty_response()
    end

    local output = handle:read("*a")
    handle:close()
    
    return parse_curl_response(output)
end

function replace_placeholders(text, data)
    if not text then return "" end
    
    if not data then
        text = text:gsub("{title}", "")
        text = text:gsub("{category}", "")
        text = text:gsub("{viewer_count}", "")
        return text
    end
    
    text = text:gsub("{title}", escape_html(data.title))
    text = text:gsub("{category}", escape_html(data.category))
    text = text:gsub("{viewer_count}", tostring(data.viewer_count))

    return text
end

function send_tg_msg(text)
    if text == "" or tg_bot_token == "" or tg_chat_id == "" then return end

    local url = TELEGRAM_BOT_API .. tg_bot_token .. "/sendMessage"
    local data = {
        chat_id = tg_chat_id,
        text = text,
        parse_mode = "HTML",
        disable_web_page_preview = "true"
    }
    local response = http_post(url, data)
    if not response.success then
        obs.script_log(obs.LOG_ERROR, "Telegram Bot API error: " .. http_response_to_string(response))
        return
    end

    return response
end

function send_start_tg_msg(text)
    local response = send_tg_msg(text)
    start_msg_id = response.body:match('"message_id":(%d+)')
end

function send_tg_photo(text, photo_url)
    if tg_bot_token == "" or tg_chat_id == "" then return end
    
    local url = TELEGRAM_BOT_API .. tg_bot_token .. "/sendPhoto"
    local caption = text or ""
    local photo_path = download_image(photo_url)

    local fields = {
        ["chat_id"] = tg_chat_id,
        ["parse_mode"] = "HTML",
        ["caption"] = "$caption",
        ["photo"] = "@" .. photo_path
    }
    local ps1_content, q = build_curl_encode_output(url, fields, caption)
    local ps1_path = os.tmpname() .. ".ps1"
    local f = io.open(ps1_path, "wb")
    if not f then
        obs.script_log(obs.LOG_ERROR, "Unable to execute curl (check if curl is installed)")
        return
    end
    
    f:write(string.char(0xEF,0xBB,0xBF)) -- Write UTF-8 BOM
    f:write(ps1_content)
    f:close()

    local cmd = "powershell -ExecutionPolicy Bypass -File " .. q .. ps1_path .. q
    local handle = io.popen(cmd, "r")
    local output = ""
    if handle then
        output = handle:read("*a")
        handle:close()
    end

    os.remove(ps1_path)
    os.remove(photo_path)

    local response = parse_curl_response(output)
    if not response.success then
        obs.script_log(obs.LOG_ERROR, "Telegram Bot API error: " .. http_response_to_string(response))
        return
    end

    return response
end

function send_start_tg_photo(text, photo_url)
    local response = send_tg_photo(text, photo_url)
    start_msg_id = response.body:match('"message_id":(%d+)')
end

function delete_tg_msg(message_id)
    if not message_id then return end
    
    local url = TELEGRAM_BOT_API .. tg_bot_token .. "/deleteMessage"
    local data = {
        chat_id = tg_chat_id,
        message_id = message_id
    }
    
    local response = http_post(url, data)
    if not response.success then
        obs.script_log(obs.LOG_ERROR, "Telegram Bot API error: " .. http_response_to_string(response))
        return
    end
end

function get_twitch_token()
    if twitch_client_id == "" or twitch_client_secret == "" then return end

    local url = TWITCH_OAUTH_API .. "/token"
    local data = {
        client_id = twitch_client_id,
        client_secret = twitch_client_secret,
        grant_type = "client_credentials"
    }
    local response = http_post(url, data)
    
    if not response.success then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch Twitch token: " .. http_response_to_string(response))
        return
    end
    
    twitch_token = response.body:match('"access_token":"([^"]+)"')
    twitch_expires_in = response.body:match('"expires_in":(%d+)')
    
    if not twitch_token then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch Twitch token: Unable to parse data")
        return
    end
end

function get_twitch_user()
    if not twitch_token or not twitch_client_id or twitch_channel == "" then return end

    local url = TWITCH_HELIX_API .. "/users?login=" .. url_encode(twitch_channel)
    local headers = {
        ["Authorization"] = "Bearer " .. twitch_token,
        ["Client-ID"] = twitch_client_id
    }
    local response = http_get(url, headers)

    if not response.success then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch Twitch user: " .. http_response_to_string(response))
        return
    end

    twitch_user_id = response.body:match('"id":"([^"]+)"')

    if not twitch_user_id then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch Twitch user: Unable to parse data")
        return
    end
end

function get_twitch_channel()
    if not twitch_token or not twitch_client_id or not twitch_user_id then return nil end

    local url = TWITCH_HELIX_API .. "/channels?broadcaster_id=" .. url_encode(twitch_user_id)
    local headers = {
        ["Authorization"] = "Bearer " .. twitch_token,
        ["Client-ID"] = twitch_client_id
    }
    local response = http_get(url, headers)

    if not response.success then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch Twitch channel: " .. http_response_to_string(response))
        return nil
    end

    return response.body
end

function get_twitch_stream()
    if not twitch_token or not twitch_client_id or twitch_channel == "" then return nil end

    local url = TWITCH_HELIX_API .. "/streams?user_login=" .. url_encode(twitch_channel)
    local headers = {
        ["Authorization"] = "Bearer " .. twitch_token,
        ["Client-ID"] = twitch_client_id
    }
    local response = http_get(url, headers)
    
    if not response.success then
        obs.script_log(obs.LOG_ERROR, "Failed to fetch Twitch stream: " .. http_response_to_string(response))
        return nil
    end

    return response.body
end

function get_twitch_metadata()
    if not twitch_token or not twitch_token_expires_at or os.time() >= twitch_token_expires_at then
        get_twitch_token()
    end
    
    if not twitch_user_id then
        get_twitch_user()
    end
    
    if enable_preview then
        local stream = get_twitch_stream()
        if stream then
            return {
                title = stream:match('"title":"([^"]+)"'),
                category = stream:match('"game_name":"([^"]+)"'),
                viewer_count = stream:match('"viewer_count":(%d+)'),
                thumbnail_url = stream:match('"thumbnail_url":"([^"]+)"')
            }
        end
    end

    local channel = get_twitch_channel()
    return {
        title = channel:match('"title":"([^"]+)"'),
        category = channel:match('"game_name":"([^"]+)"'),
        viewer_count = 0,
        thumbnail_url = nil
    }
end

function stream_start()
    local data = get_twitch_metadata()
    local thumb_url = data.thumbnail_url
    local msg = replace_placeholders(start_msg, data)

    if enable_preview and thumb_url then
        thumb_url = thumb_url:gsub("{width}", PREVIEW_WIDTH)
        thumb_url = thumb_url:gsub("{height}", PREVIEW_HEIGHT)
        thumb_url = thumb_url .. "?cb=" .. tostring(os.time()) .. tostring(math.random(1000,9999))
        send_start_tg_photo(msg, thumb_url)
    else
        send_start_tg_msg(msg)
    end
end

function stream_stop()
    local data = get_twitch_metadata()
    local thumb_url = data.thumbnail_url
    local msg = replace_placeholders(stop_msg, data)
    
    if enable_preview and thumb_url then
        thumb_url = thumb_url:gsub("{width}", PREVIEW_WIDTH)
        thumb_url = thumb_url:gsub("{height}", PREVIEW_HEIGHT)
        thumb_url = thumb_url .. "?cb=" .. tostring(os.time()) .. tostring(math.random(1000,9999))
        send_tg_photo(msg, thumb_url)
    else
        send_tg_msg(msg)
    end
    
    if enable_delete_start_msg and start_msg_id then
        delete_tg_msg(start_msg_id)
        start_msg_id = nil
    end
end

function on_stream_started()
    if not enable_start then return end

    local start_delay_ms = start_delay * 1000
    if start_delay_ms > 0 then
        obs.timer_add(function()
            obs.remove_current_callback()
            stream_start()
        end, start_delay_ms)
        return
    end

    stream_start()
end

function on_stream_stopped()
    if not enable_stop then return end
    
    stream_stop()
end

function test_stream_start(props, p)
    on_stream_started()
    return true
end

function test_stream_stop(props, p)
    on_stream_stopped()
    return true
end

function on_event(event)
    if event == obs.OBS_FRONTEND_EVENT_STREAMING_STARTED then
        on_stream_started()
    elseif event == obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED then
        on_stream_stopped()
    end
end

function script_description()
    return DESCRIPTION
end

function script_load(settings)
    obs.obs_frontend_add_event_callback(on_event)
end

function script_unload()
    obs.obs_frontend_remove_event_callback(on_event)
end

function script_properties()
    local props = obs.obs_properties_create()
    
    local notifications_props = obs.obs_properties_create()
    obs.obs_properties_add_text(notifications_props, "start_msg", "Start Message", obs.OBS_TEXT_MULTILINE)
    obs.obs_properties_add_text(notifications_props, "stop_msg", "Stop Message", obs.OBS_TEXT_MULTILINE)
    obs.obs_properties_add_int(notifications_props, "start_delay", "Start Notification Delay (sec)", 0, 300, 1)
    obs.obs_properties_add_bool(notifications_props, "enable_start", "Stream Start")
    obs.obs_properties_add_bool(notifications_props, "enable_stop", "Stream Stop")
    obs.obs_properties_add_bool(notifications_props, "enable_preview", "Use Preview")
    obs.obs_properties_add_bool(notifications_props, "enable_delete_start_msg", "Delete Start Message on Stop")
    obs.obs_properties_add_group(props, "notifications_group", "Notifications", obs.OBS_GROUP_NORMAL, notifications_props)

    local tg_props = obs.obs_properties_create()
    obs.obs_properties_add_text(tg_props, "tg_bot_token", "Bot Token", obs.OBS_TEXT_PASSWORD)
    obs.obs_properties_add_text(tg_props, "tg_chat_id", "Chat ID", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_group(props, "tg_config_group", "Telegram", obs.OBS_GROUP_NORMAL, tg_props)


    local twitch_props = obs.obs_properties_create()
    obs.obs_properties_add_text(twitch_props, "twitch_client_id", "Client ID", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(twitch_props, "twitch_client_secret", "Client Secret", obs.OBS_TEXT_PASSWORD)
    obs.obs_properties_add_text(twitch_props, "twitch_channel", "Channel", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_group(props, "twitch_group", "Twitch (optional)", obs.OBS_GROUP_NORMAL, twitch_props)

    local testing_props = obs.obs_properties_create()
    obs.obs_properties_add_button(testing_props, "btn_test_start", "Test Stream Start", test_stream_start)
    obs.obs_properties_add_button(testing_props, "btn_test_stop", "Test Stream Stop", test_stream_stop)
    obs.obs_properties_add_group(props, "testing_group", "Testing", obs.OBS_GROUP_NORMAL, testing_props)

    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "start_msg", DEFAULT_START_MSG)
    obs.obs_data_set_default_string(settings, "stop_msg", DEFAULT_STOP_MSG)
    obs.obs_data_set_default_int(settings, "start_delay", DEFAULT_START_DELAY)
    obs.obs_data_set_default_bool(settings, "enable_start", DEFAULT_ENABLE_START)
    obs.obs_data_set_default_bool(settings, "enable_stop", DEFAULT_ENABLE_STOP)
    obs.obs_data_set_default_bool(settings, "enable_preview", DEFAULT_ENABLE_PREVIEW)
    obs.obs_data_set_default_bool(settings, "enable_delete_start_msg", DEFAULT_ENABLE_DELETE_START_MSG)
    obs.obs_data_set_default_string(settings, "tg_bot_token", DEFAULT_TG_BOT_TOKEN)
    obs.obs_data_set_default_string(settings, "tg_chat_id", DEFAULT_TG_CHAT_ID)
    obs.obs_data_set_default_string(settings, "twitch_client_id", DEFAULT_TWITCH_CLIENT_ID)
    obs.obs_data_set_default_string(settings, "twitch_client_secret", DEFAULT_TWITCH_CLIENT_SECRET)
    obs.obs_data_set_default_string(settings, "twitch_channel", DEFAULT_TWITCH_CHANNEL)
end

function script_update(settings)
    start_msg = obs.obs_data_get_string(settings, "start_msg")
    stop_msg = obs.obs_data_get_string(settings, "stop_msg")
    start_delay = obs.obs_data_get_int(settings, "start_delay")
    enable_start = obs.obs_data_get_bool(settings, "enable_start")
    enable_stop = obs.obs_data_get_bool(settings, "enable_stop")
    enable_preview = obs.obs_data_get_bool(settings, "enable_preview")
    enable_delete_start_msg = obs.obs_data_get_bool(settings, "enable_delete_start_msg")
    tg_bot_token = obs.obs_data_get_string(settings, "tg_bot_token")
    tg_chat_id = obs.obs_data_get_string(settings, "tg_chat_id")
    twitch_client_id = obs.obs_data_get_string(settings, "twitch_client_id")
    twitch_client_secret = obs.obs_data_get_string(settings, "twitch_client_secret")
    twitch_channel = obs.obs_data_get_string(settings, "twitch_channel")
end
