#!/usr/bin/env bash
# =====================================================================
#  VİDEO DÖNÜŞTÜRÜCÜ  (DaVinci Resolve için)
#
#    Kurgudan ÖNCE : MP4 / MKV / AVI ...  ->  MOV (DNxHR)   Resolve bu biçimde çok daha rahat çalışır
#    Kurgudan SONRA: MOV (DNxHR / ProRes) ->  MP4 (H.264)   paylaşım / yükleme için
#
#  Kullanım:
#    ./video_convert.sh video1.mp4 video2.mkv      # yönü, dosyanın kodeğine bakıp kendisi seçer
#    ./video_convert.sh ~/İndirilenler/video       # klasördeki tüm videoları çevirir
#    ./video_convert.sh --to-mp4 export.mov        # yönü elle seç
#    ./video_convert.sh --help                     # tüm seçenekler
#
#  Çıktılar, aksi söylenmedikçe ORİJİNAL DOSYANIN KLASÖRÜNE "-converted" ekiyle yazılır.
#  Orijinal dosyalara asla dokunulmaz; var olan çıktının üzerine yazılmaz (-f ile yazılır).
# =====================================================================
set -u
# sh/dash ile başlatıldıysa bash ile yeniden başlat
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

# ---------- Renkler / mesajlar ----------
BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; BLUE=$'\033[34m'
CYAN=$'\033[36m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
info() { printf '%s\n' "${BLUE}🔧 $*${RESET}"; }
ok()   { printf '%s\n' "${GREEN}✅ $*${RESET}"; }
warn() { printf '%s\n' "${YELLOW}⚠️  $*${RESET}"; }
err()  { printf '%s\n' "${RED}❌ $*${RESET}" >&2; }

# ---------- Ayarlar ----------
MODE="auto"              # auto | mov | mp4
PROFILE=""               # lb | sq | hq | hqx | 444  (boşsa: 10-bit kaynakta hqx, değilse hq)
CRF=23                   # MP4 kalitesi (düşük = daha iyi/daha büyük)
PRESET="fast"            # x264 hız/verim ayarı
JOBS=""                  # eşzamanlı dönüşüm sayısı (boşsa işlemci çekirdeğine göre)
OUTDIR=""                # boşsa: her dosya kendi klasörüne
FORCE=0
RECURSIVE=0
DRYRUN=0
SUFFIX="-converted"
VIDEO_EXT='mp4|m4v|mov|mkv|avi|webm|mts|m2ts|ts|mpg|mpeg|wmv|flv|3gp|mxf|ogv|vob'

INPUTS=(); FILES=()
J_IN=(); J_OUT=(); J_TGT=(); J_PROF=(); J_BR=()   # planlanan işler (paralel diziler)
SKIPPED=()                                   # atlananlar ve nedenleri
TMPD=""
FFMPEG="${FFMPEG:-}"
ENC_CHECKED_MOV=0; ENC_OK_MOV=1
ENC_CHECKED_MP4=0; ENC_OK_MP4=1
H264_ENC=""             # kullanılacak H.264 encoder: libx264 | libopenh264
BITRATE=""               # yalnızca libopenh264 yedeğinde kullanılır (boşsa çözünürlükten hesaplanır)
HARD_SKIP=0              # encoder eksikliği yüzünden atlanan dosya var mı

