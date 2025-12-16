#!/usr/bin/env bash

# Emby Media Server install helper for the Riven LXC.
#
# This file is intended to be sourced by proxmox/riven-install.sh via:
#   source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/rivenmedia/distributables/main/proxmox/media-emby.sh)"
#
# It assumes the following are already available in the environment:
#   - msg_info/msg_ok/msg_error functions (from tteck install.func)
#   - CTTYPE, STD (optional), etc.
#
# It MUST NOT call exit; instead it should return non-zero on error so the
# caller can decide whether to continue.

install_emby_media_server() {
  local APT_STD="${STD:-}"

	  msg_info "Installing Emby Media Server dependencies"
	  if ! ${APT_STD} apt-get install -y curl sudo mc gpg jq; then
    msg_error "Failed to install Emby dependencies; skipping Emby installation"
    return 1
  fi
  msg_ok "Installed Emby dependencies"

	  msg_info "Setting up Emby hardware acceleration packages"
	  if ! ${APT_STD} apt-get -y install va-driver-all ocl-icd-libopencl1 intel-opencl-icd vainfo intel-gpu-tools; then
	    msg_error "Failed to install Emby GPU/VAAPI packages (continuing without hardware acceleration)"
	  else
	    if [[ "${CTTYPE:-1}" == "0" && -d /dev/dri ]]; then
	      chgrp video /dev/dri || true
	      chmod 755 /dev/dri || true
	      chmod 660 /dev/dri/* 2>/dev/null || true
	      ${APT_STD} adduser "$(id -u -n)" video || true
	      ${APT_STD} adduser "$(id -u -n)" render || true
	    fi
	    msg_ok "Set up Emby hardware acceleration packages"
	  fi
	
	  local LATEST JSON_FILE
	  JSON_FILE="/tmp/emby-releases.json"
	  msg_info "Determining latest Emby release"
	  if ! curl -fsSL https://api.github.com/repos/MediaBrowser/Emby.Releases/releases/latest -o "$JSON_FILE"; then
	    msg_error "Failed to query Emby releases API; skipping Emby installation"
	    rm -f "$JSON_FILE"
	    return 1
	  fi
	  # Use jq to parse the tag_name from the JSON payload.
	  LATEST="$(jq -r '.tag_name // empty' "$JSON_FILE" 2>/dev/null || true)"
	  rm -f "$JSON_FILE"
	  if [[ -z "${LATEST:-}" ]]; then
	    msg_error "Could not determine latest Emby release tag; skipping Emby installation"
	    return 1
	  fi

  local DEB_PATH="/tmp/emby-server-deb_${LATEST}_amd64.deb"
	  msg_info "Downloading Emby Media Server (${LATEST})"
	  if ! curl -fsSL "https://github.com/MediaBrowser/Emby.Releases/releases/download/${LATEST}/emby-server-deb_${LATEST}_amd64.deb" \
	    -o "${DEB_PATH}"; then
	    msg_error "Failed to download Emby .deb; skipping Emby installation"
	    return 1
	  fi
	
	  msg_info "Installing Emby Media Server (${LATEST})"
	  if ! ${APT_STD} dpkg -i "${DEB_PATH}"; then
	    msg_error "dpkg reported issues while installing Emby; attempting to fix dependencies"
	    if ! ${APT_STD} apt-get install -f -y; then
	      msg_error "Failed to resolve Emby dependencies"
	      rm -f "${DEB_PATH}"
	      return 1
	    fi
	  fi
	  rm -f "${DEB_PATH}"

	  # Adjust ssl-cert/render groups for Emby (best-effort).
	  if [[ "${CTTYPE:-1}" == "0" ]]; then
	    sed -i -e 's/^ssl-cert:x:104:emby$/render:x:104:root,emby/' \
	      -e 's/^render:x:108:root$/ssl-cert:x:108:emby/' /etc/group 2>/dev/null || true
	  else
	    sed -i -e 's/^ssl-cert:x:104:emby$/render:x:104:emby/' \
	      -e 's/^render:x:108:$/ssl-cert:x:108:/' /etc/group 2>/dev/null || true
	  fi

	  # Ensure Emby can read Riven's VFS by joining the riven group if it exists.
	  if getent group riven >/dev/null 2>&1; then
	    usermod -aG riven emby 2>/dev/null || true
	  fi

	  msg_ok "Installed Emby Media Server (${LATEST})"
}

