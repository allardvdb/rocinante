# Interactive Hardware Fixes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `fix-sleep` and `fix-amdgpu` ujust recipes interactive with per-fix toggle control, ASPM policy selection, and undo capability.

**Architecture:** Replace the current apply-all-unconditionally recipes with a menu loop using `gum choose` (bash fallback). Each iteration shows current status, lets the user pick one action, applies it, and loops back. "Done" exits and offers reboot if kernel params changed.

**Tech Stack:** Bash, `gum` CLI, `rpm-ostree kargs`, justfile

**Spec:** `docs/superpowers/specs/2026-03-13-interactive-hardware-fixes-design.md`

---

## Chunk 1: Rewrite `fix-sleep` recipe

### Task 1: Replace `fix-sleep` with interactive version

**Files:**
- Modify: `custom/ujust/rocinante.just:441-526`

- [ ] **Step 1: Replace the `fix-sleep` recipe**

Replace lines 441–526 in `custom/ujust/rocinante.just` with the following interactive recipe:

```just
# Manage sleep/suspend fixes on Framework 13 AMD (S0ix deep sleep)
[group('Rocinante')]
fix-sleep:
    #!/usr/bin/env bash
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""
    green=$(tput setaf 2 2>/dev/null) || green=""
    yellow=$(tput setaf 3 2>/dev/null) || yellow=""
    red=$(tput setaf 1 2>/dev/null) || red=""

    SLEEP_HOOK="/etc/systemd/system-sleep/50-disable-wakeup-sources.sh"
    ASPM_VALUES=("default" "performance" "powersave" "powersupersave")
    KARGS_CHANGED=false

    show_status() {
        CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")

        echo "${b}Sleep/Suspend Fixes (Framework 13 AMD)${n}"
        echo ""

        # RTC ACPI alarm
        if echo "$CURRENT_KARGS" | grep -q "rtc_cmos.use_acpi_alarm=1"; then
            echo "  RTC ACPI alarm:      ${green}${b}✓${n} applied"
        else
            echo "  RTC ACPI alarm:      · not applied"
        fi

        # PCIe ASPM policy
        ASPM_CURRENT=""
        for val in "${ASPM_VALUES[@]}"; do
            if echo "$CURRENT_KARGS" | grep -q "pcie_aspm.policy=${val}"; then
                ASPM_CURRENT="$val"
                break
            fi
        done
        if [[ -n "$ASPM_CURRENT" ]]; then
            echo "  PCIe ASPM policy:    ${green}${b}✓${n} ${ASPM_CURRENT}"
        else
            echo "  PCIe ASPM policy:    · unset (kernel default)"
        fi

        # Wakeup source hook
        if [[ -f "$SLEEP_HOOK" ]]; then
            echo "  Wakeup source hook:  ${green}${b}✓${n} installed"
        else
            echo "  Wakeup source hook:  · not installed"
        fi
        echo ""
    }

    choose_menu() {
        local prompt="$1"
        shift
        local options=("$@")
        if command -v gum &> /dev/null; then
            gum choose --header "$prompt" "${options[@]}"
        else
            echo "$prompt" >&2
            local i=1
            for opt in "${options[@]}"; do
                echo "  ${i}) ${opt}" >&2
                ((i++))
            done
            echo "" >&2
            read -p "Choice [1-${#options[@]}]: " choice
            if [[ "$choice" -ge 1 && "$choice" -le "${#options[@]}" ]] 2>/dev/null; then
                echo "${options[$((choice-1))]}"
            else
                echo ""
            fi
        fi
    }

    toggle_rtc() {
        CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")
        if echo "$CURRENT_KARGS" | grep -q "rtc_cmos.use_acpi_alarm=1"; then
            echo "Removing ${b}rtc_cmos.use_acpi_alarm=1${n}..."
            sudo rpm-ostree kargs --delete-if-present="rtc_cmos.use_acpi_alarm=1"
            KARGS_CHANGED=true
            echo "${green}${b}✓${n} Removed rtc_cmos.use_acpi_alarm=1"
        else
            echo "Adding ${b}rtc_cmos.use_acpi_alarm=1${n}..."
            sudo rpm-ostree kargs --append-if-missing="rtc_cmos.use_acpi_alarm=1"
            KARGS_CHANGED=true
            echo "${green}${b}✓${n} Added rtc_cmos.use_acpi_alarm=1"
        fi
    }

    change_aspm() {
        # Detect current value
        CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")
        ASPM_CURRENT=""
        for val in "${ASPM_VALUES[@]}"; do
            if echo "$CURRENT_KARGS" | grep -q "pcie_aspm.policy=${val}"; then
                ASPM_CURRENT="$val"
                break
            fi
        done

        local header="PCIe ASPM policy"
        if [[ -n "$ASPM_CURRENT" ]]; then
            header="PCIe ASPM policy (current: ${ASPM_CURRENT})"
        else
            header="PCIe ASPM policy (current: unset)"
        fi

        ACTION=$(choose_menu "$header" "default" "performance" "powersave" "powersupersave" "unset (kernel default)" "Back")

        if [[ "$ACTION" == "Back" || -z "$ACTION" ]]; then
            return
        fi

        # Remove any existing ASPM policy values
        for val in "${ASPM_VALUES[@]}"; do
            sudo rpm-ostree kargs --delete-if-present="pcie_aspm.policy=${val}" 2>/dev/null || true
        done

        if [[ "$ACTION" == "unset (kernel default)" ]]; then
            KARGS_CHANGED=true
            echo "${green}${b}✓${n} Removed PCIe ASPM policy (using kernel default)"
        else
            sudo rpm-ostree kargs --append-if-missing="pcie_aspm.policy=${ACTION}"
            KARGS_CHANGED=true
            echo "${green}${b}✓${n} Set PCIe ASPM policy to ${ACTION}"
        fi
    }

    toggle_wakeup_hook() {
        if [[ -f "$SLEEP_HOOK" ]]; then
            echo "Removing wakeup source hook..."
            sudo rm "$SLEEP_HOOK"
            echo "${green}${b}✓${n} Removed $SLEEP_HOOK"
        else
            echo "Installing wakeup source hook..."
            sudo mkdir -p "$(dirname "$SLEEP_HOOK")"
            sudo tee "$SLEEP_HOOK" > /dev/null << 'HOOK'
    #!/usr/bin/bash
    # Disable touchpad and lid as wakeup sources before suspend
    # These devices generate spurious wakeup events that block S0ix deep sleep
    # on Framework 13 AMD (Strix Point)

    case "$1" in
        pre)
            # Disable touchpad (PIXA3854) wakeup
            for dev in $(find /sys/devices -name "wakeup" -path "*PIXA3854*" 2>/dev/null); do
                echo "disabled" > "$dev" 2>/dev/null || true
            done
            # Disable lid sensor wakeup
            for dev in $(find /sys/devices -name "wakeup" -path "*PNP0C0D*" 2>/dev/null); do
                echo "disabled" > "$dev" 2>/dev/null || true
            done
            ;;
    esac
    HOOK
            sudo chmod 755 "$SLEEP_HOOK"
            echo "${green}${b}✓${n} Installed $SLEEP_HOOK"
        fi
    }

    # Main menu loop
    while true; do
        show_status

        ACTION=$(choose_menu "Select an option:" \
            "Toggle RTC ACPI alarm" \
            "Change PCIe ASPM policy" \
            "Toggle wakeup source hook" \
            "Done")

        case "$ACTION" in
            "Toggle RTC ACPI alarm") toggle_rtc ;;
            "Change PCIe ASPM policy") change_aspm ;;
            "Toggle wakeup source hook") toggle_wakeup_hook ;;
            "Done"|"") break ;;
        esac
        echo ""
    done

    if [[ "$KARGS_CHANGED" == true ]]; then
        echo "${yellow}A reboot is required for kernel parameter changes to take effect.${n}"
        echo ""
        read -p "Reboot now? [y/N]: " reboot_confirm
        if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
            systemctl reboot
        else
            echo "Please reboot when convenient: ${b}systemctl reboot${n}"
        fi
    fi
```

