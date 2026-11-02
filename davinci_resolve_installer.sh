#!/usr/bin/env bash
# =====================================================================
#  DaVinci Resolve - Evrensel Linux Kurulum / Onarım Scripti
#
#  Desteklenen aileler : Debian/Ubuntu (Zorin, Mint, Pop!_OS, Kali...)
#                        Fedora/RHEL   (Nobara, Alma, Rocky...)
#                        Arch          (Manjaro, EndeavourOS, CachyOS...)
#  Ekran kartı         : NVIDIA ve AMD otomatik tespit edilip ona göre hazırlanır
#                        (Intel: yalnızca bilgi; Blackmagic Linux'ta resmi destek vermiyor)
#
#  Kullanım: sadece çalıştır, gerisini script kendisi halleder (sudo'yu da kendisi ister):
#    ./davinci_resolve_installer.sh
#      - Resolve kurulu değilse        -> kurulum dosyasını bulur/sorar, KURAR
#      - Kurulu ve dosya yoksa         -> kurulu Resolve'u otomatik ONARIR
#      - Kurulu ve yeni dosya varsa    -> "kur/güncelle mi, onar mı?" diye tek soru sorar
#  İsteğe bağlı (çoğu kişiye gerekmez):
#    ./davinci_resolve_installer.sh DOSYA.zip|.run  # dosyayı elle ver
#    ./davinci_resolve_installer.sh --gui           # grafik sihirbaz (varsayılan: terminal kurulumu)
#    ./davinci_resolve_installer.sh --fix           # zorla onarım
#
#  Sorun olursa günlük dosyası: ~/davinci-installer.log
# =====================================================================
set -u
# sh/dash ile başlatıldıysa bash ile yeniden başlat
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

# ---------- Renkler / günlük ----------
BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; BLUE=$'\033[34m'
CYAN=$'\033[36m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'

LOG=""
_log() {
  [ -n "$LOG" ] || return 0
  printf '%s %s\n' "$(date +%H:%M:%S)" "$(printf '%s' "$*" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOG" 2>/dev/null
  return 0
}
info() { printf '%s\n' "${BLUE}🔧 $*${RESET}";           _log "INFO  $*"; }
ok()   { printf '%s\n' "${GREEN}✅ $*${RESET}";           _log "OK    $*"; }
warn() { printf '%s\n' "${YELLOW}⚠️  $*${RESET}";         _log "WARN  $*"; }
err()  { printf '%s\n' "${RED}❌ $*${RESET}" >&2;        _log "ERROR $*"; }

# ---------- Genel değişkenler ----------
MODE="auto"                     # auto = durumu tespit edip kurulum/onarımı kendisi seçer
AUTO_FIX_HINT=0
USE_CLI=1                      # varsayılan: terminal kurulumu (ekran erişimi sorunlarından etkilenmez)
INSTALLER_PATH=""
RESOLVE_DIR="${RESOLVE_DIR:-/opt/resolve}"
WORKDIR=""
ERRFILE=""
START_TS=0
XHOST_GRANTED=0
X_ENVS=()
FAMILY=""
OS_ID=""; OS_LIKE=""; OS_PRETTY=""
ORIG_ARGS="$*"
QT_FAIL_RE='Qt platform plugin|could not connect to display|Authorization required|no Qt platform'
GPU_NVIDIA=0; GPU_AMD=0; GPU_INTEL=0
GPU_MODE=""                    # nvidia | amd | intel | skip | none
PCI_DIR="${PCI_DIR:-/sys/bus/pci/devices}"
KFD_NODES="${KFD_NODES:-/sys/class/kfd/kfd/topology/nodes}"
LAUNCH_ENV="QT_QPA_PLATFORM=xcb"   # menü kısayoluna eklenecek ortam değişkenleri
GROUPS_CHANGED=0
AMD_OTHER="rocm"              # başarısızlıkta önerilecek "diğer" AMD OpenCL yığını

usage() {
cat <<EOF
Kullanım: $0 [seçenekler] [kurulum_dosyası.run|.zip]

  (seçenek yok)  OTOMATİK: Resolve kurulu değilse kurar; kuruluysa ve yeni dosya yoksa onarır;
                 ikisi de varsa tek bir soru sorar. Kurulum terminalden yapılır (her ortamda çalışır).
  dosya_yolu     Belirtilen .run/.zip ile kurar/günceller (sormadan)
  --gui          Grafik kurulum sihirbazını kullan (ekran erişimi otomatik ayarlanır)
  --fix          Zorla onarım: bağımlılıklar + glib çakışması + eksik kütüphaneler
  -h, --help     Bu yardım

Ortam değişkenleri (isteğe bağlı):
  DAVINCI_WORKDIR=/yol   Geçici dosyalar için dizin (varsayılan: /var/tmp, sonra ~/.cache)
  DAVINCI_MIN_GB=12      Geçici dizin için gereken en az boş alan (GB)
  DAVINCI_QPA=minimal    Qt platformunu elle seç (varsayılan: terminalde offscreen→minimal, grafikte xcb)
  RESOLVE_DIR=/yol       Resolve kurulum dizini (varsayılan: /opt/resolve)
  DAVINCI_NO_TEE=1       Installer hata çıktısını yakalamayı kapat (installer soruları görünmezse kullanın)
  DAVINCI_GPU=amd        Ekran kartı seçimini zorla: auto (varsayılan) | nvidia | amd | skip
  DAVINCI_AMD_STACK=rocm AMD OpenCL yığınını zorla: auto (varsayılan: Mesa) | mesa | rocm | skip
EOF
}

banner() {
  echo -e "${CYAN}#############################################################${RESET}"
  echo -e "${CYAN}#   DAVINCI RESOLVE LINUX KURULUM / ONARIM (Debian·Fedora·Arch)  #${RESET}"
  echo -e "${CYAN}#############################################################${RESET}"
}

parse_args() {
  local a
  for a in "$@"; do
    case "$a" in
      --fix)     MODE="fix" ;;
      --cli)     USE_CLI=1 ;;
      --gui)     USE_CLI=0 ;;
      -h|--help) usage; exit 0 ;;
      -*)        err "Bilinmeyen seçenek: $a"; usage; exit 1 ;;
      *)         INSTALLER_PATH="$a" ;;
    esac
  done
}

# Root değilsek sudo ile kendimizi yeniden başlat
require_root() {
  [ "$EUID" -eq 0 ] && return 0
  if command -v sudo >/dev/null 2>&1; then
    echo -e "${YELLOW}Yönetici yetkisi gerekiyor; sudo ile yeniden başlatılıyor...${RESET}"
    exec sudo -E bash "$0" "$@"
  fi
  err "Bu script yönetici yetkisi gerektirir ve sudo bulunamadı. root olarak çalıştırın."
  exit 1
}