usage() {
cat <<EOF
Kullanım: $0 [seçenekler] <dosya|klasör> [dosya|klasör ...]

Yön (varsayılan: otomatik)
  (seçeneksiz)       Kodeğe bakar: H.264/HEVC/VP9... -> MOV (DNxHR) | DNxHR/ProRes/CineForm -> MP4 (H.264)
  -m, --to-mov       Hepsini MOV (DNxHR) yap   (kurgu öncesi)
  -p, --to-mp4       Hepsini MP4 (H.264) yap   (kurgu sonrası)

Çıktı
  -o, --output DIR   Çıktıları bu klasöre yaz (varsayılan: her videonun kendi klasörü)
  -f, --force        Var olan çıktıların üzerine yaz (varsayılan: atla)
  -n, --dry-run      Hiçbir şey çevirmeden yalnızca planı göster
  -r, --recursive    Klasör verildiyse alt klasörlere de gir

Kalite
  --profile P        DNxHR profili: lb, sq, hq, hqx (10-bit), 444   (varsayılan: hq; 10-bit kaynakta otomatik hqx)
  --crf N            MP4 kalitesi 0-51 (varsayılan: $CRF)
  --preset P         x264 hızı: ultrafast ... medium ... veryslow (varsayılan: $PRESET)
  --bitrate B        Yalnızca libx264 YOKSA (OpenH264 yedeği) kullanılır, ör. 8M veya 5000k (varsayılan: çözünürlükten hesaplanır)

Diğer
  -j, --jobs N       Aynı anda çevrilecek video sayısı (varsayılan: işlemci çekirdeğine göre, en fazla 4)
  -h, --help         Bu yardım

Ortam değişkenleri: FFMPEG=/yol/ffmpeg  FFPROBE=/yol/ffprobe  (boş FFPROBE= ffprobe'suz çalıştırır)
EOF
}

die_usage() { err "$1"; echo "Yardım için: $0 --help" >&2; exit 1; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -m|--to-mov)    MODE="mov" ;;
      -p|--to-mp4)    MODE="mp4" ;;
      -f|--force)     FORCE=1 ;;
      -n|--dry-run)   DRYRUN=1 ;;
      -r|--recursive) RECURSIVE=1 ;;
      -o|--output)    [ $# -ge 2 ] || die_usage "$1 için bir değer gerekli."; OUTDIR="$2"; shift ;;
      -j|--jobs)      [ $# -ge 2 ] || die_usage "$1 için bir değer gerekli."; JOBS="$2"; shift ;;
      --profile)      [ $# -ge 2 ] || die_usage "$1 için bir değer gerekli."; PROFILE="$2"; shift ;;
      --crf)          [ $# -ge 2 ] || die_usage "$1 için bir değer gerekli."; CRF="$2"; shift ;;
      --preset)       [ $# -ge 2 ] || die_usage "$1 için bir değer gerekli."; PRESET="$2"; shift ;;
      --bitrate)      [ $# -ge 2 ] || die_usage "$1 için bir değer gerekli."; BITRATE="$2"; shift ;;
      -h|--help)      usage; exit 0 ;;
      --)             shift; while [ $# -gt 0 ]; do INPUTS+=("$1"); shift; done; break ;;
      -*)             die_usage "Bilinmeyen seçenek: $1" ;;
      *)              INPUTS+=("$1") ;;
    esac
    shift
  done

  case "$PROFILE" in ""|lb|sq|hq|hqx|444) ;; *) die_usage "Geçersiz --profile: $PROFILE (lb, sq, hq, hqx, 444)" ;; esac
  case "$CRF" in ''|*[!0-9]*) die_usage "--crf bir sayı olmalı (0-51)." ;; esac
  [ "$CRF" -le 51 ] || die_usage "--crf 0-51 arasında olmalı."
  case "$BITRATE" in ""|[0-9]*[kKmM]|[0-9]*) ;; *) die_usage "Geçersiz --bitrate: $BITRATE (ör. 8M veya 5000k)" ;; esac
  case "$PRESET" in ultrafast|superfast|veryfast|faster|fast|medium|slow|slower|veryslow) ;; *) die_usage "Geçersiz --preset: $PRESET" ;; esac
  if [ -n "$JOBS" ]; then
    case "$JOBS" in ''|*[!0-9]*|0) die_usage "--jobs 1 veya daha büyük bir sayı olmalı." ;; esac
  fi
}

