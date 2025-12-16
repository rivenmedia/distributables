#!/usr/bin/env bash

# Jellyfin Media Server install helper for the Riven LXC.
#
# This file is intended to be sourced by proxmox/riven-install.sh via:
#   source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/rivenmedia/distributables/main/proxmox/media-jellyfin.sh)"
#
# It assumes the following are already available in the environment:
#   - msg_info/msg_ok/msg_error functions (from tteck install.func)
#   - CTTYPE, PCT_OSTYPE, STD (optional), etc.
#
# It MUST NOT call exit; instead it should return non-zero on error so the
# caller can decide whether to continue.

install_jellyfin_media_server() {
	  local APT_STD="${STD:-}"
	  local INSTALL_SCRIPT="/tmp/jellyfin-install-debuntu.sh"

	  # Ensure curl is available (normally installed earlier, but be safe).
	  if ! command -v curl >/dev/null 2>&1; then
	    msg_info "Installing curl for Jellyfin installer"
	    if ! ${APT_STD} apt-get install -y curl; then
	      msg_error "Failed to install curl; skipping Jellyfin installation"
	      return 1
	    fi
	  fi

	  msg_info "Downloading official Jellyfin installer script"
	  if ! curl -fsSL https://repo.jellyfin.org/install-debuntu.sh -o "${INSTALL_SCRIPT}"; then
	    msg_error "Failed to download Jellyfin installer script; skipping Jellyfin installation"
	    return 1
	  fi

	  msg_info "Running official Jellyfin installer script"
	  if ! SKIP_CONFIRM=true bash "${INSTALL_SCRIPT}" >/dev/null 2>&1; then
	    msg_error "Jellyfin installer script failed; skipping Jellyfin installation"
	    rm -f "${INSTALL_SCRIPT}"
	    return 1
	  fi
	  rm -f "${INSTALL_SCRIPT}"

	  # Best-effort hardware acceleration tweaks (optional).
	  msg_info "Setting up Jellyfin hardware acceleration packages"
	  if ! ${APT_STD} apt-get -y install va-driver-all ocl-icd-libopencl1 intel-opencl-icd vainfo intel-gpu-tools; then
	    msg_error "Failed to install Jellyfin GPU/VAAPI packages (continuing without hardware acceleration)"
	  else
	    if [[ "${CTTYPE:-1}" == "0" && -d /dev/dri ]]; then
	      chgrp video /dev/dri || true
	      chmod 755 /dev/dri || true
	      chmod 660 /dev/dri/* 2>/dev/null || true
	      ${APT_STD} adduser "$(id -u -n)" video || true
	      ${APT_STD} adduser "$(id -u -n)" render || true
	    fi
	    msg_ok "Set up Jellyfin hardware acceleration packages"
	  fi

	  # Ensure permissions are sane; installer already does this, so best-effort.
		  chown -R jellyfin:adm /etc/jellyfin 2>/dev/null || true
		  systemctl restart jellyfin 2>/dev/null || true

		  # Ensure Jellyfin can read Riven's VFS by joining the riven group if it exists.
		  if getent group riven >/dev/null 2>&1; then
		    usermod -aG riven jellyfin 2>/dev/null || true
		  fi
	
		  msg_ok "Installed Jellyfin Media Server"
}

