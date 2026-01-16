# OBS Telegram Stream Alerts

Send Telegram notifications when your OBS stream starts and stops.

## Overview

**OBS Telegram Stream Alerts** is a lightweight Lua script for OBS Studio that automatically sends notifications to a Telegram chat when you start or stop streaming. Get instant alerts on your phone, desktop, or any device with Telegram installed.

### Features

-  **Stream Start Notifications** - Get notified when your stream goes live
-  **Stream Stop Notifications** - Know when your stream ends
-  **Customizable Messages** - Define your own notification templates
-  **Auto-Delete Start Messages** - Optionally remove start notifications when stream ends
-  **Secure Configuration** - Credentials stored using OBS's encrypted settings

## Prerequisites

- **OBS Studio** 27.0 or later
- **curl** command-line tool (pre-installed on Windows 10+, macOS, modern Linux)
- **Telegram Bot** - Create a bot via [@BotFather](https://t.me/botfather) on Telegram
- **Telegram Chat ID** - Get your chat ID from [@userinfobot](https://t.me/userinfobot)

## Installation

1. Download \obs-telegram-alerts.lua\ from the [latest release](https://github.com/your-repo/obs-telegram-stream-alerts/releases)
2. Place the file in your OBS scripts folder:
   - **Windows**: \%APPDATA%\obs-studio\scripts\
   - **macOS**: \~/Library/Application Support/obs-studio/scripts/\
   - **Linux**: \~/.config/obs-studio/scripts/\
3. In OBS, go to **Tools  Scripts**
4. Click the **+** button and select \obs-telegram-alerts.lua\
5. The script will appear in the Scripts panel

## Basic Setup

### Step 1: Create a Telegram Bot

1. Open Telegram and search for [@BotFather](https://t.me/botfather)
2. Send \/newbot\ and follow the prompts
3. Copy the **bot token** (looks like \123456789:ABCdefGHIjklMNOpqrsTUVwxyz\)

### Step 2: Get Your Chat ID

1. Search for [@userinfobot](https://t.me/userinfobot) on Telegram
2. Start a conversation - it will reply with your **Chat ID** (a number)
3. Copy this Chat ID

### Step 3: Configure the Script

Configuration details will be documented in future updates as additional features are implemented.

**Note:** Detailed configuration instructions for message templates, Twitch integration, and advanced features will be added in subsequent releases.

## Version

Current version: **1.0.0**

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: Report bugs or request features via [GitHub Issues](https://github.com/your-repo/obs-telegram-stream-alerts/issues)
- **Documentation**: Check the [docs](docs/) folder for architecture and development details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

**Made with  for the streaming community**
