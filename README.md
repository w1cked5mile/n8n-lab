# n8n WSL Lab Setup

Automates provisioning of an Ubuntu WSL distribution and deploys an n8n automation instance running in Docker.

## Prerequisites
- Windows 11 with WSL installed (`wsl --install`)
- PowerShell 7 or Windows PowerShell running **as Administrator**
- Internet access to download Ubuntu and Docker packages
- WSL version 0.67 or newer to support systemd

## Usage

### Windows 11 + WSL
1. Clone or download this repository.
2. Open an elevated PowerShell session in the repository root.
3. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\build-n8nWSL.ps1
   ```

### Linux workstation (Ubuntu/Debian)
1. Clone or download this repository.
2. Run the helper script with root privileges:
   ```bash
   sudo ./build-n8nLinux.sh
   ```
   The script installs Docker when missing (apt-based systems only), creates `/opt/n8n_lab/n8n_data`, and launches the same n8n container configuration.

The script performs these steps:
- Creates `C:\wsl\n8n_lab` for artifacts and persistent data.
- Detects the latest Ubuntu LTS release and downloads the matching rootfs.
- Imports a WSL distribution named `Ubuntu-n8n-server`.
- Enables systemd and restarts WSL so the setting takes effect.
- Installs Docker inside the distribution and launches the `n8nio/n8n` container bound to port `5678`.
- Mounts persistent workflow data at `C:\wsl\n8n_lab\n8n_data` (available inside WSL as `/home/node/.n8n`).

## Post-Installation
- Connect to the distro with `wsl -d Ubuntu-n8n-server`
- Verify persistence via `ls -la /mnt/c/wsl/n8n_lab/n8n_data` inside WSL
- Access the automation UI at http://localhost:5678/
- Register your account and request a free Community Edition license key from n8n.io
- Apply the license key and activate it

## Updating n8n
Re-run the appropriate script (`build-n8nWSL.ps1` or `build-n8nLinux.sh`) to relaunch the container with the latest `n8nio/n8n` image. The bind-mounted `n8n_data` directory preserves workflows and credentials across upgrades.

## Removal
To remove the environment:
1. Stop and unregister the WSL instance:
   ```powershell
   wsl --shutdown
   wsl --unregister Ubuntu-n8n-server
   ```
2. Optionally delete `C:\wsl\n8n_lab`.

For Linux workstations, stop and remove the Docker container with `docker rm -f n8n`, delete the persistent directory at `/opt/n8n_lab`, and optionally remove Docker if it was installed exclusively for this setup.

## Troubleshooting
- If the script reports `failed to bind host port 0.0.0.0:5678`, stop or remove any existing `n8n` container (including one launched by Docker Desktop) so the host port is free, then rerun the script.
- When rerunning after a failed attempt, remove the existing container inside the server distro with `sudo docker rm -f n8n` to avoid name conflicts.

