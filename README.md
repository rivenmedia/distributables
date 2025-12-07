# Proxmox LXC Helper Script for Riven

On a Proxmox VE host, you can create a Debian 12, unprivileged LXC that runs the
Riven backend and frontend baremetal by running this command in the Proxmox
shell:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/rivenmedia/distributables/main/proxmox/riven.sh)"
```

The script will:

- Create a new unprivileged LXC (default: Debian 12, 4 vCPU, 8 GB RAM, 40 GB disk)
- Enable FUSE inside the container
- Install and configure PostgreSQL inside the LXC
- Install the Riven backend (Python/uv) and frontend (Node/pnpm) baremetal
- Create systemd services for both backend and frontend so they start on boot

After the script completes, you should be able to reach:

- Riven backend at: `http://<CT-IP>:8080`
- Riven frontend at: `http://<CT-IP>:3000`