init_user() {
  REAL_USER="${SUDO_USER:-root}"
  REAL_UID=$(id -u "$REAL_USER" 2>/dev/null || echo 0)
  REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)
  [ -n "$REAL_HOME" ] || REAL_HOME="/root"
}

setup_log() {
  LOG="$REAL_HOME/davinci-installer.log"
  if ! : > "$LOG" 2>/dev/null; then LOG="/tmp/davinci-installer.log"; : > "$LOG" 2>/dev/null || LOG=""; fi
  [ -n "$LOG" ] && chown "$REAL_USER" "$LOG" 2>/dev/null
  _log "=== davinci_resolve_installer: $(date) | args: $ORIG_ARGS ==="
  _log "kernel: $(uname -r) | arch: $(uname -m) | kullanıcı: $REAL_USER"
  return 0
}

run_as_user() {
  if [ "$REAL_USER" = "root" ]; then "$@"; else sudo -u "$REAL_USER" -H "$@"; fi
}

check_arch() {
  if [ "$(uname -m)" != "x86_64" ]; then
    err "DaVinci Resolve'un Linux sürümü yalnızca x86_64 (64-bit Intel/AMD) destekler. Bu sistem: $(uname -m)"
    exit 1
  fi
}

# ---------- Sistem tespiti ----------
# ID ve ID_LIKE'tan aile bulur (Zorin, Nobara, CachyOS... otomatik tanınır)
family_from_ids() {
  local t
  for t in "$@"; do
    case "$t" in
      debian|ubuntu)       echo "debian"; return 0 ;;
      fedora|rhel|centos)  echo "fedora"; return 0 ;;
      arch)                echo "arch";   return 0 ;;
    esac
  done
  return 0
}

detect_os() {
  local line rest
  if [ -f /etc/os-release ]; then
    line=$(. /etc/os-release; printf '%s|%s|%s' "${ID:-}" "${ID_LIKE:-}" "${PRETTY_NAME:-${NAME:-Linux}}")
    OS_ID=${line%%|*}; rest=${line#*|}; OS_LIKE=${rest%%|*}; OS_PRETTY=${rest#*|}
  else
    OS_PRETTY="Bilinmeyen Linux"
  fi
  # shellcheck disable=SC2086
  FAMILY=$(family_from_ids $OS_ID $OS_LIKE)
  if [ -z "$FAMILY" ]; then   # ID'den anlaşılmadıysa paket yöneticisinden bul
    if   command -v apt-get >/dev/null 2>&1; then FAMILY="debian"
    elif command -v dnf     >/dev/null 2>&1; then FAMILY="fedora"
    elif command -v pacman  >/dev/null 2>&1; then FAMILY="arch"
    fi
  fi
  ok "Sistem: ${OS_PRETTY} (aile: ${FAMILY:-bilinmiyor})"

  if [ -e /run/ostree-booted ]; then
    err "Değişmez (immutable/ostree) bir sistem algılandı (Silverblue, Bazzite vb.)."
    echo "Bu sistemlerde sistem paketleri yazılabilir değil. Distrobox içinde (Ubuntu/Arch konteyneri) kurmanız önerilir."
    exit 1
  fi
}

check_nvidia() {
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    ok "NVIDIA GPU görüldü: $(nvidia-smi -L | head -n1)"
  else
    warn "NVIDIA sürücüsü çalışmıyor ya da kurulu değil (nvidia-smi başarısız)."
    echo "   Resolve GPU bulamazsa açılmaz. Fedora: RPM Fusion akmod-nvidia | Arch: nvidia/nvidia-open | Ubuntu: ubuntu-drivers install"
  fi
}

# ---------- Ekran kartı tespiti ve üreticiye özel hazırlık ----------
# Resolve'un GPU işlemesi: NVIDIA -> CUDA (sürücü paketiyle gelir) | AMD -> OpenCL (ROCm ya da Mesa/Rusticl)
detect_gpus() {
  local d c v
  GPU_NVIDIA=0; GPU_AMD=0; GPU_INTEL=0
  for d in "$PCI_DIR"/*; do
    [ -r "$d/class" ] || continue
    c=$(cat "$d/class" 2>/dev/null)
    case "$c" in 0x03*) ;; *) continue ;; esac   # 0x03xxxx = ekran denetleyicisi (VGA / 3D / Display)
    v=$(cat "$d/vendor" 2>/dev/null)
    case "$v" in
      0x10de) GPU_NVIDIA=1 ;;
      0x1002) GPU_AMD=1 ;;
      0x8086) GPU_INTEL=1 ;;
    esac
  done
  # PCI bilgisi okunamıyorsa (bazı sanal ortamlar) araçlardan tahmin et
  if [ "$GPU_NVIDIA$GPU_AMD$GPU_INTEL" = "000" ]; then
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then GPU_NVIDIA=1; fi
    if [ -d "$KFD_NODES" ]; then GPU_AMD=1; fi
  fi
}

select_gpu_mode() {
  case "${DAVINCI_GPU:-auto}" in
    nvidia|amd|skip) GPU_MODE="$DAVINCI_GPU"; return 0 ;;
  esac
  if   [ "$GPU_NVIDIA" = 1 ]; then GPU_MODE="nvidia"
  elif [ "$GPU_AMD" = 1 ];    then GPU_MODE="amd"
  elif [ "$GPU_INTEL" = 1 ];  then GPU_MODE="intel"
  else GPU_MODE="none"; fi
}

report_gpus() {
  local found=()
  [ "$GPU_NVIDIA" = 1 ] && found+=("NVIDIA")
  [ "$GPU_AMD" = 1 ]    && found+=("AMD")
  [ "$GPU_INTEL" = 1 ]  && found+=("Intel")
  if [ "${#found[@]}" -eq 0 ]; then
    warn "Ekran kartı tespit edilemedi (sanal makine/konteyner olabilir)."
  else
    ok "Ekran kartı üreticileri: ${found[*]} → Resolve için hazırlanacak: $GPU_MODE"
  fi
  if [ "${#found[@]}" -gt 1 ] && [ "$GPU_MODE" = "nvidia" ]; then
    info "Hibrit grafik: Resolve'un GPU işlemleri için NVIDIA kullanılacak (diğeri ekran çıkışı için kalır)."
  fi
}

# ---- AMD ----
user_in_group() { id -nG "$REAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$1"; }

# AMD GPU'ya erişim için kullanıcı 'render' ve 'video' gruplarında olmalı (AMD'nin resmi kurulum kılavuzu da bunu ister)
amd_fix_groups() {
  local g added=() failed=()
  [ "$REAL_USER" = "root" ] && return 0
  for g in render video; do
    getent group "$g" >/dev/null 2>&1 || continue
    user_in_group "$g" && continue
    if usermod -aG "$g" "$REAL_USER" 2>/dev/null; then added+=("$g"); else failed+=("$g"); fi
  done
  if [ "${#failed[@]}" -gt 0 ]; then
    warn "$REAL_USER kullanıcısı şu gruplara eklenemedi: ${failed[*]}. Elle: sudo usermod -aG render,video $REAL_USER"
  fi
  if [ "${#added[@]}" -gt 0 ]; then
    GROUPS_CHANGED=1
    ok "$REAL_USER kullanıcısı şu gruplara eklendi: ${added[*]} (AMD GPU erişimi için gerekli)."
  fi
}

# En düşük GPU mimarisi (çekirdeğin KFD arayüzünden): 110000 = gfx1100, 90006 = gfx906, 80003 = gfx803 (Polaris). Bilinmiyorsa boş.
amd_min_gfx() {
  local f v min=""
  for f in "$KFD_NODES"/*/properties; do
    [ -r "$f" ] || continue
    v=$(awk '$1=="gfx_target_version" {print $2}' "$f" 2>/dev/null)
    case "$v" in ''|0|*[!0-9]*) continue ;; esac
    if [ -z "$min" ] || [ "$v" -lt "$min" ]; then min="$v"; fi
  done
  printf '%s' "$min"
}

