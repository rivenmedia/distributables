# 📦 Proxmox Riven Installer — Change Log

## Version: 1.2
Release type: Structural + UX improvement (layout-changing)

---

## 🔌 Network Interface Handling
- Added automatic detection of usable network interfaces
- Excludes invalid/virtual interfaces:
  - lo, docker*, veth*, virbr*, tun*, tap*
- Added whiptail-based TUI selector for interface selection
- Removed requirement to manually type interface names

---

## 📁 Storage & Volume Layout (Major Change)
### Old
- Templates and container data stored in separate mounts
- Multiple bind mounts required
- Higher complexity and user confusion

### New
Unified storage root:
```
/srv/riven
├── templates
├── containers
├── config
├── data
└── mount
```

Benefits:
- Single bind mount
- Cleaner backups
- Simpler permissions
- Easier Docker volume management

---

## 📦 LXC Configuration
- Replaced multiple mp entries with a single mount:
  mp0: /srv/riven,mp=/srv/riven
- All services operate within unified root

---

## 🐳 Docker / Compose
- Updated volume mappings to reference /srv/riven paths
- Reduced mount propagation edge cases
- Simplified compose configuration

---

## 🛠 Installer Script Improvements
- Added interface auto-detection logic
- Added interactive UI menus
- Centralized directory creation
- Reduced hard-coded paths
- Improved comments and readability

---

## 📄 Documentation
- Updated README to reflect:
  - New storage layout
  - New network selection behavior
  - Single-mount architecture

---

## ⚠️ Migration Notes
- Existing installs using split mounts should:
  1. Move data into /srv/riven
  2. Update LXC config to single mount
  3. Restart containers

No data formats were changed — only paths.

---

## ✅ Summary
- Removed manual network configuration
- Simplified storage architecture
- Reduced user error
- Improved maintainability