# ---------- ffmpeg / ffprobe ----------
os_family() {
  local id="" like="" t
  if [ -f /etc/os-release ]; then
    id=$(. /etc/os-release; printf '%s' "${ID:-}")
    like=$(. /etc/os-release; printf '%s' "${ID_LIKE:-}")
  fi
  # shellcheck disable=SC2086
  for t in $id $like; do
    case "$t" in
      debian|ubuntu)      echo "debian"; return 0 ;;
      fedora|rhel|centos) echo "fedora"; return 0 ;;
      arch)               echo "arch";   return 0 ;;
    esac
  done
  return 0
}

find_tools() {
  if [ -z "$FFMPEG" ]; then
    if command -v ffmpeg >/dev/null 2>&1; then FFMPEG=$(command -v ffmpeg)
    elif [ -x "$HOME/.local/bin/ffmpeg" ]; then FFMPEG="$HOME/.local/bin/ffmpeg"   # elle kurulmuş (statik) ffmpeg
    fi
  fi
  [ -n "$FFMPEG" ] && [ -x "$FFMPEG" ] || FFMPEG=""
  if [ -z "${FFPROBE+x}" ]; then   # FFPROBE hiç tanımlı değilse ara; tanımlıysa (boş bile olsa) olduğu gibi kullan
    FFPROBE=""
    if [ -n "$FFMPEG" ] && [ -x "$(dirname "$FFMPEG")/ffprobe" ]; then FFPROBE="$(dirname "$FFMPEG")/ffprobe"
    elif command -v ffprobe >/dev/null 2>&1; then FFPROBE=$(command -v ffprobe)
    fi
  fi
}

ensure_ffmpeg() {
  find_tools
  [ -n "$FFMPEG" ] && return 0

  err "ffmpeg bulunamadı. Dönüştürme için gerekli."
  local cmd="" ans=""
  case "$(os_family)" in
    debian) cmd="sudo apt-get install -y ffmpeg" ;;
    fedora) cmd="sudo dnf install -y ffmpeg-free" ;;
    arch)   cmd="sudo pacman -S --needed --noconfirm ffmpeg" ;;
  esac
  if [ -z "$cmd" ]; then
    echo "   Dağıtımınızın paket yöneticisiyle 'ffmpeg' paketini kurun."
    return 1
  fi
  [ "$EUID" -eq 0 ] && cmd=${cmd#sudo }
  echo "   Kurulum komutu: $cmd"
  if [ -t 0 ] && [ -t 1 ]; then
    read -r -p "   Şimdi kurulsun mu? [E/h] " ans
    case "${ans:-E}" in [hHnN]*) return 1 ;; esac
    bash -c "$cmd" || { err "Kurulum başarısız oldu."; return 1; }
    find_tools
    [ -n "$FFMPEG" ] && return 0
    err "Kurulumdan sonra da ffmpeg bulunamadı."
  fi
  return 1
}

have_encoder() { "$FFMPEG" -hide_banner -encoders 2>/dev/null | awk -v e="$1" '$2==e {f=1} END {exit !f}'; }

# Hedef için gereken encoder'lar var mı? (bir kez kontrol eder, eksikse nasıl düzeltileceğini söyler)
# Kodlama gerçekten çalışıyor mu? (encoder listede görünse de çalışma anında kütüphanesi eksik olabilir, ör. libopenh264)
encoder_works() {
  "$FFMPEG" -hide_banner -loglevel error -nostdin -f lavfi -i "color=c=black:s=128x128:d=0.2:r=10" \
    -c:v "$1" -pix_fmt yuv420p -frames:v 2 -f null - >/dev/null 2>&1
}