# KFD sayısını GPU adına çevirir: 80003 -> gfx803, 90010 -> gfx90a, 110000 -> gfx1100
gfx_name() {
  local v=$1
  printf 'gfx%d%d%x' $((v / 10000)) $(((v / 100) % 100)) $((v % 100))
}

# clinfo'yu kullanıcı olarak çalıştırır (izinler de test edilir).
# RUSTICL_ENABLE: Mesa'nın Rusticl'i dağıtım derlemesine göre radeonsi'yi bununla ister (diğer yığınlarda zararsız).
# ROC_ENABLE_PRE_VEGA: Vega'dan eski kartlarda ROCm için gerekli.
amd_clinfo() {
  local gfx envs=(RUSTICL_ENABLE=radeonsi)
  gfx=$(amd_min_gfx)
  if [ -n "$gfx" ] && [ "$gfx" -lt 90000 ]; then envs+=(ROC_ENABLE_PRE_VEGA=1); fi
  run_as_user env "${envs[@]}" clinfo 2>/dev/null
}
amd_clinfo_has() { amd_clinfo | grep -qiE "$1"; }

# GPU tipi bir OpenCL aygıtı var mı ve Resolve'un istediği OpenCL 1.2+ sürümünü veriyor mu?
#   ok   = evet | old = GPU var ama yalnızca OpenCL 1.1 (eski Mesa 'Clover') | none = GPU aygıtı yok
amd_opencl_status() {
  command -v clinfo >/dev/null 2>&1 || { echo none; return; }
  amd_clinfo | awk '
    /^[ \t]*Device Name/    { dev++ }
    /^[ \t]*Device Version/ { if (match($0, /OpenCL [0-9]+\.[0-9]+/)) ver[dev] = substr($0, RSTART + 7, RLENGTH - 7) }
    /^[ \t]*Device Type/    { if ($0 ~ /GPU/) gpu[dev] = 1 }
    END {
      state = "none"
      for (i = 1; i <= dev; i++) if (gpu[i]) {
        split(ver[i], a, ".")
        if (a[1] + 0 > 1 || (a[1] + 0 == 1 && a[2] + 0 >= 2)) { state = "ok"; break }
        state = "old"
      }
      print state
    }'
}
amd_opencl_ok() { [ "$(amd_opencl_status)" = ok ]; }

pkg_has_candidate_debian() { apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ { if ($2 != "(none)") ok=1 } END { exit !ok }'; }

# $1 = rocm | mesa. Yalnızca dağıtımın kendi depolarındaki paketler kurulur (3. taraf depo / AUR eklenmez).
amd_install_stack() {
  case "$1:$FAMILY" in
    rocm:arch)
      if pacman -Qq opencl-amd >/dev/null 2>&1; then
        warn "opencl-amd (AUR) kurulu: rocm-opencl-runtime ile çakışıp Resolve'u açılmaz hale getirebilir; ROCm paketi kurulmadı."
        return 1
      fi
      pm_install rocm-opencl-runtime clinfo ;;
    rocm:fedora) pm_install rocm-opencl clinfo ;;
    rocm:debian)
      if pkg_has_candidate_debian rocm-opencl-icd; then
        pm_install rocm-opencl-icd clinfo
      else
        warn "Bu dağıtım sürümünün depolarında rocm-opencl-icd yok."
        echo "   AMD'nin resmi yolu 3. taraf depo + çekirdek sürücüsü ekler, bu yüzden otomatik yapılmaz:"
        echo "   rocm.docs.amd.com -> 'Install Radeon software for Linux with ROCm' (amdgpu-install)"
        echo "   (Mesa/Rusticl yığını varsayılandır: DAVINCI_AMD_STACK=mesa)"
        return 1
      fi ;;
    mesa:arch)   pm_install opencl-mesa clinfo ;;
    mesa:fedora) pm_install mesa-libOpenCL clinfo ;;
    mesa:debian) pm_install mesa-opencl-icd ocl-icd-libopencl1 clinfo ;;
    *) warn "Bu dağıtım ailesi için AMD OpenCL kurulumu tanımlı değil ($1:$FAMILY)."; return 1 ;;
  esac
  return 0
}

# Menü kısayoluna eklenecek AMD'ye özel ortam değişkenleri
amd_launch_env() {
  local gfx
  if amd_clinfo_has 'rusticl'; then
    LAUNCH_ENV="$LAUNCH_ENV RUSTICL_ENABLE=radeonsi"      # eski Mesa sürümleri radeonsi'yi açıkça ister
    AMD_OTHER="rocm"
  fi
  if amd_clinfo_has 'AMD Accelerated Parallel Processing'; then
    AMD_OTHER="mesa"                                      # ROCm platformu görünüyorsa, alternatif Mesa'dır
  fi
  gfx=$(amd_min_gfx)
  if [ -n "$gfx" ] && [ "$gfx" -lt 90000 ] && amd_clinfo_has 'AMD Accelerated Parallel Processing'; then
    LAUNCH_ENV="$LAUNCH_ENV ROC_ENABLE_PRE_VEGA=1"        # Vega'dan eski kartlarda ROCm için gerekli
    info "Vega öncesi AMD GPU ($(gfx_name "$gfx")): ROC_ENABLE_PRE_VEGA=1 menü kısayoluna eklenecek."
  fi
}

