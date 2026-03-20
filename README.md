# openclaw-install-scripts

One-command [OpenClaw](https://openclaw.dev) setup for VPS hosts.

Installs OpenClaw, connects it to Telegram, and configures your LLM provider.
No code agent (Codex / Claude Code) is installed — just the gateway and Telegram binding.

## Supported providers

| VPS / Cloud | Folder | Status |
|---|---|---|
| DigitalOcean (Ubuntu 22.04 / 24.04) | [`vps/digitalocean/`](vps/digitalocean/) | ✅ Stable |

More providers coming. PRs welcome.

## What gets installed

- **OpenClaw gateway** — the local agent runtime
- **Telegram channel** — bot token + pairing + group/topic binding
- **LLM provider** — OpenAI, Anthropic, or OpenRouter (your choice)

## What does NOT get installed

- Code agents (Codex, Claude Code) — this is the base install only
- Any workspace or agent profile files

## Quick start

Pick your VPS provider from the table above and follow the README inside that folder.

## Requirements

- Fresh Ubuntu 22.04 or 24.04 droplet (root or sudo user)
- A Telegram bot token ([create one via @BotFather](https://t.me/BotFather))
- An API key for at least one LLM provider (OpenAI / Anthropic / OpenRouter)

## License

MIT — see [LICENSE](LICENSE).