# H.264 encoder'ı seç: önce libx264 (en iyisi), yoksa Cisco OpenH264 (Fedora'nın ffmpeg-free paketinde bulunabilir)
select_h264() {
  local e
  H264_ENC=""
  for e in libx264 libopenh264; do
    if have_encoder "$e" && encoder_works "$e"; then H264_ENC="$e"; break; fi
  done
  if [ "$H264_ENC" = "libopenh264" ]; then
    warn "libx264 yok; Cisco OpenH264 ile devam ediliyor (bitrate tabanlı, kalite libx264'ten biraz düşük)."
    echo "   En iyi kalite için tam ffmpeg: Fedora'da RPM Fusion + 'sudo dnf swap ffmpeg-free ffmpeg --allowerasing'."
  fi
}

# H.264 encoder'ı hiç yoksa çözümü sun (Fedora'da onayla uygular). Başarırsa H264_ENC dolar.
offer_full_ffmpeg() {
  err "Bu ffmpeg'de kullanılabilir bir H.264 encoder'ı yok (libx264 / libopenh264); MP4'e çevrilemez."
  if [ "$(os_family)" != "fedora" ]; then
    echo "   Tam özellikli 'ffmpeg' paketini kurun (libx264 içerir)."
    return 1
  fi
  echo "   Fedora'nın varsayılan 'ffmpeg-free' paketi, telif nedeniyle libx264 içermez."
  if ! rpm -q ffmpeg-free >/dev/null 2>&1; then
    echo "   (Elle kurulmuş bir ffmpeg kullanıyorsunuz; libx264 içeren bir sürüm kurun ya da ffmpeg-free'ye geçin.)"
    return 1
  fi

  local sd="sudo " rf=0 ans="" c1 c2
  [ "$EUID" -eq 0 ] && sd=""
  dnf repolist --enabled 2>/dev/null | grep -qi 'rpmfusion-free' && rf=1
  c1="${sd}dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-\$(rpm -E %fedora).noarch.rpm"
  c2="${sd}dnf swap -y ffmpeg-free ffmpeg --allowerasing"

  echo "   Çözüm: tam 'ffmpeg'e geçmek (RPM Fusion Free; üçüncü taraf depo: https://rpmfusion.org/Configuration):"
  [ "$rf" = 0 ] && echo "     $c1"
  echo "     $c2"
  echo "   Alternatif: Fedora'nın Cisco OpenH264 deposunu etkinleştirip 'openh264' paketini kurmak (script OpenH264'ü otomatik kullanır)."

  if [ -t 0 ] && [ -t 1 ]; then
    read -r -p "   Yukarıdaki komutlar şimdi uygulansın mı? [e/H] " ans
    case "$ans" in
      [eEyY]*)
        if [ "$rf" = 0 ]; then bash -c "$c1" || { err "RPM Fusion etkinleştirilemedi."; return 1; }; fi
        bash -c "$c2" || { err "ffmpeg değişimi başarısız oldu."; return 1; }
        select_h264
        if [ -n "$H264_ENC" ]; then ok "Tam ffmpeg kuruldu."; return 0; fi
        err "Kurulumdan sonra da H.264 encoder'ı bulunamadı." ;;
    esac
  fi
  return 1
}

# Hedef için gereken encoder'lar var mı? (bir kez kontrol eder)
need_encoders() {
  case "$1" in
    mov)
      if [ "$ENC_CHECKED_MOV" = 0 ]; then
        ENC_CHECKED_MOV=1
        if ! have_encoder dnxhd || ! have_encoder pcm_s16le; then
          ENC_OK_MOV=0; err "Bu ffmpeg sürümünde DNxHR (dnxhd) encoder'ı yok; MOV'a çevrilemez."
        fi
      fi
      [ "$ENC_OK_MOV" = 1 ] ;;
    mp4)
      if [ "$ENC_CHECKED_MP4" = 0 ]; then
        ENC_CHECKED_MP4=1
        if ! have_encoder aac; then
          ENC_OK_MP4=0; err "Bu ffmpeg'de AAC ses encoder'ı yok; MP4'e çevrilemez."
        else
          select_h264
          if [ -z "$H264_ENC" ]; then
            offer_full_ffmpeg || ENC_OK_MP4=0
          fi
        fi
      fi
      [ "$ENC_OK_MP4" = 1 ] ;;
  esac
}

