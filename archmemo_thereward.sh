mkfs.fat -F32 /dev/nvme0n1p1
cryptsetup luksFormat --cipher aes-xts-plain64 --key-size 512 --hash sha512 --iter-time 5000 --use-random --label luks /dev/nvme0n1p2
cryptsetup luksOpen /dev/nvme0n1p2 btrfs
mkfs.btrfs --label btrfs /dev/mapper/btrfs
mount /dev/mapper/btrfs /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@cache_system
btrfs subvolume create /mnt/@cache_user_root
btrfs subvolume create /mnt/@cache_user_azon
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@vartmp
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@swap
umount /mnt

mount -o compress=zstd,subvol=/@ /dev/mapper/btrfs /mnt
mkdir -p /mnt/.esp
mount /dev/nvme0n1p1 /mnt/.esp
mkdir -p /mnt/.esp/EFI/arch
mkdir -p /mnt/boot
mount --bind /mnt/.esp/EFI/arch /mnt/boot
mkdir -p /mnt/var/cache
mount -o compress=zstd,subvol=/@cache_system /dev/mapper/btrfs /mnt/var/cache
mkdir -p /mnt/root/.cache
mount -o compress=zstd,subvol=/@cache_user_root /dev/mapper/btrfs /mnt/root/.cache
mkdir -p /mnt/home/azon/.cache
mount -o compress=zstd,subvol=/@cache_user_azon /dev/mapper/btrfs /mnt/home/azon/.cache
mkdir -p /mnt/var/log
mount -o compress=zstd,subvol=/@log /dev/mapper/btrfs /mnt/var/log
mkdir -p /mnt/tmp
mount -o compress=zstd,subvol=/@tmp /dev/mapper/btrfs /mnt/tmp
mkdir -p /mnt/var/tmp
mount -o compress=zstd,subvol=/@vartmp /dev/mapper/btrfs /mnt/var/tmp
mkdir -p /mnt/.snapshots
mount -o compress=zstd,subvol=/@snapshots /dev/mapper/btrfs /mnt/.snapshots
mkdir -p /mnt/.swap
mount -o compress=zstd,subvol=/@swap /dev/mapper/btrfs /mnt/.swap
touch /mnt/.swap/swap
chattr +C /mnt/.swap/swap
btrfs property set /mnt/.swap/swap compression none
fallocate -l 16G /mnt/.swap/swap
mkswap /mnt/.swap/swap
swapon /mnt/.swap/swap

pacstrap /mnt base base-devel linux linux-firmware dosfstools btrfs-progs sof-firmware linux-headers v4l2loopback-dkms neovim man-db man-pages
genfstab -U /mnt >> /mnt/etc/fstab
sed -i -E -e "s/\/mnt(\/\.esp\/EFI\/arch)/\1/g" /mnt/etc/fstab
arch-chroot /mnt

# ------------------------------------------------------------------------------

ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc --utc

sed -i -E -e "s/#(en_US\.UTF-8 UTF-8)/\1/" /etc/locale.gen
sed -i -E -e "s/#(ja_JP\.UTF-8 UTF-8)/\1/" /etc/locale.gen
locale-gen
echo LANG=ja_JP.UTF-8 > /etc/locale.conf
echo KEYMAP=jp106 > /etc/vconsole.conf

echo thereward > /etc/hostname

pacman -S wireless-regdb
sed -i -E -e "s/#(WIRELESS_REGDOM=\"JP\")/\1/" /etc/conf.d/wireless-regdom

pacman -S networkmanager
# edit /etc/NetworkManager/conf.d
systemctl enable NetworkManager

sed -i -E -e "s/HOOKS=\(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck\)/HOOKS=\(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems resume fsck\)/" /etc/mkinitcpio.conf
mkinitcpio -P

passwd

pacman -S intel-ucode
bootctl --path=.esp install
cat > /.esp/loader/entries/arch.conf << EOF
title Arch Linux
linux /EFI/arch/vmlinuz-linux
initrd /EFI/arch/intel-ucode.img
initrd /EFI/arch/initramfs-linux.img
options root=LABEL=btrfs rootflags=subvol=/@ rw cryptdevice=LABEL=luks:btrfs
EOF

echo blacklist pcspkr > /etc/modprobe.d/nobeep.conf

echo v4l2loopback > /etc/modules-load.d/virtualcamera.conf

# ------------------------------------------------------------------------------

useradd -m -G wheel -s /bin/bash azon
cp -R /etc/skel/. /home/azon
chown -R azon:azon /home/azon
EDITOR=vim visudo
passwd azon
passwd -l root

# ------------------------------------------------------------------------------

sudo pacman -S git
# edit ~/.gitconfig

mkdir ~/repos
pushd ~/repos
git clone https://aur.archlinux.org/yay.git
pushd yay
makepkg -sri
popd
rm -rf yay
popd

sudo timedatectl set-ntp true

sudo sed -i -E -e "s/#(\[multilib\])/\1/" -e "/\[multilib\]/{n;s/#(.+)/\1/}" /etc/pacman.conf
yay -Sy

