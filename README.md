# OBS Telegram Stream Alerts

Send automated Telegram notifications when your OBS stream starts and stops, with optional Twitch metadata integration.

## Overview

**OBS Telegram Stream Alerts** is a zero-dependency Lua script for OBS Studio that automatically sends rich notifications to Telegram when you start or stop streaming. Stay connected with your community through instant alerts on any device with Telegram installed.

### Features

#### Core Notifications
- 🔴 **Stream Start Notifications** - Automated alerts when you go live
- ⚫ **Stream Stop Notifications** - Automatic end-of-stream messages
- ✏️ **Customizable Message Templates** - Full HTML formatting support with placeholders
- 🗑️ **Auto-Delete Start Messages** - Optionally clean up start notifications when stream ends
- ⚙️ **Enable/Disable Toggles** - Independent control for start and stop notifications
- 🧪 **Manual Testing Interface** - Test buttons to verify configuration without going live

#### Twitch Integration (Optional)
- 🎮 **Stream Metadata** - Automatically include stream title, category, and viewer count
- 🖼️ **Preview Thumbnails** - Send stream previews as photos with captions
- 🔄 **Smart Placeholders** - `{stream_title}`, `{category}`, `{viewer_count}`
- ⚡ **Token Caching** - Efficient OAuth token management (60-day lifetime)
- 📊 **Live Data** - Fetch metadata at stream start and stop for accurate stats

#### Configuration & Validation
- ✅ **Credential Validation** - One-click verification of bot token and chat ID
- 🔒 **Secure Storage** - Credentials encrypted by OBS settings API
- 📍 **Status Indicators** - Real-time visual feedback with emoji status
- 🌐 **Cross-Platform** - Windows, macOS, and Linux support

## Prerequisites

