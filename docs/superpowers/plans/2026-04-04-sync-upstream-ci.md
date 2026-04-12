# Sync Upstream CI Changes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cherry-pick useful CI changes from upstream ublue-os/image-template without breaking our custom matrix build setup.

**Architecture:** Direct edits to two workflow files. No structural changes — just version bumps, one step removal, and one tag addition.

**Tech Stack:** GitHub Actions YAML workflows

---

## File Map

- Modify: `.github/workflows/build.yml` — 4 changes (remove container-storage-action, bump login-action, add date tag, update rechunker comment)
- Modify: `.github/workflows/build-disk.yml` — 2 changes (update BIB_IMAGE, update upload-artifact comment)

---

### Task 1: Remove container-storage-action from build.yml

**Files:**
- Modify: `.github/workflows/build.yml:57-70`

- [ ] **Step 1: Remove the BTRFS step and update the comment above remove-unwanted-software**

Delete lines 62-70 (the entire "Mount BTRFS for podman storage" step) and update the comment on lines 57-58 to match upstream's simpler wording.

Replace this block (lines 57-70):

```yaml
      # You only use this action if the container-storage-action proves to be unreliable, you don't need to enable both
      # This is optional, but if you see that your builds are way too big for the runners, you can enable this by uncommenting the following lines:
      - name: Maximize build space
        uses: ublue-os/remove-unwanted-software@695eb75bc387dbcd9685a8e72d23439d8686cba6

      - name: Mount BTRFS for podman storage
        id: container-storage-action
        uses: ublue-os/container-storage-action@911baca08baf30c8654933e9e9723cb399892140
        # Fallback to the remove-unwanted-software-action if github doesn't allocate enough space
        # See: https://github.com/ublue-os/container-storage-action/pull/11
        continue-on-error: true
        with:
          target-dir: /var/lib/containers
          mount-opts: compress-force=zstd:2
```

With:

```yaml
      # This is optional, but if you see that your builds are way too big for the runners, you can enable this by uncommenting the following lines:
      - name: Maximize build space
        uses: ublue-os/remove-unwanted-software@695eb75bc387dbcd9685a8e72d23439d8686cba6
```

- [ ] **Step 2: Verify YAML is valid**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build.yml'))"`
Expected: No output (success)

---

### Task 2: Bump docker/login-action to v4.1.0 in build.yml

**Files:**
- Modify: `.github/workflows/build.yml:153`

- [ ] **Step 1: Update the SHA and version comment**

Replace:
```yaml
        uses: docker/login-action@b45d80f862d83dbcd57f89517bcf500b2ab88fb2 # v4.0.0
```

With:
```yaml
        uses: docker/login-action@4907a6ddec9925e35a0a9e82d7399ccc52663121 # v4.1.0
```

---

### Task 3: Add bare date tag to build.yml metadata

**Files:**
- Modify: `.github/workflows/build.yml:89-93`

- [ ] **Step 1: Add the YYYYMMDD tag line**

Replace:
```yaml
          tags: |
            type=raw,value=${{ env.DEFAULT_TAG }}
            type=raw,value=${{ env.DEFAULT_TAG }}.{{date 'YYYYMMDD'}}
            type=sha,enable=${{ github.event_name == 'pull_request' }}
```

With:
```yaml
          tags: |
            type=raw,value=${{ env.DEFAULT_TAG }}
            type=raw,value=${{ env.DEFAULT_TAG }}.{{date 'YYYYMMDD'}}
            type=raw,value={{date 'YYYYMMDD'}}
            type=sha,enable=${{ github.event_name == 'pull_request' }}
```

---

### Task 4: Update commented-out rechunker reference in build.yml

**Files:**
- Modify: `.github/workflows/build.yml:130-132`

- [ ] **Step 1: Update the rechunker uses line and documentation comment**

Replace:
```yaml
      # Documentation for Rechunk is provided on their github repository at https://github.com/hhd-dev/rechunk
      # You can enable it by uncommenting the following lines:
      # - name: Run Rechunker
      #   id: rechunk
      #   uses: hhd-dev/rechunk@f153348d8100c1f504dec435460a0d7baf11a9d2 # v1.1.1
```

With:
```yaml
      # Documentation for Rechunk is provided on their github repository at https://github.com/ublue-os/legacy-rechunk
      # You can enable it by uncommenting the following lines:
      # - name: Run Rechunker
      #   id: rechunk
      #   uses: ublue-os/legacy-rechunk@a925083d9af7cb04b3e2a6e8c01bfa495f38b710 # v1.0.0
```

---

### Task 5: Update BIB_IMAGE in build-disk.yml

**Files:**
- Modify: `.github/workflows/build-disk.yml:30`

- [ ] **Step 1: Replace the pinned fork with upstream's recommended image**

Replace:
```yaml
  BIB_IMAGE: "ghcr.io/lorbuschris/bootc-image-builder:20250608" # "quay.io/centos-bootc/bootc-image-builder:latest" - see https://github.com/osbuild/bootc-image-builder/pull/954
```

With:
```yaml
  BIB_IMAGE: "quay.io/centos-bootc/bootc-image-builder:latest"
```

---

### Task 6: Update upload-artifact version comment in build-disk.yml

**Files:**
- Modify: `.github/workflows/build-disk.yml:93`

- [ ] **Step 1: Update the version comment from v4 to v7.0.0**

The SHA `bbbca2ddaa5d8feaa63e36b76fdaad77386f024f` is the same on both sides — only the comment is stale.

Replace:
```yaml
        uses: actions/upload-artifact@bbbca2ddaa5d8feaa63e36b76fdaad77386f024f # v4
```

With:
```yaml
        uses: actions/upload-artifact@bbbca2ddaa5d8feaa63e36b76fdaad77386f024f # v7.0.0
```

---

### Task 7: Validate and commit

- [ ] **Step 1: Validate both YAML files parse correctly**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build.yml')); yaml.safe_load(open('.github/workflows/build-disk.yml')); print('OK')"`
Expected: `OK`

- [ ] **Step 2: Commit all changes**

```bash
git add .github/workflows/build.yml .github/workflows/build-disk.yml
git commit -m "chore(ci): sync upstream template changes

- Remove container-storage-action (upstream dropped it)
- Bump docker/login-action v4.0.0 → v4.1.0
- Add bare YYYYMMDD date tag to image metadata
- Update rechunker comment to ublue-os/legacy-rechunk
- Switch BIB_IMAGE to upstream quay.io/centos-bootc/bootc-image-builder:latest
- Fix upload-artifact version comment (v4 → v7.0.0)"
```
