# Ghostty Terminal Emulator Design

**Status:** Approved 2026-06-25
**Branch (planned):** `feat/ghostty-terminal`
**Drives PR:** Install Ghostty terminal emulator natively into the rocinante image

## Context

1. **Ptyxis (VTE-based) lacks OSC 52.** OSC 52 is the terminal escape sequence for clipboard operations. Without it, zellij cannot write to the local clipboard when running over SSH into a remote host (e.g., GitHub Codespaces). Every copy action inside a remote zellij session silently fails.
2. **Ghostty supports OSC 52.** Ghostty is a modern GPU-accelerated terminal emulator by Mitchell Hashimoto that fully implements OSC 52. It is packaged for Fedora 44 via the `scottames/ghostty` COPR.
3. **`pgdev/ghostty` is archived** — zero chroots, no F44 builds. The `scottames/ghostty` COPR is the one cited by the official Ghostty install docs at `ghostty.org/docs/install/binary`. Build 10407077 (`ghostty 1.3.1-2`) succeeded on `fedora-44-x86_64` and `fedora-44-aarch64`.
4. **Ghostty does not yet read system-wide config.** Upstream issue #4506 (XDG_CONFIG_DIRS support) is open and unimplemented. The workaround is `/etc/skel/.config/ghostty/config`, which is applied at new-user creation.

## Goals & non-goals

**Goals:**
- Install Ghostty (`ghostty` — this COPR bundles terminfo and shell integration into the main package; no separate subpackages) from `scottames/ghostty` COPR.
- Enable OSC 52 clipboard for new users via a skeleton config.
- Set Ghostty as the image-level default terminal on GNOME/Bluefin via `xdg-terminal-exec` (safe, user-overridable, harmless on KDE).
- Provide a `ujust set-default-terminal-ghostty` recipe for KDE/Aurora users who want to opt in explicitly.

**Non-goals:**
- Removing or disabling Ptyxis (it remains installed; users choose).
- Forcing Ghostty as default on Aurora/KDE (KDE ignores `xdg-terminals.list`).
- Setting fonts, themes, or GPU-specific options (may be absent or clash with user prefs).
- System-wide config (not supported by Ghostty upstream yet).

## Approach

### Feature 1: COPR package install

**File:** `build/50-ghostty.sh`
**Change:** New build script using `copr_install_isolated "scottames/ghostty"` to install `ghostty`. This COPR ships terminfo (`xterm-ghostty`) and shell integration inside the main `ghostty` package — there are no `-terminfo`/`-shell-integration` subpackages (listing them fails the build with "No match for argument"). `gtk4-layer-shell` and other runtime deps pull automatically.

Script follows the `30-incus.sh` header convention (`#!/usr/bin/bash`, `set -eoux pipefail`, `echo ::group::`). Sources `copr-helpers.sh` with `# shellcheck source=` directive for shellcheck cleanliness.

### Feature 2: Skeleton config for OSC 52

**File:** `custom/ghostty/config` → installed to `/etc/skel/.config/ghostty/config`
**Change:** Minimal config enabling `clipboard-read = allow`, `clipboard-write = allow`, `copy-on-select = clipboard`, `shell-integration = detect`.

Ghostty defaults `clipboard-read` to `ask` (interactive prompt per-read), which breaks the silent OSC 52 remote-clipboard flow from zellij. The skel config flips this to `allow`.

