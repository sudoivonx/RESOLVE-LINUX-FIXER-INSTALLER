#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}##################################################${NC}"
echo -e "${BLUE}#      DAVINCI RESOLVE LIBRARY FIX TOOL          #${NC}"
echo -e "${BLUE}##################################################${NC}"

# Root check
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Please run as administrator: sudo ./davinci_fix.sh${NC}"
  exit
fi

echo -e "${BLUE}Step 1: Installing missing system packages...${NC}"
# Tries both old and new (t64) package names
apt update
apt install -y libapr1 libaprutil1 libglib2.0-0 libxcb-composite0 \
libxcb-cursor0 libxcb-xinerama0 libxcb-xinput0 libxcb-icccm4 \
libxcb-render-util0 libxcb-shape0 libxkbcommon-x11-0 \
libasound2 libasound2t64 2>/dev/null

echo -e "${GREEN}✅ Package installation complete (or already installed).${NC}"

echo -e "${BLUE}Step 2: Cleaning up conflicting 'glib' libraries...${NC}"
# DaVinci's own old libraries conflict with the system, hiding them.

RESOLVE_LIBS="/opt/resolve/libs"
BACKUP_DIR="$RESOLVE_LIBS/disabled-libraries"

# Create backup folder
mkdir -p "$BACKUP_DIR"

# Move problematic files
mv -v "$RESOLVE_LIBS"/libglib-2.0.so* "$BACKUP_DIR"/ 2>/dev/null
mv -v "$RESOLVE_LIBS"/libgio-2.0.so* "$BACKUP_DIR"/ 2>/dev/null
mv -v "$RESOLVE_LIBS"/libgmodule-2.0.so* "$BACKUP_DIR"/ 2>/dev/null
mv -v "$RESOLVE_LIBS"/libonig.so* "$BACKUP_DIR"/ 2>/dev/null

echo -e "${GREEN}✅ Conflicting files moved into '$BACKUP_DIR'.${NC}"

echo -e "${BLUE}Step 3: Checking Symbolic Links...${NC}"
# Patch for libasound2 error
if [ -f /usr/lib/x86_64-linux-gnu/libasound.so.2 ] && [ ! -f /usr/lib/x86_64-linux-gnu/libasound2.so.2 ]; then
    ln -s /usr/lib/x86_64-linux-gnu/libasound.so.2 /usr/lib/x86_64-linux-gnu/libasound2.so.2
    echo "🔗 libasound2 link created."
fi

ldconfig
echo -e "${GREEN}🎉 PROCESS COMPLETE! You can try opening DaVinci Resolve.${NC}"