- [ ] **Step 2: Verify syntax**

Run: `just --list --justfile custom/ujust/rocinante.just 2>&1 | grep fix-sleep`
Expected: `fix-sleep` appears in the list without syntax errors.

- [ ] **Step 3: Commit**

```bash
git add custom/ujust/rocinante.just
git commit -m "feat: make fix-sleep interactive with per-fix toggle and ASPM policy selection"
```

---

## Chunk 2: Rewrite `fix-amdgpu` recipe

### Task 2: Replace `fix-amdgpu` with interactive version

**Files:**
- Modify: `custom/ujust/rocinante.just:528-582` (line numbers after Task 1 changes — locate by `fix-amdgpu:` recipe header)

- [ ] **Step 1: Replace the `fix-amdgpu` recipe**

Replace the `fix-amdgpu` recipe (from the `# Apply AMD GPU workarounds` comment through the closing `fi`) with:

```just
# Manage AMD GPU workarounds for Framework laptops (ring buffer crash fix)
[group('Rocinante')]
fix-amdgpu:
    #!/usr/bin/env bash
    set -euo pipefail
    # Terminal formatting
    b=$(tput bold 2>/dev/null) || b=""
    n=$(tput sgr0 2>/dev/null) || n=""
    green=$(tput setaf 2 2>/dev/null) || green=""
    yellow=$(tput setaf 3 2>/dev/null) || yellow=""

    KARGS_CHANGED=false

    show_status() {
        CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")

        echo "${b}AMD GPU Fixes (Framework / Ryzen APU)${n}"
        echo ""

        if echo "$CURRENT_KARGS" | grep -q "amdgpu.dcdebugmask=0x10"; then
            echo "  PSR disable:              ${green}${b}✓${n} applied (dcdebugmask=0x10)"
        else
            echo "  PSR disable:              · not applied"
        fi

        if echo "$CURRENT_KARGS" | grep -q "amdgpu.sg_display=0"; then
            echo "  Scatter/gather disable:   ${green}${b}✓${n} applied (sg_display=0)"
        else
            echo "  Scatter/gather disable:   · not applied"
        fi
        echo ""
    }

    choose_menu() {
        local prompt="$1"
        shift
        local options=("$@")
        if command -v gum &> /dev/null; then
            gum choose --header "$prompt" "${options[@]}"
        else
            echo "$prompt" >&2
            local i=1
            for opt in "${options[@]}"; do
                echo "  ${i}) ${opt}" >&2
                ((i++))
            done
            echo "" >&2
            read -p "Choice [1-${#options[@]}]: " choice
            if [[ "$choice" -ge 1 && "$choice" -le "${#options[@]}" ]] 2>/dev/null; then
                echo "${options[$((choice-1))]}"
            else
                echo ""
            fi
        fi
    }

    toggle_karg() {
        local param="$1"
        local label="$2"
        CURRENT_KARGS=$(rpm-ostree kargs 2>/dev/null || echo "")
        if echo "$CURRENT_KARGS" | grep -q "${param}"; then
            echo "Removing ${b}${param}${n}..."
            sudo rpm-ostree kargs --delete-if-present="${param}"
            KARGS_CHANGED=true
            echo "${green}${b}✓${n} Removed ${label}"
        else
            echo "Adding ${b}${param}${n}..."
            sudo rpm-ostree kargs --append-if-missing="${param}"
            KARGS_CHANGED=true
            echo "${green}${b}✓${n} Added ${label}"
        fi
    }

    # Main menu loop
    while true; do
        show_status

        ACTION=$(choose_menu "Select an option:" \
            "Toggle PSR disable (dcdebugmask)" \
            "Toggle scatter/gather disable" \
            "Done")

        case "$ACTION" in
            "Toggle PSR disable (dcdebugmask)") toggle_karg "amdgpu.dcdebugmask=0x10" "PSR disable" ;;
            "Toggle scatter/gather disable") toggle_karg "amdgpu.sg_display=0" "scatter/gather disable" ;;
            "Done"|"") break ;;
        esac
        echo ""
    done

    if [[ "$KARGS_CHANGED" == true ]]; then
        echo "${yellow}A reboot is required for changes to take effect.${n}"
        echo ""
        read -p "Reboot now? [y/N]: " reboot_confirm
        if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
            systemctl reboot
        else
            echo "Please reboot when convenient: ${b}systemctl reboot${n}"
        fi
    fi
```