**Caveat:** Only applies to newly created user accounts. Existing users must copy or edit manually, or re-run `mkhomedir` equivalent. This is the only available mechanism until upstream implements XDG_CONFIG_DIRS (issue #4506).

### Feature 3: Image-level GNOME default terminal

**File:** `/etc/xdg/xdg-terminals.list` (written inline in `50-ghostty.sh`)
**Change:** Contains `com.mitchellh.ghostty.desktop`.

Priority chain for `xdg-terminal-exec`:
1. `~/.config/xdg-terminals.list` (user — highest, overrides all)
2. `/etc/xdg/xdg-terminals.list` (sysadmin / image — this file)
3. `/usr/share/xdg-terminal-exec/xdg-terminals.list` (upstream image default — Ptyxis)

Writing to tier 2 (not tier 3) allows users to override with their own `~/.config` file. Bluefin merged PR #265 which wired keyboard shortcuts to `xdg-terminal-exec`, so this works on Bluefin/GNOME.

**Aurora/KDE safety:** KDE does not consult `xdg-terminals.list` for Dolphin or its own terminal shortcuts. Writing this file has zero effect on the aurora variant.

### Feature 4: ujust recipe for KDE opt-in

**File:** `custom/ujust/rocinante.just`
**Change:** New `set-default-terminal-ghostty` recipe. It first deploys the skel OSC 52 config to the current user's `~/.config/ghostty/config` if absent (closing the `/etc/skel` gap for existing accounts). On KDE it uses `kwriteconfig6` (Plasma 6 on Aurora), falling back to `kwriteconfig5`, to set `kdeglobals` entries. On GNOME/other, it writes `~/.config/xdg-terminals.list`. Both paths are guarded with helpful error messages.

### Feature 5: Wire script into build

**File:** `build/10-build.sh`
**Change:** Add `/ctx/build/50-ghostty.sh` after `40-rocm.sh` in the "Run additional build scripts" block.

Custom files are available at `/ctx/custom/` (the Containerfile binds `ctx/custom` from the build context). No additional COPY step needed.

**Failure modes and what we accept:**
- If `scottames/ghostty` COPR is unavailable during a build, the build fails — acceptable; this is the correct behavior for a missing dependency.
- If a user already has `~/.config/ghostty/config`, the skel file is not applied — acceptable; user config takes precedence.
- Aurora users get Ghostty installed but not set as default terminal — acceptable; they can run `ujust set-default-terminal-ghostty` to opt in.

**What this is structurally incapable of doing wrong:**
- Cannot break Ptyxis (it is not touched).
- Cannot force KDE to use Ghostty (KDE ignores `xdg-terminals.list`).
- Cannot affect existing users' clipboard settings (skel only applies at account creation).

## File map

- **Create:** `build/50-ghostty.sh` — COPR install + skeleton config installation + xdg-terminals.list
- **Create:** `custom/ghostty/config` — minimal Ghostty config skeleton enabling OSC 52
- **Modify:** `build/10-build.sh` — add call to `50-ghostty.sh`
- **Modify:** `custom/ujust/rocinante.just` — add `set-default-terminal-ghostty` recipe
- **No changes to:** `Containerfile`, `.github/workflows/`, existing build scripts

## Verification

1. **Local shellcheck.** `shellcheck build/50-ghostty.sh` — no errors or warnings.
2. **CI build green on all variants.** Verify `rocinante`, `rocinante-nvidia`, `rocinante-aurora` all build successfully with the new script.
3. **Image inspection (post-merge).** After `bootc upgrade` and reboot:
   - `ghostty --version` succeeds.
   - `infocmp xterm-ghostty` succeeds (ghostty-terminfo installed).
   - `/etc/skel/.config/ghostty/config` exists with `clipboard-read = allow`.
   - `/etc/xdg/xdg-terminals.list` contains `com.mitchellh.ghostty.desktop`.
4. **Laptop/system test:**
   - Open Ghostty via Super+T (GNOME keyboard shortcut).
   - SSH into a GitHub Codespace, start `zellij`.
   - Copy text in zellij; paste locally — clipboard content appears correctly (OSC 52 working).
   - New user account: verify `~/.config/ghostty/config` is present with `allow` settings.
   - Aurora: confirm Plasma terminal launcher still opens Konsole (Ghostty not forced).
   - `ujust set-default-terminal-ghostty` on Aurora: Ghostty opens via Dolphin "Open Terminal".
5. **Rollback path:** Revert `10-build.sh` line addition and delete `50-ghostty.sh`, `custom/ghostty/`. Ghostty is not in Fedora base repos, so removing the COPR install line is sufficient.

## Risks

- **COPR availability.** `scottames/ghostty` is a community COPR, not an official Fedora repo. If the maintainer archives it, builds break. Mitigation: monitor COPR; the official Ghostty install docs reference this COPR, making it unlikely to disappear without warning.
- **Ghostty upstream OSC 52 regression.** If a future Ghostty release changes clipboard behavior, the skeleton config may need updating. Mitigation: `clipboard-read = allow` is an explicit config — it will not silently revert.
- **skel gap for existing users.** Users who already have accounts do not get the skeleton config at creation. Mitigation: `ujust set-default-terminal-ghostty` copies `/etc/skel/.config/ghostty/config` to the current user if missing, and the `first-run` recipe lists the command — so the OSC 52 fix reaches existing accounts.
- **xdg-terminal-exec tool availability.** If Bluefin removes `xdg-terminal-exec` in a future upstream change, `/etc/xdg/xdg-terminals.list` has no effect on keyboard shortcuts. Mitigation: this file is inert if the tool is absent — no breakage.
