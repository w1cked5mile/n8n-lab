# n8n WSL Lab Setup

Automates provisioning of paired Ubuntu WSL distributions (server and desktop) and deploys an n8n automation instance running in Docker.

## Prerequisites
- Windows 11 with WSL installed (`wsl --install`)
- PowerShell 7 or Windows PowerShell running **as Administrator**
- Internet access to download Ubuntu and Docker packages
- WSL version 0.67 or newer to support systemd

## Usage
1. Clone or download this repository.
2. Open an elevated PowerShell session in the repository root.
3. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\build-n8nWSL.ps1
   ```

The script performs these steps:
- Creates `C:\wsl\n8n_lab` for artifacts and persistent data.
- Detects the latest Ubuntu LTS release and downloads the matching rootfs.
- Imports two WSL distributions: `Ubuntu-n8n-server` and `Ubuntu-n8n-desktop`.
- Enables systemd in both distributions and restarts WSL.
- Installs Docker on the server instance and launches the `n8nio/n8n` container bound to port `5678`.
- Mounts persistent workflow data at `C:\wsl\n8n_lab\n8n_data` (available inside WSL as `/home/node/.n8n`).
- Installs `ubuntu-desktop-minimal` within the desktop instance for WSLg scenarios.

## Post-Installation
- Access the automation UI at http://localhost:5678/
- Connect to the server distro with `wsl -d Ubuntu-n8n-server`.
- Verify persistence via `ls -la /mnt/c/wsl/n8n_lab/n8n_data` inside WSL.

## Updating n8n
Re-run the script to relaunch the container with the latest `n8nio/n8n` image. The bind-mounted `n8n_data` directory preserves workflows and credentials across upgrades.

## Removal
To remove the environment:
1. Stop and unregister the WSL instances:
   ```powershell
   wsl --shutdown
   wsl --unregister Ubuntu-n8n-server
   wsl --unregister Ubuntu-n8n-desktop
   ```
2. Optionally delete `C:\wsl\n8n_lab`.

## Troubleshooting
- If the script reports `failed to bind host port 0.0.0.0:5678`, stop or remove any existing `n8n` container (including one launched by Docker Desktop) so the host port is free, then rerun the script.
- When rerunning after a failed attempt, remove the existing container inside the server distro with `sudo docker rm -f n8n` to avoid name conflicts.