setup_gpu_amd() {
  local want="${DAVINCI_AMD_STACK:-auto}" stack="mesa" other="rocm" forced=0 st
  info "AMD ekran kartı: OpenCL ortamı kontrol ediliyor..."
  amd_fix_groups

  case "$want" in
    skip)      info "AMD OpenCL kurulumu atlandı (DAVINCI_AMD_STACK=skip)."; return 0 ;;
    rocm|mesa) forced=1; stack="$want" ;;
  esac
  [ "$stack" = "rocm" ] && other="mesa"                     # başarısızlıkta önerilecek "diğer" yığın

  command -v clinfo >/dev/null 2>&1 || pm_install clinfo   # durumu görebilmek için gerekli

  st=$(amd_opencl_status)
  if [ "$forced" = 0 ] && [ "$st" = ok ]; then
    ok "Çalışan bir OpenCL (1.2+) GPU ortamı zaten var; AMD paketlerine dokunulmayacak."
  elif [ "$forced" = 0 ] && [ "$st" = old ]; then
    # Üstüne başka bir yığın kurmak çakışma riski taşır; kullanıcıyı yönlendiriyoruz
    warn "Yalnızca OpenCL 1.1 görünüyor (büyük olasılıkla eski Mesa 'Clover'); Resolve OpenCL 1.2 ister."
    echo "   Çözüm: dağıtımınızın daha yeni bir Mesa sürümüne güncellenmesi ya da ROCm:"
    echo "   DAVINCI_AMD_STACK=rocm ./davinci_resolve_installer.sh"
  else
    if [ "$forced" = 1 ]; then
      info "DAVINCI_AMD_STACK=$stack istendi: '$stack' OpenCL yığını kurulacak."
      warn "Aynı anda hem ROCm hem Mesa OpenCL kurulu olması bazı sistemlerde Resolve'u bozar; sorun olursa birini kaldırın."
    else
      info "AMD GPU için çalışan bir OpenCL ortamı bulunamadı; Mesa (Rusticl) OpenCL kuruluyor."
    fi
    amd_install_stack "$stack"
    st=$(amd_opencl_status)
    case "$st" in
      ok)  ok "OpenCL ortamı AMD GPU'yu görüyor (OpenCL 1.2+)." ;;
      old) warn "Hâlâ yalnızca OpenCL 1.1 (Clover) görünüyor: bu dağıtımın Mesa sürümü eski."
           echo "   Daha yeni Mesa ya da ROCm gerekir: DAVINCI_AMD_STACK=rocm ./davinci_resolve_installer.sh" ;;
      *)   warn "Kurulumdan sonra OpenCL GPU aygıtı görünmüyor."
           echo "   Olası nedenler: oturum henüz yenilenmedi (grup üyeliği), amdgpu/radeonsi sürücüsü yüklü değil, kart bu yığınca desteklenmiyor."
           echo "   Oturumu kapatıp açın ve 'clinfo' çalıştırın. Hâlâ yoksa: DAVINCI_AMD_STACK=$other ./davinci_resolve_installer.sh" ;;
    esac
  fi
  AMD_OTHER="$other"
  amd_launch_env
}

setup_gpu() {
  case "$GPU_MODE" in
    nvidia) check_nvidia ;;
    amd)    setup_gpu_amd ;;
    intel)  warn "Yalnızca Intel ekran kartı var. Blackmagic Linux'ta resmi olarak NVIDIA/AMD ister; Resolve açılmayabilir. Ek GPU kurulumu yapılmayacak." ;;
    skip)   info "GPU hazırlığı atlandı (DAVINCI_GPU=skip)." ;;
    *)      warn "GPU hazırlığı yapılmadı (ekran kartı tespit edilemedi)." ;;
  esac
}

gpu_final_notes() {
  if [ "$GROUPS_CHANGED" = 1 ]; then
    warn "AMD GPU erişimi için render/video gruplarına eklendiniz: değişikliğin geçerli olması için OTURUMU KAPATIP AÇIN (ya da yeniden başlatın)."
  fi
  if [ "$GPU_MODE" = "amd" ]; then
    echo -e "${YELLOW}AMD ipucu:${RESET} Resolve → Preferences → Memory and GPU → GPU Processing Mode: OpenCL. 'Unsupported GPU Processing Mode' çıkarsa oturumu yenileyip 'clinfo' ile kontrol edin; olmazsa DAVINCI_AMD_STACK=${AMD_OTHER} ile scripti tekrar çalıştırın."
  fi
}

# ---------- Paket kurulumu ----------
# Önce toplu dener; olmazsa paketleri TEK TEK kurar (tek hatalı paket hepsini iptal etmesin)
pm_install() {
  local p
  [ "$#" -gt 0 ] || return 0
  case "$FAMILY" in
    debian)
      apt-get install -y -o DPkg::Lock::Timeout=120 "$@" && return 0
      warn "Toplu kurulum başarısız; paketler tek tek deneniyor..."
      for p in "$@"; do apt-get install -y "$p" || warn "Kurulamadı: $p"; done ;;
    fedora)
      dnf install -y "$@" && return 0
      warn "Toplu kurulum başarısız; paketler tek tek deneniyor..."
      for p in "$@"; do dnf install -y "$p" || warn "Kurulamadı: $p"; done ;;
    arch)
      pacman -S --needed --noconfirm "$@" && return 0
      warn "Toplu kurulum başarısız; paketler tek tek deneniyor (gerekirse 'sudo pacman -Syu' yapın)..."
      for p in "$@"; do pacman -S --needed --noconfirm "$p" || warn "Kurulamadı: $p"; done ;;
  esac
  return 0
}

install_deps_debian() {
  export DEBIAN_FRONTEND=noninteractive
  info "apt paket listesi güncelleniyor..."
  apt-get update || warn "apt update başarısız oldu (bozuk bir depo olabilir); eldeki listeyle devam ediliyor."
  # Aynı satırdaki isimler alternatiftir (24.04+/Debian 13 için t64 adı önce denenir)
  local want=(
    "libapr1t64 libapr1"
    "libaprutil1t64 libaprutil1"
    "libasound2t64 libasound2"
    "libglib2.0-0t64 libglib2.0-0"
    "libglu1-mesa"
    "libxkbcommon-x11-0"
    "libxcb-composite0" "libxcb-cursor0" "libxcb-icccm4" "libxcb-image0"
    "libxcb-keysyms1" "libxcb-randr0" "libxcb-render-util0" "libxcb-shape0"
    "libxcb-xfixes0" "libxcb-xinerama0" "libxcb-xinput0" "libxcb-xkb1"
    "x11-xserver-utils" "unzip"
  )
  local pkgs=() entry p chosen
  for entry in "${want[@]}"; do
    chosen=""
    for p in $entry; do
      if apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/ { if ($2 != "(none)") ok=1 } END { exit !ok }'; then
        chosen="$p"; break
      fi
    done
    if [ -n "$chosen" ]; then pkgs+=("$chosen"); else warn "Depoda bulunamadı, atlanıyor: $entry"; fi
  done
  pm_install "${pkgs[@]}"
}

