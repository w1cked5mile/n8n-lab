# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

**Windows (run PowerShell as Administrator):**
```powershell
powershell -ExecutionPolicy Bypass -File .\build-n8nWSL.ps1
```

**Linux (Ubuntu/Debian):**
```bash
sudo ./build-n8nLinux.sh
```

## Prerequisites

- Windows 11 with WSL 0.67+ (`wsl --install`)
- PowerShell 7+ running as Administrator
- Internet access (downloads Ubuntu and Docker packages)

## What the Scripts Do

Both scripts provision the same n8n instance running in Docker:
- `build-n8nWSL.ps1` — creates a new Ubuntu WSL distribution, installs Docker inside it, creates `C:\wsl\n8n_lab` for persistent data, and launches n8n
- `build-n8nLinux.sh` — installs Docker if missing (apt-based systems), creates `/opt/n8n_lab/n8n_data`, and launches the same n8n container configuration
