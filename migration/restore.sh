#!/bin/bash
# =============================================================
# Machine Migration Restore Script
# Restores the archive created by backup.sh on a new machine.
# Run this BEFORE bootstrap — it restores secrets and local data
# that dotfiles/bootstrap doesn't cover.
# Created: 2026-02-12
# =============================================================

set -euo pipefail

# ---------------------------------------------------------
# Locate archive
# ---------------------------------------------------------
if [ $# -eq 1 ]; then
  ARCHIVE="$1"
elif find ~/Desktop -maxdepth 1 -name "migration-backup-*.tar.gz" | grep -q .; then
  ARCHIVE=$(find ~/Desktop -maxdepth 1 -name "migration-backup-*.tar.gz" -print0 | xargs -0 stat -f '%m %N' | sort -rn | head -1 | cut -d' ' -f2-)
  echo "Archive auto-detected: $ARCHIVE"
else
  echo "Usage: $0 <migration-backup-YYYYMMDD_HHMMSS.tar.gz>"
  exit 1
fi

if [ ! -f "$ARCHIVE" ]; then
  echo "Error: file not found: $ARCHIVE"
  exit 1
fi

RESTORE_DIR=$(mktemp -d)
echo "Extracting to temp directory: $RESTORE_DIR"
tar -xzf "$ARCHIVE" -C "$RESTORE_DIR"
BACKUP_DIR="$RESTORE_DIR/migration-backup"

echo ""
echo "=========================================="
echo " Machine Migration Restore"
echo "=========================================="
echo ""

# ---------------------------------------------------------
# 1. SSH keys & config
# ---------------------------------------------------------
echo "[1/4] Restoring SSH keys and config..."
if [ -d "$BACKUP_DIR/ssh" ]; then
  mkdir -p ~/.ssh
  cp -rn "$BACKUP_DIR/ssh/"* ~/.ssh/ 2>/dev/null || true
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/id_* ~/.ssh/*.pem ~/.ssh/config 2>/dev/null || true
  chmod 644 ~/.ssh/*.pub 2>/dev/null || true
  echo "  -> Restored. Run 'ssh-add' to register keys with the agent."
else
  echo "  -> No SSH backup found, skipping"
fi

# ---------------------------------------------------------
# 2. AWS config & credentials
# ---------------------------------------------------------
echo "[2/4] Restoring AWS config..."
if [ -d "$BACKUP_DIR/aws" ]; then
  mkdir -p ~/.aws
  cp -rn "$BACKUP_DIR/aws/"* ~/.aws/ 2>/dev/null || true
  chmod 600 ~/.aws/credentials 2>/dev/null || true
  echo "  -> Restored"
else
  echo "  -> No AWS backup found, skipping"
fi

# ---------------------------------------------------------
# 3. Terminal History
# ---------------------------------------------------------
echo "[3/4] Restoring terminal history..."
if [ -d "$BACKUP_DIR/shell" ]; then
  # Append to existing history
  if [ -f "$BACKUP_DIR/shell/.zsh_history" ]; then
    cat "$BACKUP_DIR/shell/.zsh_history" >> ~/.zsh_history 2>/dev/null || \
      cp "$BACKUP_DIR/shell/.zsh_history" ~/.zsh_history
    echo "  -> zsh_history restored"
  fi
  if [ -f "$BACKUP_DIR/shell/.bash_history" ]; then
    cat "$BACKUP_DIR/shell/.bash_history" >> ~/.bash_history 2>/dev/null || \
      cp "$BACKUP_DIR/shell/.bash_history" ~/.bash_history
    echo "  -> bash_history restored"
  fi
else
  echo "  -> No history backup found, skipping"
fi

# ---------------------------------------------------------
# 4. Restore misc config files
#    (only items NOT handled by dotfiles/bootstrap)
# ---------------------------------------------------------
echo "[4/4] Restoring misc config files..."
if [ -d "$BACKUP_DIR/config" ]; then
  # gh (GitHub CLI)
  if [ -d "$BACKUP_DIR/config/gh" ]; then
    mkdir -p ~/.config/gh
    cp -rn "$BACKUP_DIR/config/gh/"* ~/.config/gh/ 2>/dev/null || true
    echo "  -> GitHub CLI config restored"
  fi
  # ghostty
  if [ -d "$BACKUP_DIR/config/ghostty" ]; then
    mkdir -p ~/.config/ghostty
    cp -rn "$BACKUP_DIR/config/ghostty/"* ~/.config/ghostty/ 2>/dev/null || true
    echo "  -> Ghostty config restored"
  fi
  # kube config
  if [ -d "$BACKUP_DIR/config/kube" ]; then
    mkdir -p ~/.kube
    cp -rn "$BACKUP_DIR/config/kube/"* ~/.kube/ 2>/dev/null || true
    echo "  -> kube config restored"
  fi
else
  echo "  -> No config backup found, skipping"
fi

# ---------------------------------------------------------
# Cleanup
# ---------------------------------------------------------
echo ""
echo "=========================================="
echo " Restore complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Run 'ssh-add' to register SSH keys"
echo "  2. Run dotfiles/bootstrap to set up brew, shell, and editor configs"
echo "  3. Review manual checklist: MIGRATION_CHECKLIST.md"
echo ""

# Clean up temp directory
rm -rf "$RESTORE_DIR"