install_deps_fedora() {
  local pkgs=(
    apr apr-util alsa-lib mesa-libGLU libxcrypt-compat glib2 libxkbcommon-x11
    xcb-util xcb-util-cursor xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm
    libxcb libX11 libXext libXfixes libXi libXrender libXcursor libXinerama libXrandr
    unzip xhost
  )
  info "dnf ile bağımlılıklar kuruluyor..."
  pm_install "${pkgs[@]}"
  # Eski Fedora sürümlerinde xhost bu pakette
  command -v xhost >/dev/null 2>&1 || dnf install -y xorg-x11-server-utils >/dev/null 2>&1 || true
  # NVIDIA CUDA kütüphaneleri: yalnızca RPM Fusion NVIDIA sürücüsü varsa denenir
  if rpm -q xorg-x11-drv-nvidia >/dev/null 2>&1 && ! rpm -q xorg-x11-drv-nvidia-cuda >/dev/null 2>&1; then
    dnf install -y xorg-x11-drv-nvidia-cuda || warn "xorg-x11-drv-nvidia-cuda kurulamadı (RPM Fusion aktif mi?)."
  fi
}

install_deps_arch() {
  local want=(
    apr apr-util alsa-lib glu glib2 libxcrypt-compat fontconfig unzip xorg-xhost
    libxcb xcb-util xcb-util-cursor xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm
    libx11 libxext libxfixes libxi libxrender libxcursor libxinerama libxrandr libxkbcommon-x11
  )
  pacman -Qq nvidia-utils >/dev/null 2>&1 && want+=(opencl-nvidia)
  local pkgs=() p
  for p in "${want[@]}"; do   # depoda olmayan paket tüm pacman işlemini iptal eder; önce süz
    if pacman -Si "$p" >/dev/null 2>&1; then pkgs+=("$p"); else warn "Depoda yok, atlanıyor: $p"; fi
  done
  info "pacman ile bağımlılıklar kuruluyor..."
  pm_install "${pkgs[@]}"
}

install_dependencies() {
  info "Sistem bağımlılıkları kuruluyor..."
  case "$FAMILY" in
    debian) install_deps_debian ;;
    fedora) install_deps_fedora ;;
    arch)   install_deps_arch ;;
    *)      warn "Dağıtım ailesi tanınamadı; bağımlılık adımı atlandı (kurulum yine de denenecek)." ;;
  esac
}

# ---------- Kurulu Resolve'u bul ----------
locate_resolve() {
  local f
  [ -x "$RESOLVE_DIR/bin/resolve" ] && return 0
  f=$(find /opt /usr/local -maxdepth 3 -type f -path '*/bin/resolve' 2>/dev/null | head -n1)
  if [ -n "$f" ]; then RESOLVE_DIR="${f%/bin/resolve}"; return 0; fi
  return 1
}

# Bu çalıştırmada gerçekten yeni dosya yazıldı mı? (inode değişim zamanı ctime ile; eski kurulum yanıltmasın)
resolve_freshly_installed() {
  locate_resolve || return 1
  [ "$(stat -c %Z "$RESOLVE_DIR/bin/resolve" 2>/dev/null || echo 0)" -ge "$START_TS" ]
}

# ---------- Resolve'un eski glib kütüphanelerini devre dışı bırak ----------
# Resolve kendi eski glib'ini getirir; yeni dağıtımlardaki pango/Qt ile çakışır. Dosyalar silinmez, yedeğe taşınır.
fix_glib_conflicts() {
  local libs="$RESOLVE_DIR/libs" bk="$RESOLVE_DIR/libs/disabled-libraries" n=0 pat f
  if [ ! -d "$libs" ]; then
    warn "$libs bulunamadı; Resolve kurulu değil, kütüphane yaması atlandı."
    return 1
  fi
  mkdir -p "$bk"
  for pat in libglib-2.0 libgio-2.0 libgmodule-2.0 libgobject-2.0 libgthread-2.0; do
    # Sistemde karşılığı yoksa paketle geleni BIRAKIYORUZ (Resolve'u bozmamak için)
    if ! ldconfig -p 2>/dev/null | grep -qF "$pat.so.0 ("; then
      warn "Sistemde $pat.so.0 yok; Resolve'un kendi sürümü bırakıldı."
      continue
    fi
    for f in "$libs/$pat".so*; do
      if [ -e "$f" ] || [ -L "$f" ]; then
        mv -v "$f" "$bk/" && n=$((n + 1))
      fi
    done
  done
  if [ "$n" -gt 0 ]; then
    ok "$n adet çakışan glib dosyası '$bk' içine taşındı."
  else
    info "Taşınacak çakışan glib dosyası yok (zaten temiz)."
  fi
}

# ---------- Eksik kütüphaneleri bul ve otomatik kur ----------
# Taranacak dosyalar: ana ikili + Qt xcb eklentileri. Eklentiler çalışma anında dlopen ile yüklendiği için
# ana ikilinin ldd çıktısında görünmezler; eksik xcb-* kütüphaneleri en sık burada ortaya çıkar.
resolve_scan_targets() {
  printf '%s\n' "$RESOLVE_DIR/bin/resolve"
  find "$RESOLVE_DIR" -maxdepth 6 -path '*/disabled-libraries' -prune -o -type f -name 'libqxcb*.so' -print 2>/dev/null
}

# Sistemde eksik olan kütüphanelerin soname listesi.
# - Resolve'un kendi libs dizini aramaya dahil edilir (kendi kütüphaneleri "eksik" görünmesin)
# - Resolve dizininde zaten bulunan adlar elenir (yedek klasör 'disabled-libraries' hariç: oraya taşınanlar sistemden gelmeli)
missing_sonames() {
  local t so found raw="" ld="$RESOLVE_DIR/libs:$RESOLVE_DIR/bin"
  while IFS= read -r t; do
    [ -f "$t" ] || continue
    raw+=$(LD_LIBRARY_PATH="$ld${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$t" 2>/dev/null | awk '/not found/ {print $1}')
    raw+=$'\n'
  done < <(resolve_scan_targets)
  while IFS= read -r so; do
    [ -n "$so" ] || continue
    found=$(find "$RESOLVE_DIR" -path '*/disabled-libraries' -prune -o -name "$so" -print -quit 2>/dev/null)
    [ -n "$found" ] || printf '%s\n' "$so"
  done < <(printf '%s' "$raw" | sort -u)
}

# soname -> kurulacak paket (stdout). Fedora'da soname'in kendisi "capability" olarak kurulabilir.
so_to_pkg() {
  local so="$1" re
  case "$FAMILY" in
    fedora) printf '%s' "${so}()(64bit)" ;;
    arch)   pacman -F "$so" 2>/dev/null \
              | awk '/^[^ \t]/ {pkg=$1} /^[ \t]+usr\/lib\// {print pkg; exit}' \
              | sed 's|^[^/]*/||' ;;
    debian) re="/x86_64-linux-gnu/${so//./\\.}\$"
            apt-file search --regexp "$re" 2>/dev/null | head -n1 | cut -d: -f1 ;;
  esac
}

