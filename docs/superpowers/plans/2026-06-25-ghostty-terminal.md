# Ghostty Terminal Emulator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install the Ghostty terminal emulator natively into the rocinante image to fix the OSC 52 clipboard breakage that prevents remote copy-paste from zellij over SSH into GitHub Codespaces. Ptyxis (VTE-based) lacks OSC 52; Ghostty implements it fully. Ship a skeleton config enabling `clipboard-read = allow` so the feature works without user intervention for new accounts.

**Architecture:** New build script `build/50-ghostty.sh` installs Ghostty from the `scottames/ghostty` COPR (verified F44 builds). A skeleton config at `/etc/skel/.config/ghostty/config` enables OSC 52 for new users. Image-level GNOME default terminal is set via `/etc/xdg/xdg-terminals.list` (tier 2 of xdg-terminal-exec priority chain — user-overridable, harmless on KDE). A `ujust` recipe handles KDE/Aurora opt-in explicitly.

**Tech Stack:** Containerfile + buildah, bash build scripts, dnf5, copr-helpers.sh, shellcheck, just

**Spec:** `docs/superpowers/specs/2026-06-25-ghostty-terminal-design.md`

---

## File map

- **Create:** `build/50-ghostty.sh` — COPR install + skel config install + xdg-terminals.list
- **Create:** `custom/ghostty/config` — minimal Ghostty skeleton config enabling OSC 52
- **Modify:** `build/10-build.sh` — wire in `/ctx/build/50-ghostty.sh` after `40-rocm.sh`
- **Modify:** `custom/ujust/rocinante.just` — add `set-default-terminal-ghostty` recipe
- **No changes to:** `Containerfile`, `.github/workflows/`, other build scripts

---

## Task 1: Ghostty skeleton config

**Files:**
- Create: `custom/ghostty/config`

The critical enabler for OSC 52 is `clipboard-read = allow`. Ghostty defaults this to `ask`, which prompts interactively on every remote clipboard write — breaking the silent zellij-over-SSH copy flow. This config is installed to `/etc/skel/.config/ghostty/config` by `50-ghostty.sh` and applies at new-user account creation.

- [x] **Step 1: Create `custom/ghostty/config`** with `clipboard-read = allow`, `clipboard-write = allow`, `copy-on-select = clipboard`, `shell-integration = detect`. Add comments explaining the OSC 52 purpose.

Expected: File exists at `custom/ghostty/config`.

---

## Task 2: Build script `build/50-ghostty.sh`

**Files:**
- Create: `build/50-ghostty.sh`

Follows `30-incus.sh` conventions: `#!/usr/bin/bash`, `set -eoux pipefail`, `echo ::group::` blocks, sources `copr-helpers.sh` with shellcheck directive. Installs `ghostty` via `copr_install_isolated "scottames/ghostty"` (this COPR bundles terminfo and shell integration into the main package — no separate subpackages). Installs the skel config via `install -D -m0644`. Writes `/etc/xdg/xdg-terminals.list` with `com.mitchellh.ghostty.desktop`.

- [x] **Step 1: Create `build/50-ghostty.sh`** with correct shebang, `set -eoux pipefail`, copr source directive, COPR install, skel config install, and xdg-terminals.list write.

- [x] **Step 2: Make executable**

```bash
chmod +x build/50-ghostty.sh
```

Expected: `ls -la build/50-ghostty.sh` shows `-rwxr-xr-x`.

- [x] **Step 3: shellcheck clean**

```bash
shellcheck build/50-ghostty.sh
```

Expected: No errors or warnings.

---

## Task 3: Wire into `build/10-build.sh`

**Files:**
- Modify: `build/10-build.sh`

Add one line after the `40-rocm.sh` call.

- [x] **Step 1: Add `/ctx/build/50-ghostty.sh` to the "Run additional build scripts" block**

The block should read:
```bash
# Run additional build scripts
/ctx/build/20-1password.sh
/ctx/build/30-incus.sh
/ctx/build/40-rocm.sh
/ctx/build/50-ghostty.sh
```

