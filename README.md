# seedit

One-shot setup for a new seedbox user: Python, Playwright and VS Code. No root needed.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/srao-fox/seedit/main/setup-all.sh | bash
```

Or:

```bash
git clone https://github.com/srao-fox/seedit.git
bash seedit/setup-all.sh
```

## What you get

- **Python 3.12**, installed with [uv](https://github.com/astral-sh/uv), plus a virtualenv at `~/.venvs/main`
- **Playwright** with Chromium, plus `requests`, `httpx`, `beautifulsoup4`, `lxml` and `python-dotenv`
- **VS Code CLI**, with a Remote Tunnel running in tmux or screen

The script is safe to re-run, because it skips anything already installed.

## After install

```bash
source ~/.bashrc
tmux attach -t vscode     # first time: open the GitHub link, enter the code, then Ctrl+B, D
```

Then open **https://vscode.dev/tunnel/seedbox**. In VS Code, choose **Python: Select Interpreter** and enter `~/.venvs/main/bin/python`.

## Options

```bash
PY_VERSION=3.11 BROWSERS="chromium firefox" TUNNEL_NAME=mybox bash setup-all.sh
```

| Variable | Default |
|---|---|
| `PY_VERSION` | `3.12` |
| `VENV_DIR` | `~/.venvs/main` |
| `BROWSERS` | `chromium` |
| `EXTRA_PKGS` | `requests httpx beautifulsoup4 lxml python-dotenv` |
| `TUNNEL_NAME` | `seedbox` |

## Troubleshooting

- **Playwright fails to launch:** the script lists any missing system libraries. Ask your provider to install them, and always launch with `args=["--no-sandbox"]`.
- **`$'\r': command not found`:** run `sed -i 's/\r$//' setup-all.sh`.
- **The tunnel stopped:** re-run the script. It skips installs and restarts the tunnel.

## License

MIT
# seedit
