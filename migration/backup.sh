#!/bin/bash
# =============================================================
# Machine Migration Backup Script
# Backs up secrets and local data that dotfiles/bootstrap can't cover.
# Created: 2026-02-12
# =============================================================

set -euo pipefail

BACKUP_DIR="$HOME/Desktop/migration-backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE_NAME="migration-backup-${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "=========================================="
echo " Machine Migration Backup"
echo "=========================================="
echo ""

# ---------------------------------------------------------
# 1. SSH keys & config
# ---------------------------------------------------------
echo "[1/5] Backing up SSH keys and config..."
mkdir -p "$BACKUP_DIR/ssh"
cp -r ~/.ssh/config ~/.ssh/config.d "$BACKUP_DIR/ssh/" 2>/dev/null || true
# Copy key files (exclude known_hosts)
for f in ~/.ssh/*; do
  fname=$(basename "$f")
  case "$fname" in
    known_hosts|known_hosts.old|.DS_Store) continue ;;
    *) cp -p "$f" "$BACKUP_DIR/ssh/" 2>/dev/null || true ;;
  esac
done
echo "  -> $(find "$BACKUP_DIR/ssh/" -maxdepth 1 -type f | wc -l | tr -d ' ') files backed up"

# ---------------------------------------------------------
# 2. AWS config & credentials
# ---------------------------------------------------------
echo "[2/5] Backing up AWS config..."
mkdir -p "$BACKUP_DIR/aws"
cp -r ~/.aws/config ~/.aws/credentials "$BACKUP_DIR/aws/" 2>/dev/null || true
cp -r ~/.aws/cli ~/.aws/sso "$BACKUP_DIR/aws/" 2>/dev/null || true
echo "  -> Done"

# ---------------------------------------------------------
# 3. Chrome Bookmarks
# ---------------------------------------------------------
echo "[3/5] Backing up Chrome bookmarks..."
mkdir -p "$BACKUP_DIR/chrome"
CHROME_BOOKMARKS="$HOME/Library/Application Support/Google/Chrome/Default/Bookmarks"
if [ -f "$CHROME_BOOKMARKS" ]; then
  cp "$CHROME_BOOKMARKS" "$BACKUP_DIR/chrome/Bookmarks.json"
  echo "  -> Bookmarks file backed up"
else
  echo "  -> Chrome Bookmarks file not found"
fi

# ---------------------------------------------------------
# 4. Terminal History
# ---------------------------------------------------------
echo "[4/5] Backing up terminal history..."
mkdir -p "$BACKUP_DIR/shell"
cp ~/.zsh_history "$BACKUP_DIR/shell/" 2>/dev/null || true
cp ~/.bash_history "$BACKUP_DIR/shell/" 2>/dev/null || true
echo "  -> zsh_history: $(wc -l < ~/.zsh_history 2>/dev/null | tr -d ' ') lines"

# ---------------------------------------------------------
# 5. Misc config files (not handled by dotfiles/bootstrap)
# ---------------------------------------------------------
echo "[5/5] Backing up misc config files..."
mkdir -p "$BACKUP_DIR/config"
# gh (GitHub CLI auth tokens)
cp -r ~/.config/gh "$BACKUP_DIR/config/gh" 2>/dev/null || true
# ghostty
cp -r ~/.config/ghostty "$BACKUP_DIR/config/ghostty" 2>/dev/null || true
# kube config (exclude cache)
if [ -d ~/.kube ]; then
  mkdir -p "$BACKUP_DIR/config/kube"
  cp ~/.kube/config "$BACKUP_DIR/config/kube/" 2>/dev/null || true
  cp ~/.kube/kubectx "$BACKUP_DIR/config/kube/" 2>/dev/null || true
  cp -r ~/.kube/kubeconfigs "$BACKUP_DIR/config/kube/" 2>/dev/null || true
  cp -r ~/.kube/kubens "$BACKUP_DIR/config/kube/" 2>/dev/null || true
fi
echo "  -> Done"

# ---------------------------------------------------------
# Archive
# ---------------------------------------------------------
echo ""
echo "Compressing..."
cd "$HOME/Desktop"
tar -czf "$ARCHIVE_NAME" -C "$HOME/Desktop" "migration-backup"
ARCHIVE_SIZE=$(du -h "$HOME/Desktop/$ARCHIVE_NAME" | cut -f1)
echo ""
echo "=========================================="
echo " Backup complete!"
echo " File: ~/Desktop/$ARCHIVE_NAME"
echo " Size: $ARCHIVE_SIZE"
echo "=========================================="
echo ""
echo "Transfer this file to the new machine via USB or AirDrop,"
echo "then run restore.sh followed by dotfiles/bootstrap."