# ---------- Dosyaları topla ----------
is_video_name() {
  local r
  shopt -s nocasematch
  [[ "$1" =~ \.($VIDEO_EXT)$ ]]; r=$?
  shopt -u nocasematch
  return $r
}

collect_files() {
  local a f
  local -a depth
  for a in "${INPUTS[@]}"; do
    if [ -d "$a" ]; then
      if [ "$RECURSIVE" = 1 ]; then depth=(); else depth=(-maxdepth 1); fi
      while IFS= read -r -d '' f; do
        is_video_name "$f" || continue
        case "$f" in *"$SUFFIX".*) continue ;; esac   # daha önce üretilmiş çıktıları tekrar işleme
        FILES+=("$f")
      done < <(find "$a" ${depth[@]+"${depth[@]}"} -type f -print0 | sort -z)
    elif [ -f "$a" ]; then
      case "$a" in -*) a="./$a" ;; esac               # '-' ile başlayan dosya adı seçenek sanılmasın
      FILES+=("$a")
    else
      warn "Bulunamadı, atlandı: $a"
    fi
  done
}

# ---------- Video bilgisi: "kodek pix_fmt" ----------
probe_video() {
  local f="$1" out line codec="" pix=""
  if [ -n "$FFPROBE" ]; then
    out=$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=codec_name,pix_fmt -of default=noprint_wrappers=1 "$f" 2>/dev/null)
    codec=$(printf '%s\n' "$out" | sed -n 's/^codec_name=//p' | head -n1)
    pix=$(printf '%s\n' "$out" | sed -n 's/^pix_fmt=//p' | head -n1)
  else
    # ffprobe yoksa (ör. tek dosyalık statik ffmpeg) 'ffmpeg -i' çıktısından oku
    line=$("$FFMPEG" -hide_banner -nostdin -i "$f" 2>&1 | grep -m1 'Stream #.*Video:')
    if [ -n "$line" ]; then
      line=${line#*Video: }
      codec=${line%%[ ,(]*}
      pix=$(printf '%s\n' "$line" | grep -oE '\b(yuvj?[0-9a-z]+|gbrp[0-9a-z]*|rgb[0-9a-z]*|bgr[0-9a-z]*|nv[0-9a-z]+|gray[0-9a-z]*|pal8)\b' | head -n1)
    fi
  fi
  [ -n "$codec" ] && printf '%s %s' "$codec" "${pix:-unknown}"
}

# Genişlik, yükseklik, fps -> "W H FPS" (yalnızca OpenH264 yedeğinde bitrate hesabı için)
probe_dims() {
  local f="$1" out w="" h="" fr="" fps="" line wh
  if [ -n "$FFPROBE" ]; then
    out=$("$FFPROBE" -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate -of default=noprint_wrappers=1 "$f" 2>/dev/null)
    w=$(printf '%s\n' "$out" | sed -n 's/^width=//p' | head -n1)
    h=$(printf '%s\n' "$out" | sed -n 's/^height=//p' | head -n1)
    fr=$(printf '%s\n' "$out" | sed -n 's/^avg_frame_rate=//p' | head -n1)
    fps=$(awk -v r="$fr" 'BEGIN { split(r, a, "/"); if (a[2] + 0 > 0) printf "%.3f", a[1] / a[2]; else printf "%s", a[1] + 0 }')
  else
    line=$("$FFMPEG" -hide_banner -nostdin -i "$f" 2>&1 | grep -m1 'Stream #.*Video:')
    wh=$(printf '%s\n' "$line" | grep -oE '[0-9]{2,5}x[0-9]{2,5}' | head -n1)
    w=${wh%x*}; h=${wh#*x}
    fps=$(printf '%s\n' "$line" | grep -oE '[0-9]+(\.[0-9]+)? fps' | head -n1 | cut -d' ' -f1)
  fi
  [ -n "$w" ] && [ -n "$h" ] && printf '%s %s %s' "$w" "$h" "${fps:-25}"
}

# "W H FPS" -> yaklaşık bitrate (piksel başına ~0,12 bit; 1000k ile 50000k arasına sıkıştırılır)
calc_bitrate() {
  awk -v w="$1" -v h="$2" -v f="$3" 'BEGIN { if (f + 0 <= 0) f = 25; k = w * h * f * 0.12 / 1000; if (k < 1000) k = 1000; if (k > 50000) k = 50000; printf "%dk", k }'
}

# Yönü ve DNxHR profilini seç -> "mov|mp4 profil"
decide() {
  local codec="$1" pix="$2" tgt prof
  case "$MODE" in
    mov|mp4) tgt="$MODE" ;;
    *) case "$codec" in dnxhd|prores|cfhd) tgt="mp4" ;; *) tgt="mov" ;; esac ;;
  esac
  prof="${PROFILE:-hq}"
  if [ -z "$PROFILE" ]; then
    case "$pix" in *10le|*10be|*12le|*12be|*14le|*14be|*16le|*16be) prof="hqx" ;; esac   # 10-bit kaynağı 8-bit'e düşürme
  fi
  printf '%s %s' "$tgt" "$prof"
}

