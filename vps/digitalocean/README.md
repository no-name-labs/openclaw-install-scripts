# OpenClaw on DigitalOcean

Install OpenClaw on a fresh DigitalOcean droplet in one command.

## Requirements

- Ubuntu 22.04 or 24.04 droplet (1 GB RAM minimum, 2 GB recommended)
- Root or sudo access
- A Telegram bot token — get one from [@BotFather](https://t.me/BotFather)
- An API key for at least one of: OpenAI, Anthropic, or OpenRouter

---

## Step 1 — Create a droplet

Recommended spec: **1 vCPU / 2 GB RAM / 50 GB SSD** (Basic, ~$12/mo).

Any Ubuntu 22.04 or 24.04 image works. Enable a firewall if needed — OpenClaw
only needs outbound internet access, no inbound ports are required.

---

## Step 2 — SSH into the droplet

```bash
ssh root@YOUR_DROPLET_IP
```

---

## Step 3 — Run the installer

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/openclaw-vps/main/vps/digitalocean/install.sh)
```

The script will walk you through:

1. Installing system dependencies and Node.js
2. Installing OpenClaw via npm
3. Choosing your LLM provider and entering your API key
4. Setting up your Telegram bot token
5. Pairing the bot with your Telegram account
6. Choosing where the bot should reply (group topic or direct chat)

At the end the script prints a summary with your gateway status and access token.

---

## Non-interactive install

Pre-set environment variables to skip all prompts:

```bash
export RUNTIME_PROVIDER=openai          # openai | anthropic | openrouter
export OPENAI_API_KEY=sk-...            # or ANTHROPIC_API_KEY / OPENROUTER_API_KEY
export TELEGRAM_BOT_TOKEN=123456:ABC...
export BIND_MODE=topic                  # topic | direct
export BIND_TELEGRAM_LINK=https://t.me/c/1234567890/2   # topic link
export AUTO_CONFIRM=true
export NON_INTERACTIVE=true

bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/openclaw-vps/main/vps/digitalocean/install.sh)
```

---

## After install

- Send a message to your bot in Telegram to verify it's responding.
- OpenClaw gateway runs as a background process. It auto-starts on reboot via cron
  (added by the installer).
- Logs: `~/.openclaw/logs/gateway-run.log`

### Useful commands

```bash
openclaw gateway status     # check if the gateway is running
openclaw gateway restart    # restart the gateway
openclaw health --json      # full health probe
```

---

## Uninstall

```bash
openclaw gateway stop
sudo npm uninstall -g openclaw
rm -rf ~/.openclaw
```
