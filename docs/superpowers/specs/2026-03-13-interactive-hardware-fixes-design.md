# Interactive Hardware Fixes Design

Make `fix-sleep` and `fix-amdgpu` ujust recipes interactive, allowing users to toggle individual fixes on/off and select between options (e.g., PCIe ASPM policy levels). Uses `gum` with plain bash fallback.

## Motivation

The current recipes apply all fixes unconditionally. `pcie_aspm.policy=powersupersave` is suspected of breaking WiFi/Bluetooth on Framework 13 AMD by putting the MediaTek WiFi card's PCIe link into an unrecoverable state. Users need per-fix control and the ability to undo fixes.

## `fix-sleep` Recipe

### Current state display

On launch, show current status of each fix. Status is read from `rpm-ostree kargs` (staged state, which may differ from the running kernel if a reboot is pending). The wakeup hook status is checked by file existence.

```
Sleep/Suspend Fixes (Framework 13 AMD)

  RTC ACPI alarm:      ✓ applied (rtc_cmos.use_acpi_alarm=1)
  PCIe ASPM policy:    ✓ powersupersave
  Wakeup source hook:  · not installed
```

### Menu options

Present via `gum choose` (single select). The menu includes a "Done" option to exit without changes.

- `Toggle RTC ACPI alarm` — adds or removes `rtc_cmos.use_acpi_alarm=1` kernel param
- `Change PCIe ASPM policy` — opens sub-menu (see below)
- `Toggle wakeup source hook` — installs or removes `/etc/systemd/system-sleep/50-disable-wakeup-sources.sh`
- `Done` — exit

After each action, the recipe loops back to the menu with refreshed status display, so multiple changes can be made in one session.

### PCIe ASPM sub-menu

Present via `gum choose` with `--header` showing the current value. Options:

- `default`
- `performance`
- `powersave`
- `powersupersave`
- `unset (kernel default)`
- `Back`

To handle the possibility of multiple `pcie_aspm.policy=` values (from manual edits or older recipe runs), removal iterates over all known values and deletes each with `rpm-ostree kargs --delete-if-present=pcie_aspm.policy=VALUE`. Then appends the new value (unless "unset" was chosen).

### Wakeup source hook

The hook content is preserved exactly as in the current recipe (disables PIXA3854 touchpad and PNP0C0D lid wakeup sources before suspend). Toggle "off" removes the file with `sudo rm`.

### Behavior

- Toggling a kernel param that's currently applied removes it (`rpm-ostree kargs --delete-if-present`); if not applied, adds it (`--append-if-missing`).
- After exiting the menu (via "Done"), if kernel params were modified, offer reboot prompt.

## `fix-amdgpu` Recipe

### Current state display

```
AMD GPU Fixes (Framework / Ryzen APU)

  PSR disable:              ✓ applied (amdgpu.dcdebugmask=0x10)
  Scatter/gather disable:   · not applied
```

### Menu options

Present via `gum choose` with a "Done" option. Loops back to menu after each action.

- `Toggle PSR disable (dcdebugmask)` — adds or removes `amdgpu.dcdebugmask=0x10`
- `Toggle scatter/gather disable` — adds or removes `amdgpu.sg_display=0`
- `Done` — exit

### Behavior

Same toggle logic as fix-sleep kernel params. Offer reboot if params changed.

## Bash Fallback

When `gum` is not available, use numbered menu with `read -p` input, matching the pattern in `configure-yubikey-pam`. The loop and "Done" option work identically.

## Doc Fix

`docs/sleep-suspend-setup.md` line 74 incorrectly attributes `pcie_aspm.policy` to `ujust fix-amdgpu` — it belongs to `fix-sleep`. Fix the table.

## Files Changed

- `custom/ujust/rocinante.just` — rewrite `fix-sleep` and `fix-amdgpu` recipes
- `docs/sleep-suspend-setup.md` — update table and usage instructions for interactive flow

## Out of Scope

- No changes to `diagnose-sleep` recipe
- No changes to build-time firmware handling
- No new files beyond the existing recipe file
