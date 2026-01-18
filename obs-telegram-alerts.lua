-- ============================================================================
-- OBS Telegram Stream Alerts
-- Version: 1.0.0
-- Description: Send Telegram notifications when OBS streaming starts/stops
-- ============================================================================

obs = obslua

VERSION = "1.0.0"

local tg_config = {
    bot_token = "",
    chat_id = "",
    status = "⚪ Not Configured",
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
    status = "⚪ Not Configured"
}

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

function script_properties()
    local props = obs.obs_properties_create()
    
    local tg_props = obs.obs_properties_create()
    obs.obs_properties_add_text(tg_props, "bot_token", "Bot Token", obs.OBS_TEXT_PASSWORD)
    obs.obs_properties_add_text(tg_props, "chat_id", "Chat ID", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_group(props, "tg_group", "Telegram", obs.OBS_GROUP_NORMAL, tg_props)
    
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
    obs.obs_data_set_default_string(settings, "bot_token", "")
    obs.obs_data_set_default_string(settings, "chat_id", "")
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
    tg_config.bot_token = obs.obs_data_get_string(settings, "bot_token")
    tg_config.chat_id = obs.obs_data_get_string(settings, "chat_id")
end

function script_load(settings)
    obs.obs_frontend_add_event_callback(on_event)
end

function script_unload()
    obs.obs_frontend_remove_event_callback(on_event)
end