sudo sed -i -E -e "s/#(PACKAGER)=\"[^\"]+\"/\1=\"Shu Takayama <syu.takayama@gmail.com>\"/" /etc/makepkg.conf
sudo sed -i -E -e "s/OPTIONS=\(strip docs \!libtool \!staticlibs emptydirs zipman purge debug lto\)/OPTIONS=\(strip docs \!libtool \!staticlibs emptydirs zipman purge \!debug lto\)/" /etc/makepkg.conf

yay -S snapper
sudo umount /.snapshots
sudo rmdir /.snapshots
sudo snapper -c default create-config /
sudo btrfs subvolume delete /.snapshots
sudo mkdir /.snapshots
sudo mount -o compress=zstd,subvol=@snapshots /dev/mapper/btrfs /.snapshots
sudo sed -i -E -e "s/(TIMELINE_LIMIT_HOURLY)=\"[0-9]+\"/\1=\"6\"/" /etc/snapper/configs/default
sudo sed -i -E -e "s/(TIMELINE_LIMIT_DAILY)=\"[0-9]+\"/\1=\"24\"/" /etc/snapper/configs/default
sudo sed -i -E -e "s/(TIMELINE_LIMIT_WEEKLY)=\"[0-9]+\"/\1=\"7\"/" /etc/snapper/configs/default
sudo sed -i -E -e "s/(TIMELINE_LIMIT_MONTHLY)=\"[0-9]+\"/\1=\"0\"/" /etc/snapper/configs/default
sudo sed -i -E -e "s/(TIMELINE_LIMIT_YEARLY)=\"[0-9]+\"/\1=\"0\"/" /etc/snapper/configs/default
sudo systemctl enable snapper-timeline.timer
sudo systemctl enable snapper-cleanup.timer

yay -S tlp ethtool lsb-release smartmontools x86_energy_perf_policy acpi_call
sudo sed -i -E -e "s/#(START_CHARGE_THRESH_BAT0)=[0-9]+/\1=75/" /etc/tlp.conf
sudo sed -i -E -e "s/#(STOP_CHARGE_THRESH_BAT0)=[0-9]+/\1=80/" /etc/tlp.conf
sudo sed -i -E -e "s/#(RESTORE_THRESHOLDS_ON_BAT)=[01]/\1=1/" /etc/tlp.conf
sudo systemctl enable tlp
sudo systemctl mask systemd-rfkill
sudo systemctl mask systemd-rfkill.socket

yay -S networkmanager-pptp

yay -S networkmanager-l2tp strongswan

yay -S networkmanager-openvpn

sudo sed -i -E -e "s/#(DNSSEC=no)/\1/" /etc/systemd/resolved.conf
# edit /etc/NetworkManager/conf.d
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo systemctl enable systemd-resolved

yay -S bluez
sudo systemctl enable bluetooth

yay -S docker
sudo systemctl enable docker

yay -S docker-compose

yay -S tor
sudo systemctl enable tor

yay -S proxychains-ng
sudo sed -i -E -e "s/socks4 \t127\.0\.0\.1 9050/socks5 \t127.0.0.1 9050/" /etc/proxychains.conf

mkdir ~/.profile.d
# edit ~/.bash_profile

mkdir ~/.bashrc.d
# edit ~/.bashrc

yay -S bash-completion

yay -S asdf-vm
# edit ~/.profile.d

yay -S go
# edit ~/.profile.d

yay -S npm

yay -S opam
opam init
# edit ~/.profile.d
opam repo add coq-released https://coq.inria.fr/opam/released

yay -S jdk11-openjdk
archlinux-java set java-11-openjdk

sudo npm install -g neovim
yay -S python-pynvim
# edit ~/.config/nvim
# edit ~/.profile.d

# edit ~/.ssh/config
# edit ~/.profile.d

yay -S android-udev android-tools
sudo gpasswd -a azon adbusers

yay -S android-studio
# edit ~/.profile.d
sudo npm install -g nativescript

yay -S xdg-utils
# edit ~/.bashrc.d

yay -S xclip
# edit ~/.bashrc.d

yay -S tmux
# edit ~/.tmux.conf

yay -S texlive texlive-langjapanese texlive-langgreek
# edit ~/.latexmkrc

yay -S git-lfs

yay -S clang

yay -S gopls

sudo npm install -g typescript-language-server

sudo npm install -g pyright

yay -S flake8

yay -S python-isort

yay -S terraform-ls

yay -S solidity-bin

yay -S ac-library

yay -S cblas

sudo npm install -g @vue/cli

yay -S terraform

yay -S unarchiver

yay -S zip

yay -S iftop

yay -S lshw

yay -S gnu-netcat

yay -S bind

yay -S mtr

yay -S jq

yay -S gnuplot

yay -S ffmpeg

yay -S youtube-dl

yay -S slackcat

sudo npm install -g hexo-cli

yay -S namcap

go install golang.org/x/tools/cmd/goimports@latest

yay -S golangci-lint-bin

yay -S google-cloud-cli

yay -S imagemagick

yay -S elan-lean
elan toolchain install leanprover/lean4:stable

# ------------------------------------------------------------------------------