auto_fix_missing_libs() {
  local list="$1" so pkg n=0 pkgs=()
  case "$FAMILY" in
    arch)   info "Pacman dosya veritabanı eşitleniyor (pacman -Fy)..."; pacman -Fy >/dev/null 2>&1 || warn "pacman -Fy başarısız." ;;
    debian) info "apt-file hazırlanıyor..."
            command -v apt-file >/dev/null 2>&1 || apt-get install -y apt-file >/dev/null 2>&1
            apt-file update >/dev/null 2>&1 || warn "apt-file update başarısız." ;;
    fedora) ;;
    *)      return 0 ;;
  esac
  while IFS= read -r so; do
    [ -n "$so" ] || continue
    case "$so" in   # sürücü paketlerini otomatik kurmayız (sürücüyü bozabilir)
      libcuda*|libnvidia*|libnvcuvid*|libnvoptix*)
        warn "$so GPU sürücüsüyle gelir; otomatik kurulmayacak (sürücünüzü kontrol edin)."; continue ;;
    esac
    n=$((n + 1)); [ "$n" -gt 25 ] && break
    pkg=$(so_to_pkg "$so")
    if [ -n "$pkg" ]; then pkgs+=("$pkg"); info "$so -> $pkg"; else warn "$so için paket bulunamadı."; fi
  done <<< "$list"
  pm_install "${pkgs[@]}"
}

check_missing_libs() {
  [ -x "$RESOLVE_DIR/bin/resolve" ] || return 0
  local miss
  miss=$(missing_sonames)
  if [ -z "$miss" ]; then
    ok "Resolve'un tüm kütüphane bağımlılıkları çözüldü."
    return 0
  fi
  warn "Eksik kütüphaneler tespit edildi; otomatik kurulmaya çalışılacak:"
  printf '%s\n' "$miss" | sed 's/^/     /'
  auto_fix_missing_libs "$miss"
  miss=$(missing_sonames)
  if [ -z "$miss" ]; then
    ok "Eksik kütüphanelerin hepsi giderildi."
  else
    warn "Hâlâ eksik olanlar (elle kurulmalı):"
    printf '%s\n' "$miss" | sed 's/^/     /'
    echo "   Günlük: $LOG"
  fi
}

# Wayland oturumlarında QT_QPA_PLATFORM=wayland ayarlıysa Resolve (kendi Qt'sinde wayland eklentisi yok) açılmaz.
# Menü kısayolunun kullanıcıya özel bir kopyasını QT_QPA_PLATFORM=xcb ile oluşturuyoruz.
setup_launcher() {
  local src dst dstdir="$REAL_HOME/.local/share/applications" made=0
  for src in /usr/share/applications/com.blackmagicdesign.resolve*.desktop; do
    [ -f "$src" ] || continue
    grep -q "^Exec=.*$RESOLVE_DIR/bin/resolve" "$src" || continue
    run_as_user mkdir -p "$dstdir"
    dst="$dstdir/$(basename "$src")"
    sed -E "s|^Exec=|Exec=env ${LAUNCH_ENV} |" "$src" | run_as_user tee "$dst" >/dev/null
    made=1
  done
  if [ "$made" = 1 ]; then ok "Menü kısayolu şu ortam değişkenleriyle güncellendi: ${LAUNCH_ENV}"; fi
  return 0
}

# ---------- Kurulum dosyasını bul ----------
find_installer() {
  local dirs=() d f newest=""
  if command -v xdg-user-dir >/dev/null 2>&1; then
    d=$(run_as_user xdg-user-dir DOWNLOAD 2>/dev/null)
    [ -n "$d" ] && dirs+=("$d")
  fi
  dirs+=("$REAL_HOME/Downloads" "$REAL_HOME/İndirilenler" "$PWD" "$REAL_HOME")
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/DaVinci_Resolve*Linux*.run "$d"/DaVinci_Resolve*Linux*.zip; do
      [ -f "$f" ] || continue
      if [ -z "$newest" ] || [ "$f" -nt "$newest" ]; then newest="$f"; fi
    done
  done
  printf '%s' "$newest"
}

# Sürükle-bırak ile gelen tırnak / ters bölü (\ ) / ~ karakterlerini temizle
sanitize_path() {
  local p="$1"
  p=$(printf '%s' "$p" | sed -e "s/^[[:space:]]*['\"]//" -e "s/['\"][[:space:]]*\$//" -e 's/\\\(.\)/\1/g')
  case "$p" in "~/"*) p="$REAL_HOME/${p#\~/}" ;; esac
  printf '%s' "$p"
}

ask_installer() {
  local ans=""
  if [ -z "$INSTALLER_PATH" ]; then
    INSTALLER_PATH=$(find_installer)
    if [ -n "$INSTALLER_PATH" ]; then
      ok "Kurulum dosyası otomatik bulundu: $INSTALLER_PATH"
      read -r -p "Bu dosya kullanılsın mı? [E/h] " ans
      case "$ans" in [hHnN]*) INSTALLER_PATH="" ;; esac
    fi
  fi
  if [ -z "$INSTALLER_PATH" ]; then
    echo -e "${CYAN}📂 İndirdiğin .run (veya .zip) dosyasının yolunu yaz / sürükle ve ENTER'a bas (TAB ile tamamlama çalışır):${RESET}"
    read -e -r INSTALLER_PATH
  fi
  INSTALLER_PATH=$(sanitize_path "$INSTALLER_PATH")
  if [ ! -f "$INSTALLER_PATH" ]; then
    err "Dosya bulunamadı: '$INSTALLER_PATH'"
    exit 1
  fi
  _log "kurulum dosyası: $INSTALLER_PATH"
}

# ---------- Geçici dizin (tmpfs'e DEĞİL, diske) ----------
make_workdir() {
  local min="${DAVINCI_MIN_GB:-12}" base free best="" cands=()
  if [ -n "${DAVINCI_WORKDIR:-}" ]; then
    mkdir -p "$DAVINCI_WORKDIR" 2>/dev/null
    cands=("$DAVINCI_WORKDIR")
  else
    cands=(/var/tmp "$REAL_HOME/.cache" "$REAL_HOME")
  fi
  for base in "${cands[@]}"; do
    [ -d "$base" ] || continue
    free=$(df -P -BG "$base" 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4}')
    if [ "${free:-0}" -ge "$min" ]; then best="$base"; break; fi
    warn "$base altında ${free:-?} GB boş yer var (gereken: en az $min GB)."
  done
  if [ -z "$best" ]; then
    err "Kurulum dosyasını açmak için yeterli boş yer bulunamadı."
    echo "Başka bir diske yönlendirin: DAVINCI_WORKDIR=/baska/yer $0 $ORIG_ARGS"
    exit 1
  fi
  WORKDIR=$(mktemp -d "$best/davinci-install.XXXXXX") || { err "Geçici dizin oluşturulamadı."; exit 1; }
  ERRFILE="$WORKDIR/installer.err"
  _log "geçici dizin: $WORKDIR"
}

