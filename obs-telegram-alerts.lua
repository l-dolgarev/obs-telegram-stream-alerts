-- ============================================================================
-- OBS Telegram Stream Alerts
-- Version: 1.0.0
-- Description: Send Telegram notifications when OBS streaming starts/stops
-- ============================================================================

obs = obslua

VERSION = "1.0.0"

-- ============================================================================
-- CONFIGURATION TABLES
-- ============================================================================

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

-- ============================================================================
-- OBS INTEGRATION LAYER
-- ============================================================================

function script_description()
    return [[<b>OBS Telegram Stream Alerts</b> v]] .. VERSION .. [[<br>
<br>
Send Telegram notifications when your stream starts and stops.<br>
<br>
<i>Configure your Telegram bot credentials and message templates below.</i>]]
end

function script_properties()
    local props = obs.obs_properties_create()
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
        obs.script_log(obs.LOG_ERROR, "Streaming started")
    elseif event == obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED then
        obs.script_log(obs.LOG_ERROR, "Streaming stopped")
    end
end

function script_load(settings)
    obs.obs_frontend_add_event_callback(on_event)
end

function script_unload()
    obs.obs_frontend_remove_event_callback(on_event)
end