yay -S lightdm lightdm-gtk-greeter
sudo systemctl enable lightdm

yay -S xorg-server xorg-xwininfo
# edit ~/.xprofile

localectl set-x11-keymap jp pc104

yay -S pulseaudio pulseaudio-alsa pulseaudio-bluetooth

yay -S xfce4 ristretto xfce4-taskmanager xfce4-notifyd xfce4-screenshooter xfce4-clipman-plugin lightdm-gtk-greeter-settings pavucontrol xfce4-pulseaudio-plugin network-manager-applet blueberry light-locker gvfs gvfs-gphoto2 gvfs-mtp qt5-styleplugins gnome-keyring papirus-icon-theme
# edit ~/.profile.d

yay -S noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-hackgen
# edit /etc/fonts/local.conf

yay -S fcitx5-im mozc-ut fcitx5-mozc-ut
# edit ~/.profile.d

yay -S cups
sudo systemctl enable cups
yay -S brother-mfc-l9570cdw
yay -S epson-inkjet-printer-escpr2

# ------------------------------------------------------------------------------

# PulseAudio configuration

# Xfce configuration
## 個人設定/Xfce ターミナル設定/一般/スクロール/スクロールバー
## 個人設定/Xfce ターミナル設定/一般/スクロール/U
## 個人設定/Xfce ターミナル設定/外観/フォント/F
## 個人設定/Xfce ターミナル設定/外観/背景
## 個人設定/Xfce ターミナル設定/外観/新しいウィンドウを開く場合/M
## 個人設定/ウィンドウマネージャー (詳細)/アクセシビリティ/L
## 個人設定/ウィンドウマネージャー (詳細)/ワークスペース/M
## 個人設定/ウィンドウマネージャー (詳細)/コンポジット処理/D
## 個人設定/デスクトップ/背景/デスクトップの壁紙
## 個人設定/デスクトップ/メニュー/デスクトップメニュー/D
## 個人設定/デスクトップ/メニュー/ウィンドウリストメニュー/W
## 個人設定/デスクトップ/アイコン/外観/アイコンタイプ
## 個人設定/パネル/パネル1/外観/全般/ダークモード
## 個人設定/パネル/パネル1/アイテム/アプリケーションメニュー/外観/E
## 個人設定/パネル/パネル1/アイテム/アプリケーションメニュー/外観/S
## 個人設定/パネル/パネル1/アイテム/ウィンドウボタン/外観/並び替え順
## 個人設定/パネル/パネル1/アイテム/ウィンドウボタン/振る舞い/ウィンドウのグループ化
## 個人設定/パネル/パネル1/アイテム/Clipman
## 個人設定/パネル/パネル1/アイテム/電源管理プラグイン
## 個人設定/パネル/パネル1/アイテム/時計/外観/ツールチップの形式
## 個人設定/パネル/パネル1/アイテム/時計/時計のオプション/表示形式
## 個人設定/パネル/パネル1/アイテム/アクションボタン/アクション
## 個人設定/パネル/パネル2
## 個人設定/外観/アイコン
## 個人設定/外観/フォント/レンダリング
## ハードウェア/ディスプレイ/全般/1/周波数
## ハードウェア/電源管理/一般/ボタン
## ハードウェア/電源管理/システム
## ハードウェア/電源管理/ディスプレイ
## ハードウェア/電源管理/セキュリティ
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/logind-handle-lid-switch -s false
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/brightness-switch-restore-on-exit -s 1
## システム/LightDM GTK+ Greeterの設定/外観/テーマ
## システム/LightDM GTK+ Greeterの設定/外観/アイコン
## azon のログアウト/S

# CUPS configuration

yay -S wireshark-qt
sudo gpasswd -a azon wireshark

yay -S virtualbox virtualbox-host-modules-arch
sudo gpasswd -a azon vboxusers

yay -S vmware-workstation
systemctl enable vmware-usbarbitrator
systemctl enable vmware-networks

yay -S google-chrome
# Google Chrome configuration
## デザイン/フォントをカスタマイズ
# Xfce configuration
## システム/デフォルトアプリケーション/インターネット/ウェブブラウザー

yay -S firefox firefox-i18n-ja
# Firefox configuration
## 一般/ネットワーク設定/E
## プライバシーとセキュリティ/ブラウザープライバシー/履歴/W

yay -S torbrowser-launcher

yay -S slack-desktop
# Slack configuration

yay -S zoom
# Zoom configuration

yay -S discord
# Discord configuration

yay -S transmission-gtk

yay -S qpdfview

yay -S gimp

yay -S eclipse-java
# Eclipse configuration

yay -S intellij-idea-community-edition
# IntelliJ IDEA configuration

# Android Studio configuration

yay -S zotero-bin

yay -S obs-studio

opam install coq coq-mathcomp-ssreflect

yay -S tla-toolbox

yay -S ganache-bin

yay -S steam

yay -S minecraft-launcher

yay -S mcpelauncher-appimage

yay -S wine winetricks

yay -S diff-pdf

yay -S audacity

yay -S voicevox-appimage

yay -S visual-studio-code-bin
