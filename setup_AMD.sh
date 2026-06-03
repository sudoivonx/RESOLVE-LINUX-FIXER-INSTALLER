#!/bin/bash

# --- COLORS ---
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
BLUE="\033[34m"
CYAN="\033[36m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${RED}#############################################################${RESET}"
echo -e "${RED}#        DAVINCI RESOLVE INSTALLER (AMD EDITION)            #${RESET}"
echo -e "${RED}#        (OpenCL Drivers and Required Patches)              #${RESET}"
echo -e "${RED}#############################################################${RESET}"

# 1. ROOT CHECK
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}❌ Please run with administrator privileges: sudo ./setup_amd.sh${RESET}"
  exit
fi

# 2. SYSTEM DETECTION
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}❌ Distribution information could not be read!${RESET}"
    exit 1
fi

# 3. DEPENDENCIES (AMD SPECIFIC)
install_dependencies() {
    echo -e "${BLUE}🔧 Preparing AMD OpenCL and System libraries...${RESET}"
    
    case $OS in
        ubuntu|debian|linuxmint|pop|kali|neon)
            apt update
            
            # Base Packages + AMD OpenCL (mesa-opencl-icd)
            PKGS="libapr1 libaprutil1 libglib2.0-0 libxcb-composite0 libxcb-cursor0 \
            libxcb-xinerama0 libxcb-xinput0 libxcb-icccm4 libxcb-render-util0 \
            libxcb-shape0 libxkbcommon-x11-0 mesa-opencl-icd ocl-icd-libopencl1 opencl-headers"
            
            # t64 (Ubuntu 24.04+) Check
            if apt-cache show libasound2 >/dev/null 2>&1; then
                PKGS="$PKGS libasound2"
            else
                PKGS="$PKGS libasound2t64"
                NEEDS_SYMLINK_ASOUND=true
            fi
            
            # libapr Check
            if ! apt-cache show libapr1 >/dev/null 2>&1; then
                 PKGS="$PKGS libapr1t64 libaprutil1t64"
            fi

            apt install -y $PKGS
            ;;
        
        fedora|nobara)
            # AMD Packages for Fedora
            dnf install -y apr apr-util alsa-lib mesa-libGLU libxcb libX11 libXext \
            libXfixes libXi libXrender libXcursor libXinerama libxkbcommon-x11 \
            mesa-libOpenCL ocl-icd
            ;;
            
        arch|manjaro|endeavouros)
            # AMD Packages for Arch
            pacman -S --needed --noconfirm base-devel apr apr-util alsa-lib mesa-libglu \
            libxcb libx11 libxext libxfixes libxi libxrender libxcursor libxinerama \
            libxkbcommon-x11 opencl-mesa ocl-icd
            ;;
    esac
}

# 4. SYMLINK HACK (Only for Debian/Ubuntu)
apply_symlink_hacks() {
    LIB_PATH="/usr/lib/x86_64-linux-gnu"
    if [ "$NEEDS_SYMLINK_ASOUND" = true ]; then
        if [ -f "$LIB_PATH/libasound.so.2" ] && [ ! -f "$LIB_PATH/libasound2.so.2" ]; then
            echo -e "${YELLOW}🛠️  Applying sound card patch...${RESET}"
            ln -s "$LIB_PATH/libasound.so.2" "$LIB_PATH/libasound2.so.2"
            ldconfig
        fi
    fi
}

# --- EXECUTION ---
install_dependencies
if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS" == "pop" || "$OS" == "linuxmint" ]]; then
    apply_symlink_hacks
fi

echo ""
echo -e "${CYAN}📂 Please drag the downloaded .run file into the terminal and press ENTER:${RESET}"
read -r INSTALLER_PATH
INSTALLER_PATH=$(echo $INSTALLER_PATH | tr -d "'\"")

if [ -f "$INSTALLER_PATH" ]; then
    chmod +x "$INSTALLER_PATH"
    echo -e "${GREEN}🚀 Starting Installation...${RESET}"
    SKIP_PACKAGE_CHECK=1 "$INSTALLER_PATH" --appimage-extract-and-run
else
    echo -e "${RED}❌ File not found!${RESET}"
fi
