# Docker Images

## Images

| Dockerfile | Base | What it adds | Built image |
|---|---|---|---|
| `Dockerfile.claude` | `ubuntu:24.04` | Go, Node.js 20, gh CLI, dev utils, Claude Code, [GSD](https://github.com/gsd-build/get-shit-done) | `claude:latest` |
| `Dockerfile.claude.evm` | `claude:latest` | Foundry (forge/cast/anvil), Hardhat | `claude-evm:latest` |

Layer chain: `ubuntu:24.04` → `claude` → `claude-evm`. Each image reuses cached layers from its base.

## Build

```bash
# Base image (Go + Claude Code)
docker build -t claude:latest -f Dockerfile.claude .

# EVM image (Foundry + Hardhat)
docker build -t claude-evm:latest -f Dockerfile.claude.evm .
```


## Run

Interactive login (`claude login`) won't work inside Docker — pasting the auth token fails within the Claude process (Claude-specific input handling issue; paste works fine in the container shell). Use environment variables instead:

```bash
# Generate token on host first:  claude setup-token
# Then pass it to the container (OAuth token requires -p mode, not interactive claude)
docker run --rm -it -e CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN claude \
  claude -p "your prompt" --allowedTools "Read,Edit,Bash"
```

Useful commands:

```bash
docker run -it --name claude -v $(pwd):/workspace claude bash
docker run -it --name claude -v $(pwd):/workspace claude claude --dangerously-skip-permissions
docker start -ai claude                           # re-attach (volume already set from docker run)
docker run --rm -it claude bash
docker run --rm claude-evm:latest forge --version
docker run --rm claude-evm:latest npx hardhat --version
```