human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || printf '%s bayt' "$1"; }

# ---------- Planlama (sırayla; hiçbir şey çevirmez) ----------
plan() {
  local f n=0 pr codec pix dec tgt prof dir base name out label dims br
  for f in "${FILES[@]}"; do
    n=$((n + 1))
    base="${f##*/}"
    if ! pr=$(probe_video "$f"); then
      warn "$base: video akışı okunamadı (bozuk ya da video değil), atlandı."
      SKIPPED+=("$base — video akışı okunamadı")
      continue
    fi
    codec=${pr%% *}; pix=${pr#* }
    dec=$(decide "$codec" "$pix"); tgt=${dec%% *}; prof=${dec#* }

    if ! need_encoders "$tgt"; then
      HARD_SKIP=1
      SKIPPED+=("$base — gerekli encoder yok")
      continue
    fi

    if [ -n "$OUTDIR" ]; then dir="$OUTDIR"; else dir=$(dirname "$f"); fi
    name="${base%.*}"
    out="$dir/${name}${SUFFIX}.${tgt}"

    br=""
    if [ "$tgt" = "mov" ]; then
      label="MOV (DNxHR ${prof^^})"
    elif [ "$H264_ENC" = "libopenh264" ]; then
      if [ -n "$BITRATE" ]; then br="$BITRATE"
      else dims=$(probe_dims "$f") && br=$(calc_bitrate $dims) || br="8000k"
      fi
      label="MP4 (H.264 / OpenH264, ~$br)"
    else
      label="MP4 (H.264, CRF $CRF)"
    fi

    if [ -e "$out" ] && [ "$FORCE" = 0 ]; then
      echo "  ⏭  $base  [$codec]  →  $label  (çıktı zaten var, atlandı; üzerine yazmak için -f)"
      SKIPPED+=("$base — çıktı zaten var")
      continue
    fi
    echo "  📄 $base  [$codec, $pix]  →  $label"
    echo "       ↳ $out"
    J_IN+=("$f"); J_OUT+=("$out"); J_TGT+=("$tgt"); J_PROF+=("$prof"); J_BR+=("$br")
  done
}

check_space() {
  local i sz need=0 dir avail
  for i in "${!J_IN[@]}"; do
    sz=$(stat -c %s "${J_IN[$i]}" 2>/dev/null || echo 0)
    if [ "${J_TGT[$i]}" = "mov" ]; then need=$((need + sz * 12)); else need=$((need + sz)); fi
  done
  dir=$(dirname "${J_OUT[0]}")
  [ -d "$dir" ] || dir=$(dirname "$dir")
  avail=$(df -P -B1 "$dir" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$avail" ] && [ "$need" -gt "$avail" ]; then
    warn "Tahmini gereken alan ~$(human "$need"), boş alan $(human "$avail"). DNxHR dosyaları orijinalden çok daha büyüktür."
  fi
}

# ---------- Dönüştürme (paralel çalışır) ----------
run_job() {
  local i="$1" in out tgt prof pf tmp log rc base
  in="${J_IN[$i]}"; out="${J_OUT[$i]}"; tgt="${J_TGT[$i]}"; prof="${J_PROF[$i]}"
  tmp="$out.partial"; log="$TMPD/$i.log"; base="${in##*/}"

  local -a g=(-nostdin -hide_banner -y)
  local -a args=(-i "$in" -map 0:v:0 -map "0:a?" -sn -dn)     # ilk video + tüm sesler; altyazı/veri akışları MOV/MP4'e sorun çıkarmasın
  if [ "$tgt" = "mov" ]; then
    case "$prof" in hqx) pf="yuv422p10le" ;; 444) pf="yuv444p10le" ;; *) pf="yuv422p" ;; esac
    args+=(-c:v dnxhd -profile:v "dnxhr_$prof" -pix_fmt "$pf" -c:a pcm_s16le)
  else
    # yuv420p çift sayıda genişlik/yükseklik ister; tek sayıysa 1 piksel kırpılır
    if [ "$H264_ENC" = "libopenh264" ]; then
      args+=(-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libopenh264 -b:v "${J_BR[$i]:-8000k}" -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart)
    else
      args+=(-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf "$CRF" -preset "$PRESET" -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart)
    fi
  fi

  printf '%s\n' "${CYAN}[BAŞLADI]${RESET} $base"
  if [ "${#J_IN[@]}" -eq 1 ] && [ -t 2 ]; then
    "$FFMPEG" "${g[@]}" -loglevel warning -stats "${args[@]}" -f "$tgt" "$tmp"; rc=$?   # tek dosya: canlı ilerleme
  else
    "$FFMPEG" "${g[@]}" -loglevel error -nostats "${args[@]}" -f "$tgt" "$tmp" 2>"$log"; rc=$?
  fi

  if [ "$rc" -eq 0 ] && [ -s "$tmp" ] && mv -f "$tmp" "$out"; then
    echo ok > "$TMPD/$i.status"
    printf '%s\n' "${GREEN}[BİTTİ]${RESET}   $base  →  $out"
  else
    rm -f "$tmp"
    echo fail > "$TMPD/$i.status"
    printf '%s\n' "${RED}[HATA]${RESET}    $base  (ffmpeg çıkış kodu: $rc)" >&2
    if [ -s "$log" ]; then tail -n 3 "$log" | sed 's/^/             /' >&2; fi
  fi
  return 0
}