check_install_space() {
  local d="$RESOLVE_DIR" free
  while [ ! -d "$d" ] && [ "$d" != "/" ]; do d=$(dirname "$d"); done
  free=$(df -P -BG "$d" 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4}')
  if [ "${free:-99}" -lt 8 ]; then
    warn "$d üzerinde yalnızca ${free} GB boş yer var; Resolve kurulumu yaklaşık 6-8 GB gerektirir."
  fi
}

cleanup() {
  if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then rm -rf "$WORKDIR"; fi
  if [ "$XHOST_GRANTED" = 1 ]; then
    run_as_user env ${X_ENVS[@]+"${X_ENVS[@]}"} xhost -SI:localuser:root >/dev/null 2>&1
  fi
}

# ---------- Ekran erişimi (yalnızca --gui için) ----------
# Hyprland'de Xwayland sadece kullanıcıya açıktır; root'a geçince sihirbaz açılmaz
# ("Authorization required, but no authorization protocol specified"). Erişim burada GERÇEKTEN test edilir.
x_root_ok() {   # $1 = kullanılacak XAUTHORITY dosyası, boş = hiç kullanma
  if [ -n "${1:-}" ]; then
    env DISPLAY="$DISPLAY" XAUTHORITY="$1" xhost >/dev/null 2>&1
  else
    env -u XAUTHORITY DISPLAY="$DISPLAY" xhost >/dev/null 2>&1
  fi
}

prepare_display() {
  X_ENVS=()
  if [ -z "${DISPLAY:-}" ]; then
    local sock
    sock=$(ls /tmp/.X11-unix 2>/dev/null | head -n1)
    [ -n "$sock" ] && export DISPLAY=":${sock#X}"
  fi
  if [ -z "${DISPLAY:-}" ]; then
    warn "DISPLAY bulunamadı (X11/Xwayland çalışmıyor olabilir)."
    return 1
  fi
  export DISPLAY

  if ! command -v xhost >/dev/null 2>&1; then
    warn "'xhost' kurulu değil; ekran erişimi test edilemiyor."
    return 1
  fi

  # 1) Root zaten bağlanabiliyor mu? (KDE, GNOME, klasik X11)
  local cand
  for cand in "${XAUTHORITY:-}" "/run/user/$REAL_UID"/xauth_* "/run/user/$REAL_UID"/.mutter-Xwaylandauth.* "$REAL_HOME/.Xauthority" ""; do
    if [ -n "$cand" ] && [ ! -r "$cand" ]; then continue; fi
    if x_root_ok "$cand"; then
      if [ -n "$cand" ]; then export XAUTHORITY="$cand"; else unset XAUTHORITY; fi
      ok "Root ekrana bağlanabiliyor (DISPLAY=$DISPLAY)."
      return 0
    fi
  done

  # 2) Bağlanamıyor: kullanıcı adına xhost ile root'a izin ver (Hyprland / saf Xwayland)
  info "Root ekrana bağlanamıyor; xhost ile izin veriliyor..."
  local out="" granted=0
  if out=$(run_as_user env DISPLAY="$DISPLAY" xhost +SI:localuser:root 2>&1); then
    granted=1
  elif out=$(run_as_user env -u XAUTHORITY DISPLAY="$DISPLAY" xhost +SI:localuser:root 2>&1); then
    granted=1
  fi
  if [ "$granted" = 1 ]; then
    XHOST_GRANTED=1
    X_ENVS=("DISPLAY=$DISPLAY")
    unset XAUTHORITY
    if x_root_ok ""; then
      ok "xhost ile root'a ekran erişimi verildi (kurulum bitince geri alınacak)."
      return 0
    fi
    warn "xhost komutu başarılı oldu ama root yine de ekrana bağlanamadı."
    return 1
  fi
  warn "xhost izni verilemedi. Çıktı: $out"
  return 1
}

# ---------- Kurulum ----------
# $1 = kurulum dosyası, $2 = Qt platformu
run_installer() {
  local installer="$1" qpa="$2" runner=() args=()

  cd "$WORKDIR" || return 1
  chmod +x "$installer" 2>/dev/null

  if [ ! -x "$WORKDIR/squashfs-root/AppRun" ]; then
    if [ ! -x "$installer" ]; then   # noexec bölüm (USB/NTFS vb.) olabilir
      warn "Dosya çalıştırılamıyor (noexec bölüm olabilir); geçici dizine kopyalanıyor..."
      cp "$installer" "$WORKDIR/installer.run" && chmod +x "$WORKDIR/installer.run" && installer="$WORKDIR/installer.run"
    fi
    info "Kurulum paketi açılıyor (birkaç dakika sürebilir)..."
    SKIP_PACKAGE_CHECK=1 "$installer" --appimage-extract >/dev/null
  fi
  if [ -x "$WORKDIR/squashfs-root/AppRun" ]; then
    runner=("$WORKDIR/squashfs-root/AppRun")
  else
    warn "--appimage-extract başarısız; --appimage-extract-and-run deneniyor (TMPDIR=$WORKDIR)."
    export TMPDIR="$WORKDIR"
    runner=("$installer" --appimage-extract-and-run)
  fi

  if [ "$USE_CLI" = 1 ]; then
    args=(-i)
    info "Terminal tabanlı kurulum başlıyor; sorulara cevap verin."
  else
    info "Kurulum sihirbazı başlatılıyor..."
  fi
  info "Qt platformu: $qpa"

  : > "$ERRFILE"
  local cmd=(env -u WAYLAND_DISPLAY SKIP_PACKAGE_CHECK=1 QT_QPA_PLATFORM="$qpa" "${runner[@]}" ${args[@]+"${args[@]}"})
  if [ "${DAVINCI_NO_TEE:-0}" = 1 ]; then
    # Kaçış yolu: hata çıktısı yakalanmaz (Qt hatasında otomatik yedek platform denemesi yapılamaz)
    "${cmd[@]}"
  else
    # stderr hem ekrana hem dosyaya gider (hata nedenini anlamak için); stdout/stdin terminalde kalır
    "${cmd[@]}" 2> >(tee -a "$ERRFILE" >&2)
    sleep 1   # tee'nin yazmayı bitirmesi için
  fi
  # AppRun, installer çökse bile 0 döndürebiliyor: çıkış koduna güvenmiyoruz, sonucu dosyadan anlıyoruz.
  cat "$ERRFILE" >> "${LOG:-/dev/null}" 2>/dev/null
  return 0
}

