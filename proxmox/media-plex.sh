#!/usr/bin/env bash

# Plex Media Server install helper for the Riven LXC.
#
# This file is intended to be sourced by proxmox/riven-install.sh via:
#   source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/rivenmedia/distributables/main/proxmox/media-plex.sh)"
#
# It assumes the following are already available in the environment:
#   - msg_info/msg_ok/msg_error functions (from tteck install.func)
#   - CTTYPE, STD (optional), etc.
#
# It MUST NOT call exit; instead it should return non-zero on error so the
# caller can decide whether to continue.

install_plex_media_server() {
  local APT_STD="${STD:-}"

  msg_info "Installing Plex Media Server dependencies"
  if ! ${APT_STD} apt-get install -y curl sudo mc gpg; then
    msg_error "Failed to install Plex dependencies; skipping Plex installation"
    return 1
  fi
  msg_ok "Installed Plex Media Server dependencies"

  msg_info "Setting up Plex hardware acceleration packages"
  if ! ${APT_STD} apt-get -y install va-driver-all ocl-icd-libopencl1 intel-opencl-icd vainfo intel-gpu-tools; then
    msg_error "Failed to install Plex GPU/VAAPI packages (continuing without hardware acceleration)"
  else
    if [[ "${CTTYPE:-1}" == "0" && -d /dev/dri ]]; then
      chgrp video /dev/dri || true
      chmod 755 /dev/dri || true
      chmod 660 /dev/dri/* 2>/dev/null || true
      ${APT_STD} adduser "$(id -u -n)" video || true
      ${APT_STD} adduser "$(id -u -n)" render || true
    fi
    msg_ok "Set up Plex hardware acceleration packages"
  fi

  msg_info "Setting up Plex Media Server repository"
  if ! curl -fsSL https://downloads.plex.tv/plex-keys/PlexSign.key \
    >/usr/share/keyrings/PlexSign.asc; then
    msg_error "Failed to download Plex signing key; skipping Plex installation"
    return 1
  fi
  if ! echo "deb [signed-by=/usr/share/keyrings/PlexSign.asc] https://downloads.plex.tv/repo/deb/ public main" \
    >/etc/apt/sources.list.d/plexmediaserver.list; then
    msg_error "Failed to configure Plex apt source; skipping Plex installation"
    return 1
  fi
  msg_ok "Configured Plex Media Server repository"

  msg_info "Installing Plex Media Server"
  if ! ${APT_STD} apt-get update; then
    msg_error "apt-get update failed before Plex installation; skipping Plex"
    return 1
  fi
  if ! ${APT_STD} apt-get -o Dpkg::Options::="--force-confold" install -y plexmediaserver; then
    msg_error "Failed to install Plex Media Server package"
    return 1
  fi

  # Adjust ssl-cert/render groups for Plex (best-effort, do not fail install).
  if [[ "${CTTYPE:-1}" == "0" ]]; then
    sed -i -e 's/^ssl-cert:x:104:plex$/render:x:104:root,plex/' \
      -e 's/^render:x:108:root$/ssl-cert:x:108:plex/' /etc/group 2>/dev/null || true
  else
    sed -i -e 's/^ssl-cert:x:104:plex$/render:x:104:plex/' \
      -e 's/^render:x:108:$/ssl-cert:x:108:/' /etc/group 2>/dev/null || true
  fi

	  # Ensure Plex can read Riven's VFS by joining the riven group if it exists.
	  if getent group riven >/dev/null 2>&1; then
	    usermod -aG riven plex 2>/dev/null || true
	  fi

  msg_ok "Installed Plex Media Server"
}