- [ ] **Step 2: Verify syntax**

Run: `just --list --justfile custom/ujust/rocinante.just 2>&1 | grep fix-amdgpu`
Expected: `fix-amdgpu` appears in the list without syntax errors.

- [ ] **Step 3: Commit**

```bash
git add custom/ujust/rocinante.just
git commit -m "feat: make fix-amdgpu interactive with per-fix toggle"
```

---

## Chunk 3: Update documentation

### Task 3: Fix docs to reflect interactive usage and correct ASPM attribution

**Files:**
- Modify: `docs/sleep-suspend-setup.md:69-75`

- [ ] **Step 1: Update the manual fixes table**

Replace the manual fixes table in `docs/sleep-suspend-setup.md` (lines 69-75) with:

```markdown
### Manual (machine-specific, via ujust)

| Fix | Command | What it does |
|-----|---------|-------------|
| RTC ACPI alarm for s2idle | `ujust fix-sleep` | Toggle `rtc_cmos.use_acpi_alarm=1` kernel param |
| PCIe ASPM policy | `ujust fix-sleep` | Select ASPM policy (default/performance/powersave/powersupersave/unset) |
| Touchpad/lid wakeup suppression | `ujust fix-sleep` | Toggle sleep hook in `/etc/systemd/system-sleep/` |
| PSR disable (dcdebugmask) | `ujust fix-amdgpu` | Toggle `amdgpu.dcdebugmask=0x10` kernel param |
| Scatter/gather disable | `ujust fix-amdgpu` | Toggle `amdgpu.sg_display=0` kernel param |
```

- [ ] **Step 2: Update Step 2 instructions**

Replace lines 24-32 (the "Step 2" section) with:

```markdown
## Step 2: Apply machine-specific fixes

After rebooting onto the new image:

```bash
# Interactively configure sleep fixes (RTC alarm, ASPM policy, wakeup sources)
ujust fix-sleep

# Interactively configure GPU fixes (PSR, scatter/gather)
ujust fix-amdgpu
```

Both recipes show current status and let you toggle individual fixes. They prompt for a reboot if kernel parameters were changed.
```

- [ ] **Step 3: Update verify checklist**

Replace lines 43-47 (the check items) with:

```markdown
Check the output for:
- `linux-firmware` shows `20260309` or newer
- `rtc_cmos.use_acpi_alarm=1` is set (if enabled via fix-sleep)
- PCIe ASPM policy matches your selection (if set via fix-sleep)
- Wakeup source hook is listed under installed sleep hooks (if enabled via fix-sleep)
- No known-bad firmware warning
```

- [ ] **Step 4: Commit**

```bash
git add docs/sleep-suspend-setup.md
git commit -m "docs: update sleep setup guide for interactive fix-sleep and fix-amdgpu"
```