# Qt platformu başarısız olursa sıradakini dener (offscreen -> minimal)
run_installer_chain() {
  local plats=() p
  if [ -n "${DAVINCI_QPA:-}" ]; then plats=("$DAVINCI_QPA")
  elif [ "$USE_CLI" = 1 ]; then plats=(offscreen minimal)
  else plats=(xcb); fi

  for p in "${plats[@]}"; do
    run_installer "$INSTALLER_PATH" "$p"
    resolve_freshly_installed && return 0
    if grep -qiE "$QT_FAIL_RE" "$ERRFILE" 2>/dev/null; then
      warn "Qt platformu '$p' çalışmadı."
      continue
    fi
    break   # Qt dışı bir neden (iptal, lisans reddi vb.): tekrar deneme
  done
  resolve_freshly_installed
}

post_install() {
  if ! locate_resolve; then
    warn "Resolve ikilisi bulunamadı; kurulum tamamlanmamış görünüyor."
    return 1
  fi
  fix_glib_conflicts
  check_missing_libs
  setup_launcher
  return 0
}

do_install() {
  check_install_space
  ask_installer
  make_workdir

  # .zip verildiyse içinden .run'ı çıkar
  case "$INSTALLER_PATH" in
    *.zip)
      command -v unzip >/dev/null 2>&1 || { err "unzip kurulu değil."; exit 1; }
      info ".zip açılıyor..."
      unzip -o -q "$INSTALLER_PATH" -d "$WORKDIR/zip" || { err "zip açılamadı."; exit 1; }
      INSTALLER_PATH=$(find "$WORKDIR/zip" -maxdepth 2 -name '*.run' | head -n1)
      [ -n "$INSTALLER_PATH" ] || { err "zip içinde .run dosyası bulunamadı."; exit 1; }
      ;;
  esac

  if [ "$USE_CLI" = 0 ] && ! prepare_display; then
    warn "Grafik sihirbaz başlatılamayacağı için terminal kurulumuna geçiliyor."
    USE_CLI=1
  fi

  START_TS=$(date +%s)
  run_installer_chain

  # Grafik sihirbaz ekran sorunuyla çöktüyse otomatik terminal kurulumuna geç
  if ! resolve_freshly_installed && [ "$USE_CLI" = 0 ] && grep -qiE "$QT_FAIL_RE" "$ERRFILE" 2>/dev/null; then
    warn "Grafik sihirbaz ekran sorunu yüzünden açılamadı; terminal kurulumuna geçiliyor."
    USE_CLI=1
    run_installer_chain
  fi

  if ! resolve_freshly_installed; then
    err "Kurulum tamamlanamadı (Resolve ikilisi oluşmadı)."
    return 1
  fi
  ok "Resolve kuruldu: $RESOLVE_DIR/bin/resolve"
  post_install
}

# ---------- Otomatik mod: kullanıcı seçenek yazmak zorunda kalmasın ----------
is_interactive() { [ -t 0 ] && [ -t 1 ]; }

# Durumu tespit eder ve MODE'u "install" ya da "fix" yapar
decide_mode() {
  [ "$MODE" = "auto" ] || return 0

  local installed=0 found="" def="O" ans="" fm=0 ic=0
  locate_resolve && installed=1

  # Dosya yolu açıkça verildiyse: kurulum/güncelleme (sormadan)
  if [ -n "$INSTALLER_PATH" ]; then MODE="install"; return 0; fi

  found=$(find_installer)

  if [ "$installed" = 0 ]; then
    info "Resolve kurulu değil → KURULUM modu."
    MODE="install"; return 0
  fi

  if [ -z "$found" ]; then
    info "Resolve zaten kurulu ($RESOLVE_DIR) ve yeni bir kurulum dosyası bulunamadı → otomatik ONARIM modu."
    MODE="fix"; AUTO_FIX_HINT=1; return 0
  fi

  # Kurulu + kurulum dosyası da var: asıl niyet belirsiz. Dosya kurulumdan SONRA indirilmişse büyük ihtimalle güncelleme.
  fm=$(stat -c %Y "$found" 2>/dev/null || echo 0)
  ic=$(stat -c %Z "$RESOLVE_DIR/bin/resolve" 2>/dev/null || echo 0)
  [ "$fm" -gt "$ic" ] && def="K"

  info "Resolve kurulu ($RESOLVE_DIR) ve kurulum dosyası bulundu: $found"
  if is_interactive; then
    read -r -p "Ne yapılsın?  [K] Bu dosyayla kur/güncelle   [O] Sadece onar   (Enter = $def) " ans
  fi
  case "${ans:-$def}" in
    [kKgG]*) INSTALLER_PATH="$found"; MODE="install"; info "→ Seçilen işlem: KURULUM/GÜNCELLEME ($found)" ;;
    *)       MODE="fix";                              info "→ Seçilen işlem: ONARIM (kurulum yapılmayacak)" ;;
  esac
  is_interactive || info "(Etkileşimsiz oturum: varsayılan seçildi. Farklısı için dosya yolunu argüman verin ya da --fix kullanın.)"
  return 0
}

do_repair() {
  if ! locate_resolve; then
    err "Kurulu Resolve bulunamadı ($RESOLVE_DIR). Başka bir dizindeyse: RESOLVE_DIR=/yol $0"
    return 1
  fi
  fix_glib_conflicts
  check_missing_libs
  setup_launcher
  ok "Onarım tamamlandı."
  if [ "$AUTO_FIX_HINT" = 1 ]; then
    echo -e "${YELLOW}İpucu:${RESET} Resolve'u güncellemek için yeni .run/.zip dosyasını İndirilenler klasörüne koyup scripti tekrar çalıştırın (ya da dosya yolunu verin)."
  fi
  return 0
}

main() {
  parse_args "$@"
  banner
  require_root "$@"
  init_user
  setup_log
  check_arch
  detect_os
  detect_gpus
  select_gpu_mode
  report_gpus
  trap cleanup EXIT
  trap 'exit 130' INT TERM

  decide_mode
  install_dependencies
  setup_gpu

  if [ "$MODE" = "fix" ]; then
    do_repair || exit 1
    echo ""
    gpu_final_notes
    ok "Tamamlandı. Günlük: $LOG"
    exit 0
  fi

  if ! do_install; then
    echo ""
    err "Kurulum başarısız. Ayrıntılar için günlük dosyasına bakın: $LOG"
    exit 1
  fi

  echo ""
  gpu_final_notes
  ok "Tamamlandı. Günlük: $LOG"
  echo -e "${YELLOW}Resolve açılmazsa terminalden çalıştırıp hata çıktısına bakın:${RESET} ${BOLD}QT_QPA_PLATFORM=xcb $RESOLVE_DIR/bin/resolve${RESET}"
  echo -e "${YELLOW}Sorun yaşarsanız scripti aynı şekilde tekrar çalıştırın:${RESET} kurulu Resolve'u kendisi onarır."
}

# Dosya doğrudan çalıştırılınca main'i çağır (source edilince çağırma)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