cleanup() {
  local i
  for i in "${!J_OUT[@]}"; do rm -f "${J_OUT[$i]}.partial" 2>/dev/null; done
  [ -n "$TMPD" ] && [ -d "$TMPD" ] && rm -rf "$TMPD"
}
on_interrupt() {
  echo; warn "Durduruldu, yarım kalan dosyalar temizleniyor..."
  # shellcheck disable=SC2046
  kill $(jobs -p) 2>/dev/null
  wait 2>/dev/null
  exit 130
}

run_all() {
  local i running=0 can_wait_n=0
  if [ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 3 ]; }; then can_wait_n=1; fi
  for i in "${!J_IN[@]}"; do
    run_job "$i" &
    running=$((running + 1))
    if [ "$running" -ge "$JOBS" ]; then
      if [ "$can_wait_n" = 1 ]; then wait -n; running=$((running - 1)); else wait; running=0; fi
    fi
  done
  wait
}

summary() {
  local i okc=0 failc=0 s
  local -a failed=()
  for i in "${!J_IN[@]}"; do
    s=$(cat "$TMPD/$i.status" 2>/dev/null || echo fail)
    if [ "$s" = ok ]; then okc=$((okc + 1)); else failc=$((failc + 1)); failed+=("${J_IN[$i]##*/}"); fi
  done
  echo "------------------------------------------------------------"
  echo "  ${GREEN}Başarılı: $okc${RESET}   ${YELLOW}Atlanan: ${#SKIPPED[@]}${RESET}   ${RED}Hatalı: $failc${RESET}"
  if [ "${#SKIPPED[@]}" -gt 0 ]; then
    printf '  %s\n' "Atlananlar:"; printf '    - %s\n' "${SKIPPED[@]}"
  fi
  if [ "$failc" -gt 0 ]; then
    printf '  %s\n' "Hatalı olanlar:"; printf '    - %s\n' "${failed[@]}"
    err "Bazı dönüşümler başarısız oldu (ayrıntılar yukarıda)."
    return 1
  fi
  if [ "$HARD_SKIP" = 1 ]; then
    err "Bazı dosyalar gerekli encoder eksik olduğu için çevrilemedi (ayrıntılar yukarıda)."
    return 1
  fi
  [ "$okc" -gt 0 ] && ok "Tüm dönüştürmeler tamamlandı."
  return 0
}

