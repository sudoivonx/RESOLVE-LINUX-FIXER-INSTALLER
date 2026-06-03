#!/bin/bash

# --- COLORS AND VISUALIZATION ---
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
BLUE="\033[34m"
CYAN="\033[36m"
YELLOW="\033[33m"
RESET="\033[0m"

echo -e "${CYAN}#############################################################${RESET}"
echo -e "${CYAN}#     DAVINCI RESOLVE UNIVERSAL LINUX INSTALLER (ULTIMATE)  #${RESET}"
echo -e "${CYAN}#        (Ubuntu 24.04+ / Fedora / Arch / Debian Supported)     #${RESET}"
echo -e "${CYAN}#############################################################${RESET}"

# 1. ROOT CHECK
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ ERROR: This script requires administrator privileges.${RESET}"
  echo -e "Please run it like this: ${BOLD}sudo ./setup.sh${RESET}"
  exit
fi

# 2. SYSTEM DETECTION
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
    echo -e "${GREEN}✅ System Detected: ${BOLD}${NAME} (${VERSION_ID})${RESET}"
else
    echo -e "${RED}❌ Distribution information could not be read!${RESET}"
    exit 1
fi

# 3. DEPENDENCIES AND HACK FUNCTIONS
install_dependencies() {
    echo -e "${BLUE}🔧 Analyzing system dependencies...${RESET}"
    
    case $OS in
        ubuntu|debian|linuxmint|pop|kali|neon)
            apt update
            
            # --- UBUNTU 24.04 / DEBIAN 13 SPECIFIC FIX (t64 Transition) ---
            # In newer systems, 't64' is appended to packages, DaVinci is unaware of this.
            # This block attempts both old and new packages.
            
            PKGS="libapr1 libaprutil1 libglib2.0-0 libxcb-composite0 libxcb-cursor0 \
            libxcb-xinerama0 libxcb-xinput0 libxcb-icccm4 libxcb-render-util0 \
            libxcb-shape0 libxkbcommon-x11-0 libnvidia-encode-any nvidia-cuda-toolkit"
            
            # Smart check for libasound2 issue
            if apt-cache show libasound2 >/dev/null 2>&1; then
                PKGS="$PKGS libasound2"
            else
                echo -e "${YELLOW}⚠️  Old 'libasound2' not found (Modern system). Installing 'libasound2t64'...${RESET}"
                PKGS="$PKGS libasound2t64"
                NEEDS_SYMLINK_ASOUND=true
            fi

             # Smart check for libapr issue
            if ! apt-cache show libapr1 >/dev/null 2>&1; then
                 PKGS="$PKGS libapr1t64 libaprutil1t64"
                 NEEDS_SYMLINK_APR=true
            fi

            apt install -y $PKGS
            ;;
        
        fedora|nobara)
            echo -e "${BLUE}📦 Installing Fedora/Nobara packages...${RESET}"
            dnf install -y apr apr-util alsa-lib mesa-libGLU libxcb libX11 libXext libXfixes \
            libXi libXrender libXcursor libXinerama libxkbcommon-x11 xorg-x11-drv-nvidia-cuda
            ;;
            
        arch|manjaro|endeavouros)
            echo -e "${BLUE}📦 Installing Arch Linux packages...${RESET}"
            pacman -S --needed --noconfirm base-devel apr apr-util alsa-lib mesa-libglu \
            libxcb libx11 libxext libxfixes libxi libxrender libxcursor libxinerama \
            libxkbcommon-x11 nvidia-utils opencl-nvidia
            ;;
    esac
}

# 4. SYMLINK HACK (CRITICAL SECTION FOR Ubuntu 24.04+)
apply_symlink_hacks() {
    echo -e "${BLUE}🔗 Checking compatibility bridges (Symlinks)...${RESET}"
    
    # The library path is usually here on Debian/Ubuntu based systems
    LIB_PATH="/usr/lib/x86_64-linux-gnu"
    
    if [ "$NEEDS_SYMLINK_ASOUND" = true ]; then
        if [ -f "$LIB_PATH/libasound.so.2" ] && [ ! -f "$LIB_PATH/libasound2.so.2" ]; then
            echo -e "${YELLOW}🛠️  FIX: Masking libasound2t64 -> libasound2...${RESET}"
            ln -s "$LIB_PATH/libasound.so.2" "$LIB_PATH/libasound2.so.2"
        fi
    fi
    
    # DaVinci sometimes asks for libglib-2.0-0 but the system has libglib-2.0
    if [ -f "$LIB_PATH/libglib-2.0.so.0" ] && [ ! -f "$LIB_PATH/libglib-2.0-0.so.0" ]; then
         echo -e "${YELLOW}🛠️  FIX: Correcting GLib naming...${RESET}"
         ln -s "$LIB_PATH/libglib-2.0.so.0" "$LIB_PATH/libglib-2.0-0.so.0"
    fi
    
    # Refresh system libraries
    ldconfig
    echo -e "${GREEN}✅ Library paths patched.${RESET}"
}

# --- PROCESS STARTING ---

install_dependencies
if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS" == "pop" || "$OS" == "linuxmint" ]]; then
    apply_symlink_hacks
fi

echo ""
echo -e "${CYAN}📂 Please drag the downloaded .run file into the terminal and press ENTER:${RESET}"
read -r INSTALLER_PATH
INSTALLER_PATH=$(echo $INSTALLER_PATH | tr -d "'\"")

if [ -f "$INSTALLER_PATH" ]; then
    echo -e "${GREEN}🚀 Starting DaVinci Resolve Installer...${RESET}"
    echo -e "${YELLOW}Info: Installation wizard will open. Even if it throws an error, continue if the 'Next' buttons are active.${RESET}"
    
    chmod +x "$INSTALLER_PATH"
    
    # Trying to bypass package check with --appimage-extract-and-run
    # The SKIP_PACKAGE_CHECK=1 variable skips the check in some versions
    SKIP_PACKAGE_CHECK=1 "$INSTALLER_PATH" --appimage-extract-and-run
else
    echo -e "${RED}❌ File not found!${RESET}"
fi

echo -e "${GREEN}🏁 Script has completed its task.${RESET}"
echo -e "${YELLOW}If the installation is successful, make sure to RESTART before opening the program.${RESET}"
