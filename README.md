# 🎥 DAVINCI RESOLVE LINUX MASTER FIXER & INSTALLER 🚀

![Linux Support](https://img.shields.io/badge/Support-Ubuntu%20%7C%20Fedora%20%2C%20Arch-blueviolet?style=for-the-badge&logo=linux)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

---

## 🌍 Language / Dil
- [🇹🇷 Türkçe İçerik](#-türkçe-readme---tr)
- [🇺🇸 English Content](#-english-readme---en)

---

## 🇹🇷 TÜRKÇE (README - TR)

Bu araç, Linux sistemlerde (Ubuntu/Debian, Fedora, Arch ailesi) DaVinci Resolve kurulumunu, ekran kartı hazırlığını ve kütüphane çakışmalarını **TEK SCRIPT İLE OTOMATİK ÇÖZER**. 🛠️

> [!IMPORTANT]
> **ÖNEMLİ NOT:** Projenin temel dosyası `davinci_resolve_installer.sh` dosyasıdır. Eski `setup.sh` (kurulum), `fix_resolve.sh` (onarım) ve NVIDIA/AMD için ayrı scriptlerin işini artık **tek başına** yapar. Diğer tüm araçlar (çeviriciler vb.) tamamen **opsiyoneldir**, ihtiyaca göre kullanılabilir.

### 🛠️ İÇERİK
| Dosya | Açıklama |
| :--- | :--- |
| 📦 **davinci_resolve_installer.sh** | Bağımlılıkları **KURAR**, ekran kartını **HAZIRLAR**, Resolve'u **KURAR / GÜNCELLER** ve açılmama sorunlarını **ONARIR**. |
| 🎞️ **videocovmov.sh** | MP4 dosyalarını kurgu için **MOV** formatına çevirir (Opsiyonel). |
| 📤 **mov_to_mp4.sh** | Kurgu bitince dosyayı **MP4** olarak export eder (Opsiyonel). |

### 🚀 KULLANIM
Resolve'un Linux `.zip` (veya `.run`) dosyasını Blackmagic Design sitesinden indirin, sonra:

```bash
chmod +x davinci_resolve_installer.sh
./davinci_resolve_installer.sh
```

Yönetici yetkisi gerekirse script `sudo`'yu kendisi ister. **Seçenek yazmanız gerekmez**, script durumu kendisi anlar:

| Durum | Script ne yapar? |
| :--- | :--- |
| Resolve kurulu değil | Kurulum dosyasını İndirilenler klasöründe bulur (bulamazsa yolunu sorar) ve **kurar**. |
| Resolve kurulu, yeni dosya yok | Kurulu Resolve'u **otomatik onarır**. |
| Resolve kurulu + yeni dosya var | Tek bir soru sorar: **güncelle mi, onar mı?** |

İsteğe bağlı (çoğu kişiye gerekmez):

```bash
./davinci_resolve_installer.sh DOSYA.zip   # kurulum dosyasını elle ver (sormadan kurar)
./davinci_resolve_installer.sh --gui       # grafik kurulum sihirbazı (varsayılan: terminal kurulumu)
./davinci_resolve_installer.sh --fix       # zorla onarım
```

### ✨ SCRIPT NELERİ OTOMATİK YAPAR?
| Özellik | Açıklama |
| :--- | :--- |
| 🐧 **Dağıtım tespiti** | Ubuntu/Debian, Fedora ve Arch ailesini (Zorin, Mint, Pop!_OS, Nobara, Manjaro, EndeavourOS, CachyOS…) kendisi tanır. Komut değiştirmeniz gerekmez. |
| 📦 **Dayanıklı paket kurulumu** | Depoda olmayan bir paket tüm kurulumu **iptal etmez**; atlanır ve uyarı verilir. Ubuntu 24.04+ `t64` gibi yeniden adlandırılan paketleri kendisi seçer. |
| 🔧 **glib çakışması yaması** | Resolve'un getirdiği eski `glib` kütüphanelerini yedek klasöre taşır (`libs/disabled-libraries`). Hiçbir dosya silinmez. |
| 🔍 **Eksik kütüphane taraması** | Resolve ve Qt eklentileri için `ldd` ile eksikleri bulur, doğru paketi dağıtımın kendi veritabanından bulup kurar (`dnf` / `pacman -F` / `apt-file`). |
| 🖥️ **Her masaüstünde çalışan kurulum** | Varsayılan terminal kurulumu, Wayland/Hyprland/SSH'ta ekran erişimi sorunu yaşamaz. Qt hata verirse yedek platformu otomatik dener. |
| 💾 **Güvenli geçici dizin** | Kurulum paketini RAM tabanlı `/tmp` yerine diske (`/var/tmp`) açar. Geçici dizinde yaklaşık **12 GB**, kurulum dizininde yaklaşık **8 GB** boş alan gerekir. |
| 🗂️ **.zip desteği** | İndirdiğiniz `.zip` dosyasını kendisi açar. |
| 🚀 **Menü kısayolu** | Wayland uyumu için kısayola `QT_QPA_PLATFORM=xcb` ekler (kullanıcıya özel kopya, sistem dosyası değişmez). |
| 📝 **Günlük dosyası** | Her çalıştırmada `~/davinci-installer.log` dosyası yazılır. |

### 🐧 DESTEKLENEN DAĞITIMLAR
Artık komutları elle değiştirmeniz **gerekmez**. Script paket yöneticisini kendisi seçer:

| Aile | Örnekler | Paket yöneticisi |
| :--- | :--- | :--- |
| 🟧 **Ubuntu / Debian** | Ubuntu, Zorin OS, Linux Mint, Pop!_OS, Debian | `apt` |
| 🟩 **Fedora** | Fedora, Nobara | `dnf` |
| 🟥 **Arch** | Arch, Manjaro, EndeavourOS, CachyOS | `pacman` |

> [!NOTE]
> * Değişmez (immutable) sistemler (Fedora Silverblue, Bazzite vb.) desteklenmez. Distrobox içinde kurmanız önerilir.
> * Yukarıdaki ailelerin dışındaki dağıtımlarda (ör. openSUSE) bağımlılık adımı atlanır, kurulum yine de denenir.

### 🎮 EKRAN KARTI (GPU)
Script ekran kartını kendisi tespit eder ve ona göre hazırlık yapar:

| Kart | Ne yapılır? |
| :--- | :--- |
| 🟢 **NVIDIA** | Sürücü kontrol edilir (sürücüyü **kurmaz**). Eksikse: Ubuntu `ubuntu-drivers install`, Fedora RPM Fusion `akmod-nvidia`, Arch `nvidia` / `nvidia-open`. |
| 🔴 **AMD** | Dağıtımın kendi deposundan **Mesa OpenCL (Rusticl)** kurulur. Çalışan bir OpenCL varsa dokunulmaz. Resolve **OpenCL 1.2+** ister. Kullanıcı `render` ve `video` gruplarına eklenir, bu yüzden **oturumu kapatıp açın**. |
| 🔀 **Hibrit** (iGPU + NVIDIA) | Resolve işlemleri için NVIDIA kullanılır. |
| 🔵 **Yalnızca Intel** | Blackmagic Linux'ta resmi destek vermez; yalnızca uyarı verilir. |

AMD'de Resolve içinde: **Preferences → Memory and GPU → GPU Processing Mode: OpenCL**.

> [!TIP]
> Mesa ile OpenCL aygıtı görünmezse (ya da eski Mesa nedeniyle yalnızca OpenCL 1.1 çıkarsa) ROCm'u deneyin:
> ```bash
> DAVINCI_AMD_STACK=rocm ./davinci_resolve_installer.sh
> ```
> Script yalnızca dağıtımın resmi depolarındaki paketleri kurar (AUR veya üçüncü taraf depo eklemez).

### ⚙️ İLERİ SEVİYE (ORTAM DEĞİŞKENLERİ)
Normalde gerekmez. Örnek: `DAVINCI_GPU=amd ./davinci_resolve_installer.sh`

| Değişken | Açıklama |
| :--- | :--- |
| `DAVINCI_GPU` | Ekran kartı seçimini zorla: `auto` (varsayılan), `nvidia`, `amd`, `skip`. |
| `DAVINCI_AMD_STACK` | AMD OpenCL yığını: `auto` (Mesa), `mesa`, `rocm`, `skip`. |
| `DAVINCI_WORKDIR` | Geçici dosyalar için dizin (varsayılan: `/var/tmp`). |
| `DAVINCI_MIN_GB` | Geçici dizinde gereken en az boş alan, GB (varsayılan: `12`). |
| `DAVINCI_QPA` | Qt platformunu elle seç (ör. `minimal`). |
| `DAVINCI_NO_TEE` | `1` yaparsanız installer hata çıktısı yakalanmaz (soruları göremiyorsanız). |
| `RESOLVE_DIR` | Resolve kurulum dizini (varsayılan: `/opt/resolve`). |

### 🔄 GÜNCELLEME
* **Script ile:** Yeni `.zip` / `.run` dosyasını İndirilenler klasörüne koyup scripti aynı şekilde çalıştırın; "güncelle mi, onar mı?" diye sorar.
* **Blackmagic'in kendi kurulum dosyasıyla güncellediyseniz:** Güncelleme glib yamasını geri alır. Scripti tekrar çalıştırın, kurulu Resolve'u otomatik onarır.

### 🧰 SORUN GİDERME
* 📝 Her şey `~/davinci-installer.log` dosyasına yazılır.
* 🖥️ Resolve açılmıyorsa terminalden çalıştırıp hata çıktısına bakın: `QT_QPA_PLATFORM=xcb /opt/resolve/bin/resolve`
* 🔴 AMD'de "Unsupported GPU Processing Mode" çıkarsa: oturumu yenileyin, `clinfo` çalıştırın, olmazsa diğer yığını deneyin (`DAVINCI_AMD_STACK=rocm` veya `mesa`).

> [!TIP]
> ### 🤖 GELECEK İÇİN GÜNCELLEME
> Script paket isimlerindeki değişiklikleri büyük ölçüde kendisi telafi eder. Yine de yıllar sonra çalışmazsa, herhangi bir **YAPAY ZEKAYA** scripti ve `~/davinci-installer.log` dosyasını verip şu cümleyi yazarak güncelletin:
> *"BU DAVINCI RESOLVE KURULUM SCRIPTINI GÜNCEL LINUX ÇEKİRDEĞİNE VE PAKET İSİMLERİNE GÖRE MODERNIZE EDER MISIN?"* 💡

> [!NOTE]
> Her dağıtım ve donanım kombinasyonu test edilmemiştir. Sorun yaşarsanız `~/davinci-installer.log` dosyasıyla birlikte bir issue açın.

### ⚠️ KRİTİK NOTLAR
* 🔌 **GPU:** Mutlaka **GÜNCEL NVIDIA** sürücülerini kullanın.
* 🖥️ **XORG:** Genelde Wayland'da (XWayland ile) çalışır; açılmazsa giriş ekranında **X11 / "UBUNTU ON XORG"** oturumunu seçin.
* 🎬 **CODEC:** Ücretsiz sürümde H.264 videolar için **TRANSCODE** gerekebilir (opsiyonel çevirici scriptler bunun içindir).

---

## 🇺🇸 ENGLISH (README - EN)

This tool **AUTOMATICALLY RESOLVES** DaVinci Resolve installation, GPU setup and library conflicts on Linux (Ubuntu/Debian, Fedora and Arch families) **WITH A SINGLE SCRIPT**. 🛠️

> [!IMPORTANT]
> **NOTE:** The core file of this project is `davinci_resolve_installer.sh`. It now replaces the former `setup.sh` (install), `fix_resolve.sh` (repair) and the separate NVIDIA/AMD scripts **on its own**. All other tools (converters, etc.) are completely **optional** and can be used as needed.

### 🛠️ CONTENT
| File | Description |
| :--- | :--- |
| 📦 **davinci_resolve_installer.sh** | **Installs** dependencies, **prepares** your GPU, **installs / updates** Resolve and **fixes** launch issues. |
| 🎞️ **videocovmov.sh** | Transcodes MP4 to **MOV** for editing (Optional). |
| 📤 **mov_to_mp4.sh** | Converts edited files back to **MP4** for export (Optional). |

### 🚀 USAGE
Download the Linux `.zip` (or `.run`) of Resolve from the Blackmagic Design website, then:

```bash
chmod +x davinci_resolve_installer.sh
./davinci_resolve_installer.sh
```

The script asks for `sudo` by itself when needed. **You don't have to pass any options**; it detects the situation on its own:

| Situation | What the script does |
| :--- | :--- |
| Resolve is not installed | Finds the installer in your Downloads folder (asks for the path if not found) and **installs** it. |
| Resolve installed, no new file | **Repairs** the installed Resolve automatically. |
| Resolve installed + new file found | Asks one question: **update or repair?** |

Optional (most people won't need these):

```bash
./davinci_resolve_installer.sh FILE.zip    # give the installer file manually (installs without asking)
./davinci_resolve_installer.sh --gui       # graphical installer wizard (default: terminal install)
./davinci_resolve_installer.sh --fix       # force repair
```

### ✨ WHAT THE SCRIPT DOES AUTOMATICALLY
| Feature | Description |
| :--- | :--- |
| 🐧 **Distro detection** | Recognizes the Ubuntu/Debian, Fedora and Arch families (Zorin, Mint, Pop!_OS, Nobara, Manjaro, EndeavourOS, CachyOS…). No need to edit any commands. |
| 📦 **Resilient package install** | A package missing from the repos does **not abort** the whole install; it is skipped with a warning. Picks renamed packages (e.g. Ubuntu 24.04+ `t64`) on its own. |
| 🔧 **glib conflict patch** | Moves Resolve's bundled old `glib` libraries into a backup folder (`libs/disabled-libraries`). Nothing is deleted. |
| 🔍 **Missing library scan** | Finds missing libraries for Resolve and its Qt plugins with `ldd`, looks up the right package in your distro's own database and installs it (`dnf` / `pacman -F` / `apt-file`). |
| 🖥️ **Works on any desktop** | The default terminal install avoids display-access problems on Wayland/Hyprland/SSH. Automatically tries a fallback Qt platform if one fails. |
| 💾 **Safe temp directory** | Extracts the installer to disk (`/var/tmp`) instead of the RAM-backed `/tmp`. Needs roughly **12 GB** free in the temp directory and about **8 GB** in the install directory. |
| 🗂️ **.zip support** | Unpacks the downloaded `.zip` by itself. |
| 🚀 **Menu shortcut** | Adds `QT_QPA_PLATFORM=xcb` to the launcher for Wayland compatibility (a per-user copy; system files are untouched). |
| 📝 **Log file** | Every run writes `~/davinci-installer.log`. |

### 🐧 SUPPORTED DISTRIBUTIONS
You **no longer** need to edit commands by hand. The script picks the package manager itself:

| Family | Examples | Package manager |
| :--- | :--- | :--- |
| 🟧 **Ubuntu / Debian** | Ubuntu, Zorin OS, Linux Mint, Pop!_OS, Debian | `apt` |
| 🟩 **Fedora** | Fedora, Nobara | `dnf` |
| 🟥 **Arch** | Arch, Manjaro, EndeavourOS, CachyOS | `pacman` |

> [!NOTE]
> * Immutable systems (Fedora Silverblue, Bazzite, etc.) are not supported. Installing inside a Distrobox container is recommended.
> * On distributions outside the families above (e.g. openSUSE) the dependency step is skipped, but the installation is still attempted.

### 🎮 GPU
The script detects your graphics card and prepares it accordingly:

| Card | What happens |
| :--- | :--- |
| 🟢 **NVIDIA** | The driver is checked (the script does **not** install it). If missing: Ubuntu `ubuntu-drivers install`, Fedora RPM Fusion `akmod-nvidia`, Arch `nvidia` / `nvidia-open`. |
| 🔴 **AMD** | **Mesa OpenCL (Rusticl)** is installed from your distro's own repositories. A working OpenCL setup is left untouched. Resolve needs **OpenCL 1.2+**. Your user is added to the `render` and `video` groups, so **log out and back in**. |
| 🔀 **Hybrid** (iGPU + NVIDIA) | NVIDIA is used for Resolve's processing. |
| 🔵 **Intel only** | Blackmagic does not officially support it on Linux; only a warning is shown. |

On AMD, inside Resolve: **Preferences → Memory and GPU → GPU Processing Mode: OpenCL**.

> [!TIP]
> If no OpenCL device shows up with Mesa (or only OpenCL 1.1 appears because of an old Mesa), try ROCm:
> ```bash
> DAVINCI_AMD_STACK=rocm ./davinci_resolve_installer.sh
> ```
> The script only installs packages from your distro's official repositories (no AUR or third-party repos).

### ⚙️ ADVANCED (ENVIRONMENT VARIABLES)
Normally not needed. Example: `DAVINCI_GPU=amd ./davinci_resolve_installer.sh`

| Variable | Description |
| :--- | :--- |
| `DAVINCI_GPU` | Force the GPU choice: `auto` (default), `nvidia`, `amd`, `skip`. |
| `DAVINCI_AMD_STACK` | AMD OpenCL stack: `auto` (Mesa), `mesa`, `rocm`, `skip`. |
| `DAVINCI_WORKDIR` | Directory for temporary files (default: `/var/tmp`). |
| `DAVINCI_MIN_GB` | Minimum free space required in the temp directory, in GB (default: `12`). |
| `DAVINCI_QPA` | Pick the Qt platform manually (e.g. `minimal`). |
| `DAVINCI_NO_TEE` | Set to `1` to stop capturing installer error output (if you can't see its prompts). |
| `RESOLVE_DIR` | Resolve install directory (default: `/opt/resolve`). |

### 🔄 UPDATING
* **With the script:** Drop the new `.zip` / `.run` into your Downloads folder and run the script the same way; it asks "update or repair?".
* **If you updated with Blackmagic's own installer:** The update undoes the glib patch. Just run the script again; it repairs the installed Resolve automatically.

### 🧰 TROUBLESHOOTING
* 📝 Everything is logged to `~/davinci-installer.log`.
* 🖥️ If Resolve doesn't start, run it from a terminal and read the error output: `QT_QPA_PLATFORM=xcb /opt/resolve/bin/resolve`
* 🔴 On AMD, if you get "Unsupported GPU Processing Mode": refresh your session, run `clinfo`, and if that doesn't help try the other stack (`DAVINCI_AMD_STACK=rocm` or `mesa`).

> [!TIP]
> ### 🤖 FOR FUTURE UPDATES
> The script compensates for many package-name changes on its own. If it still stops working years from now, give the script and your `~/davinci-installer.log` to any **AI** and ask:
> *"CAN YOU MODERNIZE THIS DAVINCI RESOLVE INSTALLATION SCRIPT ACCORDING TO THE CURRENT LINUX KERNEL AND PACKAGE NAMES?"* 💡

> [!NOTE]
> Not every distribution and hardware combination has been tested. If you run into problems, please open an issue and attach `~/davinci-installer.log`.

### ⚠️ CRITICAL TIPS
1. 🔌 **GPU:** Ensure you are using the latest proprietary **NVIDIA** drivers.
2. 🖥️ **XORG:** It usually works on Wayland (via XWayland); if it doesn't launch, switch to the **X11 / "UBUNTU ON XORG"** session at login.
3. 🎬 **CODEC:** The free version may require transcoding to **MOV/PRORES** for H.264 footage (the optional converter scripts are for this).

---
*Created with ❤️ for the Linux Community by a Professional Video Editor*