main() {
  parse_args "$@"
  echo -e "${CYAN}#############################################################${RESET}"
  echo -e "${CYAN}#      VİDEO DÖNÜŞTÜRÜCÜ  (MP4 ⇄ MOV, DaVinci Resolve için)   #${RESET}"
  echo -e "${CYAN}#############################################################${RESET}"

  [ "${#INPUTS[@]}" -gt 0 ] || { usage; exit 1; }
  ensure_ffmpeg || exit 1

  if [ -z "$JOBS" ]; then
    local cores; cores=$(nproc 2>/dev/null || echo 2)
    JOBS=$((cores / 4)); [ "$JOBS" -lt 1 ] && JOBS=1; [ "$JOBS" -gt 4 ] && JOBS=4
  fi

  collect_files
  [ "${#FILES[@]}" -gt 0 ] || { err "İşlenecek video dosyası bulunamadı."; exit 1; }

  if [ -n "$OUTDIR" ] && [ "$DRYRUN" = 0 ]; then
    mkdir -p "$OUTDIR" 2>/dev/null || { err "Çıktı klasörü oluşturulamadı: $OUTDIR"; exit 1; }
  fi
  TMPD=$(mktemp -d) || { err "Geçici dizin oluşturulamadı."; exit 1; }
  trap cleanup EXIT
  trap on_interrupt INT TERM

  [ -n "$FFPROBE" ] || info "ffprobe bulunamadı; video bilgisi ffmpeg ile okunacak."
  info "Toplam ${#FILES[@]} dosya inceleniyor (eşzamanlı iş: $JOBS)..."
  echo "------------------------------------------------------------"
  plan
  echo "------------------------------------------------------------"

  if [ "${#J_IN[@]}" -eq 0 ]; then
    summary; local rc=$?
    [ "${#SKIPPED[@]}" -gt 0 ] && [ "$rc" -eq 0 ] && info "Çevrilecek yeni bir şey yok."
    exit $rc
  fi
  if [ "$DRYRUN" = 1 ]; then
    info "Deneme modu (--dry-run): ${#J_IN[@]} dosya çevrilecekti, hiçbir şey yapılmadı."
    exit 0
  fi

  check_space
  info "${#J_IN[@]} dosya dönüştürülüyor..."
  run_all
  summary
  exit $?
}

# Dosya doğrudan çalıştırılınca main'i çağır (source edilince çağırma)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