- **OBS Studio** 27.0 or later
- **curl** command-line tool (pre-installed on Windows 10+, macOS, and modern Linux distributions)
- **Telegram Bot Token** - Create a bot via [@BotFather](https://t.me/botfather) on Telegram
- **Telegram Chat ID** - Get your chat or channel ID
- **(Optional) Twitch App Credentials** - For metadata integration ([register here](https://dev.twitch.tv/console/apps))

## Installation

1. Download `obs-telegram-alerts.lua` from the [latest release](https://github.com/your-repo/obs-telegram-stream-alerts/releases)
2. In OBS, go to **Tools → Scripts**
3. Click the **+** button and select `obs-telegram-alerts.lua`
4. The script will appear in the Scripts panel

**Optional**: You can also place the file in your OBS scripts folder for automatic loading:
   - **Windows**: `%APPDATA%\obs-studio\scripts\`
   - **macOS**: `~/Library/Application Support/obs-studio/scripts/`
   - **Linux**: `~/.config/obs-studio/scripts/`

## Quick Start Guide

### Step 1: Create a Telegram Bot

1. Open Telegram and search for [@BotFather](https://t.me/botfather)
2. Send `/newbot` and follow the prompts
3. Copy the **Bot Token** (looks like `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

### Step 2: Get Your Chat ID

**For personal messages:**
1. Search for [@userinfobot](https://t.me/userinfobot) on Telegram
2. Start a conversation - it will reply with your **Chat ID** (a number like `123456789`)

**For channels:**
1. Add your bot as an administrator to the channel
2. The Chat ID is your channel username with `@` (e.g., `@mychannel`) or numeric ID (e.g., `-1001234567890`)

**For groups:**
1. Add your bot to the group
2. Use [@userinfobot](https://t.me/userinfobot) in the group to get the group's Chat ID

### Step 3: Configure the Script in OBS

1. In OBS Scripts panel, select **OBS Telegram Stream Alerts**
2. Under **Telegram** section:
   - Enter your **Bot Token**
   - Enter your **Chat ID**
   - Click **Validate** to verify credentials
   - ✅ You should see "Bot Connected: @yourbotname | Chat Found: YourChat"

3. Under **Notifications** section:
   - Check **Stream Start** to enable start notifications
   - Check **Stream Stop** to enable stop notifications
   - Customize **Start Message** and **Stop Message** templates (optional)
   - Set **Start Notification Delay** (0-300 seconds, default 0, recommend 30 for Twitch previews)
   - Check **Delete Start Message on Stop** if you want clean chat history (optional)

4. Click **Test Stream Start** to verify your configuration

### Step 4: Customize Your Messages (Optional)

Use HTML formatting and placeholders in your message templates:

**Default Start Message:**
```
🔴 <i>Stream started:</i> {stream_title}
Now playing <b>{category}</b>
```

**Default Stop Message:**
```
⚪ <i>Stream offline:</i> {stream_title}
Thanks to all <code>{viewer_count}</code> viewers for watching!
```

**Supported HTML Tags:**
- `<b>bold</b>` - **bold text**
- `<i>italic</i>` - *italic text*
- `<code>code</code>` - `monospace text`
- `<a href="url">link</a>` - hyperlinks

**Available Placeholders** (requires Twitch integration):
- `{stream_title}` - Stream title from Twitch
- `{category}` - Game/category being played
- `{viewer_count}` - Current viewer count (displays as plain number)

**Stream Preview**: When Twitch integration is configured, stream thumbnails are automatically sent as photo attachments with your message as the caption. No placeholder needed!

---

## Advanced: Twitch Integration

Add rich stream metadata to your notifications by connecting your Twitch account.

### Step 1: Register a Twitch Application

1. Go to [Twitch Developer Console](https://dev.twitch.tv/console/apps)
2. Click **Register Your Application**
3. Fill in:
   - **Name**: Any name (e.g., "OBS Telegram Alerts")
   - **OAuth Redirect URLs**: `http://localhost` (required but not used)
   - **Category**: Choose "Application Integration"
4. Click **Create**
5. Copy your **Client ID**
6. Click **New Secret** and copy the **Client Secret**

### Step 2: Configure Twitch in OBS Script

1. In OBS Scripts panel, under **Twitch (optional)** section:
   - Enter your **Client ID**
   - Enter your **Client Secret**
   - Enter your **Channel Name** (your Twitch username)
   - Click **Validate** to verify credentials
   - ✅ You should see "Connected: yourchannelname"

2. Update your message templates to use placeholders:
   ```
   🔴 Now live: {stream_title}
   Playing {category} with {viewer_count} viewers
   ```

3. Set **Start Notification Delay** to 30 seconds (recommended for reliable Twitch previews)

4. When you stream, notifications will automatically include:
   - Your current stream title
   - The game/category you're playing
   - Live viewer count (plain number format)
   - Stream preview thumbnail (as photo attachment with caption)

### Troubleshooting Twitch Integration

- **"Auth Failed"**: Double-check your Client ID and Client Secret
- **"Channel Offline"**: This is normal when not streaming - metadata will work when live
- **"Channel Not Found"**: Verify your Twitch username is correct
- **Placeholders empty**: Metadata only available when Twitch integration is configured and stream is live

---

## Configuration Reference

### Telegram Section
| Setting | Description | Required |
|---------|-------------|----------|
| Bot Token | Your Telegram bot token from @BotFather | ✅ Yes |
| Chat ID | Target chat/channel/group ID | ✅ Yes |
| Validate Button | Verifies bot token and chat access | - |
| Status | Shows connection status with visual indicators | - |

### Notifications Section
| Setting | Description | Default |
|---------|-------------|---------|
| Start Message | Template for stream start notifications | See above |
| Stop Message | Template for stream stop notifications | See above |
| Start Notification Delay (sec) | Delay before sending start notification (0-300s) | 0 (immediate) |
| Preview URL | Custom preview image URL (optional, overridden by Twitch) | Empty |
| Stream Start | Enable/disable start notifications | ❌ Disabled |
| Stream Stop | Enable/disable stop notifications | ❌ Disabled |
| Delete Start Message on Stop | Remove start notification when stream ends | ❌ Disabled |

### Twitch (Optional) Section
| Setting | Description | Required |
|---------|-------------|----------|
| Client ID | Twitch application client ID | Optional |
| Client Secret | Twitch application client secret | Optional |
| Channel Name | Your Twitch username | Optional |
| Validate Button | Verifies Twitch credentials | - |
| Status | Shows Twitch connection status | - |

### Testing Section
| Button | Description |
|--------|-------------|
| Test Stream Start | Manually trigger start notification (for testing) |
| Test Stream Stop | Manually trigger stop notification (for testing) |

---

## Security & Privacy

- ✅ **Encrypted Storage**: Bot tokens and secrets are stored using OBS's encrypted settings API
- ✅ **No External Dependencies**: Zero third-party Lua libraries - uses only system curl
- ✅ **HTTPS Only**: All API communication uses secure HTTPS connections
- ✅ **Local Processing**: No data sent to external services except Telegram and Twitch APIs
- ✅ **Input Validation**: All user inputs are validated and sanitized
- ⚠️ **Platform Limitation**: Bot tokens visible in process list when curl executes (OS-level limitation)

---

## Troubleshooting

### "Telegram API error (401): Unauthorized"
- Your bot token is invalid or expired
- Regenerate token via @BotFather and update in settings

### "Chat Not Found"
- Bot is not added to the channel/group, or
- Chat ID format is incorrect (use `@` for public channels, numeric ID for private)
- For groups: Ensure bot is a member

### "Failed to send Telegram message: network timeout"
- Check your internet connection
- Verify curl is installed: Run `curl --version` in terminal
- Check firewall settings

### Notifications not sending
1. Verify **Stream Start** / **Stream Stop** checkboxes are enabled
2. Click **Validate** to ensure credentials are correct
3. Use **Test Stream Start** button to verify configuration
4. Check OBS log file (Help → Log Files → View Current Log) for error messages

### Twitch metadata not appearing
1. Ensure Twitch section is fully configured (Client ID, Client Secret, Channel Name)
2. Click **Validate** in Twitch section
3. Metadata only available when you're actually streaming on Twitch
4. Check that placeholders are spelled correctly in message templates

---

## FAQ

**Q: Do I need to be streaming on Twitch to use this?**  
A: No! Twitch integration is completely optional. Basic notifications work with any OBS stream.

**Q: Can I send notifications to multiple chats?**  
A: Not currently. v1.0 supports one bot/chat configuration. Multi-channel support is planned for future releases.

**Q: Does this work with OBS Studio on Linux?**  
A: Yes! Tested on Windows 10+, macOS 13+, and Linux (Ubuntu 22.04).

**Q: Will this slow down OBS or affect stream performance?**  
A: No. The script has minimal memory footprint (<5MB) and doesn't impact stream encoding.

**Q: Can I use emojis in my messages?**  
A: Yes! Full UTF-8 emoji support in message templates.

**Q: What happens if Telegram is down when I start streaming?**  
A: The script logs an error but doesn't interrupt your stream. OBS continues normally.

---

## Technical Details

- **Language**: Lua 5.2 (LuaJIT via OBS)
- **Dependencies**: None (uses system curl)
- **File Size**: <100KB (single `.lua` file)
- **Memory**: <5MB footprint
- **APIs**: Telegram Bot API, Twitch Helix API (optional)
- **License**: MIT

---

## Version

**Current version: 1.0.0**

See [CHANGELOG](docs/CHANGELOG.md) for release history.

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup

1. Clone the repository
2. Review [Architecture Documentation](docs/architecture.md)
3. Check [Coding Standards](docs/architecture/coding-standards.md)
4. See [Story Documentation](docs/stories/) for implementation details

---

## Support

- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/your-repo/obs-telegram-stream-alerts/issues)
- 💡 **Feature Requests**: [GitHub Discussions](https://github.com/your-repo/obs-telegram-stream-alerts/discussions)
- 📚 **Documentation**: [docs/](docs/) folder
- 🏗️ **Architecture**: [docs/architecture/](docs/architecture/)

---

## Roadmap

Planned features for future releases:
- 📢 Multi-channel notifications
- 🌍 Internationalization (i18n)
- 🔄 Retry logic with exponential backoff
- 🎨 Custom emoji sets
- 📊 YouTube Live metadata integration
- 🪝 Webhook-based Twitch events

See [Future Enhancements](docs/architecture/future-enhancements-out-of-scope-for-v10.md) for details.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Made with ❤️ for the streaming community**