Expected: `grep 50-ghostty build/10-build.sh` shows the new line.

---

## Task 4: ujust recipe

**Files:**
- Modify: `custom/ujust/rocinante.just`

Add `set-default-terminal-ghostty` recipe following the standard skeleton (one-line comment, `[group('Rocinante')]`, `#!/usr/bin/env bash`, `set -euo pipefail`, `b`/`n` vars). The recipe also deploys the skel OSC 52 config to the current user (existing accounts don't get `/etc/skel`). It detects KDE via `$XDG_CURRENT_DESKTOP` and uses `kwriteconfig6` (Plasma 6 on Aurora), falling back to `kwriteconfig5`; for GNOME it writes `~/.config/xdg-terminals.list`.

- [x] **Step 1: Append recipe to `custom/ujust/rocinante.just`**

Expected: `ujust --list | grep ghostty` shows the recipe (after system rebuild).

---

## Task 5: Local validation

- [ ] **shellcheck `build/50-ghostty.sh`**

```bash
shellcheck build/50-ghostty.sh
```

Expected: Zero findings.

- [ ] **shellcheck `build/10-build.sh`**

```bash
shellcheck build/10-build.sh
```

Expected: Zero findings (already shellcheck-clean before this change).

- [ ] **just fmt check on rocinante.just**

```bash
just --fmt --check --unstable custom/ujust/rocinante.just
```

Expected: No formatting changes needed (or apply with `just --fmt --unstable`).

- [ ] **Verify custom/ghostty/config exists and has correct content**

```bash
grep 'clipboard-read.*allow' custom/ghostty/config
```

Expected: line found.

- [ ] **Verify 10-build.sh wiring**

```bash
grep '50-ghostty' build/10-build.sh
```

Expected: `/ctx/build/50-ghostty.sh` line present.

---

## Task 6: Push branch and open PR

- [ ] Push `feat/ghostty-terminal` to origin
- [ ] Open PR with `gh pr create`
- [ ] Watch CI — all three variants (rocinante, rocinante-nvidia, rocinante-aurora) must build green

---

## Task 7: Merge and verify

- [ ] Merge PR after CI green
- [ ] On target machine: `bootc upgrade && systemctl reboot`
- [ ] Verify: `ghostty --version`
- [ ] Verify: `infocmp xterm-ghostty` (ghostty-terminfo)
- [ ] Verify: `/etc/xdg/xdg-terminals.list` contains `com.mitchellh.ghostty.desktop`
- [ ] Verify: `/etc/skel/.config/ghostty/config` contains `clipboard-read = allow`
- [ ] Live OSC 52 test: SSH to Codespace, open zellij, copy text, paste locally

---

## Verification (end-to-end)

- `ghostty --version` outputs a version string
- `infocmp xterm-ghostty` succeeds (no "unknown terminal" error on remote SSH hosts)
- Super+T in GNOME opens Ghostty (xdg-terminal-exec routing)
- Copy in remote zellij (over SSH into Codespace) pastes correctly in local Ghostty
- Aurora: Plasma terminal launcher still opens Konsole by default (Ghostty NOT forced)
- `ujust set-default-terminal-ghostty` on Aurora correctly configures KDE via `kwriteconfig6` (falls back to `kwriteconfig5`)

## Risks and rollback

- **COPR single-maintainer risk.** `scottames/ghostty` is a community COPR. If archived, future builds break. Rollback: revert the `10-build.sh` line and delete `50-ghostty.sh`.
- **Existing users miss the skel config.** `/etc/skel` only applies at account creation. `ujust set-default-terminal-ghostty` copies the config to the current user's `~/.config/ghostty/config` to close this gap, and the `first-run` recipe surfaces the command.
- **`xdg-terminal-exec` upstream changes.** If Bluefin removes the tool, `/etc/xdg/xdg-terminals.list` has no effect. Inert failure — no breakage, just no GNOME default override.
- **FC44 COPR build availability.** Verified build 10407077 succeeded on `fedora-44-x86_64` and `fedora-44-aarch64`. If the build is later removed, builds break; monitor COPR.
