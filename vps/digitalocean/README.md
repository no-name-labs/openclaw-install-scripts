# OpenClaw on DigitalOcean

Install OpenClaw on a fresh DigitalOcean droplet in a few commands.
Connect to the UI from your local browser via SSH tunnel — no domain or open ports needed.

---

## Requirements

- Ubuntu 22.04 or 24.04 droplet (1 GB RAM minimum, 2 GB recommended)
- Root or sudo access
- A Telegram bot token — get one from [@BotFather](https://t.me/BotFather)
- An API key for at least one of: OpenAI, Anthropic, or OpenRouter

---

## Step 1 — Create a droplet

Go to [cloud.digitalocean.com](https://cloud.digitalocean.com) → **Create → Droplets**.

Recommended settings:
- **Region**: closest to you
- **Image**: Ubuntu 24.04 (LTS) x64
- **Size**: Basic — 1 vCPU / 2 GB RAM / 50 GB SSD (~$12/mo)
- **Authentication**: SSH key (recommended) or password
- Leave all other settings as default

Click **Create Droplet** and wait ~30 seconds.

<!-- screenshot: 01-create-droplet.png -->
> 📸 _Add screenshot: DigitalOcean droplet creation settings_

Once created, copy the droplet's **IPv4 address** from the dashboard.

<!-- screenshot: 02-droplet-ready.png -->
> 📸 _Add screenshot: Dashboard showing droplet IP_

---

## Step 2 — Connect via SSH

Open a terminal on your local machine:

```bash
ssh root@YOUR_DROPLET_IP
```

If you used a password instead of an SSH key, enter it when prompted.
You should see the Ubuntu welcome message.

<!-- screenshot: 03-ssh-connected.png -->
> 📸 _Add screenshot: Terminal connected to the droplet_

---

## Step 3 — Run the installer

Paste this single command and press Enter:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/no-name-labs/openclaw-install-scripts/main/vps/digitalocean/install.sh)
```

The installer runs 5 stages automatically:

| Stage | What happens |
|---|---|
| 1/5 | Installs system packages and Node.js |
| 2/5 | Installs OpenClaw via npm, starts the gateway |
| 3/5 | You choose your LLM provider and enter your API key |
| 4/5 | You enter your Telegram bot token, pair the bot, choose binding target |
| 5/5 | Startup cron installed, summary printed with gateway token |

<!-- screenshot: 04-install-running.png -->
> 📸 _Add screenshot: Installer stages running in terminal_

### LLM provider menu

When prompted, use ↑/↓ to select your provider and press Enter:

<!-- screenshot: 05-provider-menu.png -->
> 📸 _Add screenshot: Interactive provider selection menu_

### Telegram pairing

When the installer reaches Stage 4:

1. Open Telegram and find your bot (search for its username).
2. Press **Start** if you haven't chatted with it before.
3. Send any message — the bot will reply with a pairing request.
4. Return to the terminal and press **Enter** to approve.

<!-- screenshot: 06-telegram-pairing.png -->
> 📸 _Add screenshot: Telegram showing bot pairing message_

### Install summary

At the end the installer prints a summary including your gateway token.
**Copy and save the gateway token** — you'll need it to connect apps.

<!-- screenshot: 07-install-summary.png -->
> 📸 _Add screenshot: Final install summary with gateway token_

---

## Step 4 — Open the UI in your browser (SSH tunnel)

OpenClaw's UI runs on the droplet at `localhost:18789`.
An SSH tunnel forwards that port to your local machine — no domain or firewall changes needed.

**On your local machine** (new terminal tab, keep the droplet SSH session open):

```bash
ssh -L 18789:127.0.0.1:18789 root@YOUR_DROPLET_IP -N
```

The command will appear to hang — that's correct, the tunnel is running.

<!-- screenshot: 08-ssh-tunnel.png -->
> 📸 _Add screenshot: Tunnel command running in local terminal_

Now open your browser:

```
http://localhost:18789
```

You should see the OpenClaw UI.

<!-- screenshot: 09-openclaw-ui.png -->
> 📸 _Add screenshot: OpenClaw UI in the browser_

To stop the tunnel: press `Ctrl+C` in the terminal tab running the ssh command.

> **Tip — persistent tunnel via SSH config:**
> Add this to your `~/.ssh/config` to open the tunnel with a shorter alias:
> ```
> Host openclaw-vps
>     HostName YOUR_DROPLET_IP
>     User root
>     LocalForward 18789 127.0.0.1:18789
> ```
> Then run `ssh openclaw-vps -N` and access `http://localhost:18789`.

---

## Non-interactive install

Pre-set environment variables to skip all prompts — useful for scripting or re-installs:

```bash
export RUNTIME_PROVIDER=openai          # openai | anthropic | openrouter
export OPENAI_API_KEY=sk-...            # or ANTHROPIC_API_KEY / OPENROUTER_API_KEY
export TELEGRAM_BOT_TOKEN=123456:ABC...
export BIND_MODE=topic                  # topic | direct
export BIND_TELEGRAM_LINK=https://t.me/c/1234567890/2
export AUTO_CONFIRM=true
export NON_INTERACTIVE=true

bash <(curl -fsSL https://raw.githubusercontent.com/no-name-labs/openclaw-install-scripts/main/vps/digitalocean/install.sh)
```

---

## After install

- Send a message to your Telegram bot to verify it's responding.
- OpenClaw auto-starts on reboot via cron (added by the installer).
- Logs: `~/.openclaw/logs/gateway-run.log`

### Useful commands (run on the droplet)

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
crontab -l | grep -v "openclaw" | crontab -
```

---

## Screenshots

See the [`screenshots/`](screenshots/) folder for the full annotated walkthrough.
