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
fallocate -l 8G /mnt/.swap/swap
mkswap /mnt/.swap/swap
swapon /mnt/.swap/swap

pacstrap /mnt base base-devel linux linux-firmware dosfstools btrfs-progs vim man-db man-pages
genfstab -U /mnt >> /mnt/etc/fstab
sed -i -E -e "s/\/mnt(\/\.esp\/EFI\/arch)/\1/g" /mnt/etc/fstab
arch-chroot /mnt

# ------------------------------------------------------------------------------

ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc --utc

sed -i -E -e "s/#(en_US.UTF-8 UTF-8)/\1/" /etc/locale.gen
sed -i -E -e "s/#(ja_JP.UTF-8 UTF-8)/\1/" /etc/locale.gen
locale-gen
echo LANG=ja_JP.UTF-8 > /etc/locale.conf
echo KEYMAP=jp106 > /etc/vconsole.conf

echo mynewgear > /etc/hostname

pacman -S crda
sed -i -E -e "s/#(WIRELESS_REGDOM=\"JP\")/\1/" /etc/conf.d/wireless-regdom

pacman -S networkmanager
# edit /etc/NetworkManager/conf.d
systemctl enable NetworkManager

sed -i -E -e "s/HOOKS=\(base udev autodetect modconf block filesystems keyboard fsck\)/HOOKS=\(base udev autodetect modconf block keyboard keymap encrypt filesystems resume fsck\)/" /etc/mkinitcpio.conf
mkinitcpio -P

passwd

pacman -S intel-ucode
bootctl --path=.esp install
cat > /.esp/loader/entries/arch.conf << EOF
title Arch Linux
linux /EFI/arch/vmlinuz-linux
initrd /EFI/arch/intel-ucode.img
initrd /EFI/arch/initramfs-linux.img
options root=LABEL=btrfs rootflags=subvol=/@ rw cryptdevice=LABEL=luks:btrfs pci=noaer
EOF

echo blacklist pcspkr > /etc/modprobe.d/nobeep.conf

# ------------------------------------------------------------------------------

timedatectl set-ntp true

sed -i -E -e "s/#(\[multilib\])/\1/" -e "/\[multilib\]/{n;s/#(.+)/\1/}" /etc/pacman.conf
pacman -Sy

sed -i -E -e "s/#(PACKAGER)=\"[^\"]+\"/\1=\"Shu Takayama <syu.takayama@gmail.com>\"/" /etc/makepkg.conf

pacman -S snapper
umount /.snapshots
rmdir /.snapshots
snapper -c default create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount -o compress=zstd,subvol=@snapshots /dev/mapper/btrfs /.snapshots
sed -i -E -e "s/(TIMELINE_LIMIT_HOURLY)=\"[0-9]+\"/\1=\"6\"/" /etc/snapper/configs/default
sed -i -E -e "s/(TIMELINE_LIMIT_DAILY)=\"[0-9]+\"/\1=\"24\"/" /etc/snapper/configs/default
sed -i -E -e "s/(TIMELINE_LIMIT_WEEKLY)=\"[0-9]+\"/\1=\"7\"/" /etc/snapper/configs/default
sed -i -E -e "s/(TIMELINE_LIMIT_MONTHLY)=\"[0-9]+\"/\1=\"0\"/" /etc/snapper/configs/default
sed -i -E -e "s/(TIMELINE_LIMIT_YEARLY)=\"[0-9]+\"/\1=\"0\"/" /etc/snapper/configs/default
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

pacman -S tlp ethtool lsb-release smartmontools x86_energy_perf_policy
sed -i -E -e "s/#(SOUND_POWER_SAVE_ON_AC)=[01]/\1=0/" /etc/tlp.conf
sed -i -E -e "s/#(SOUND_POWER_SAVE_ON_BAT)=[01]/\1=0/" /etc/tlp.conf
sed -i -E -e "s/#(SOUND_POWER_SAVE_CONTROLLER)=[NY]/\1=N/" /etc/tlp.conf
systemctl enable tlp
systemctl mask systemd-rfkill
systemctl mask systemd-rfkill.socket

pacman -S bluez
systemctl enable bluetooth

pacman -S docker
systemctl enable docker

pacman -S docker-compose

pacman -S tor
systemctl enable tor

pacman -S proxychains-ng
sed -i -E -e "s/socks4 \t127\.0\.0\.1 9050/socks5 \t127.0.0.1 9050/" /etc/proxychains.conf

useradd -m -G wheel -s /bin/bash azon
cp -R /etc/skel/. /home/azon
chown -R azon:azon /home/azon
EDITOR=vim visudo
passwd azon
passwd -l root

sed -i -E -e "s/#(DNSSEC=no)/\1/" /etc/systemd/resolved.conf
# edit /etc/NetworkManager/conf.d
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable systemd-resolved

# ------------------------------------------------------------------------------

mkdir ~/.profile.d
# edit ~/.bash_profile

sudo pacman -S go
# edit ~/.profile.d

sudo pacman -S npm

sudo pacman -S neovim
sudo npm install -g neovim
sudo pacman -S python-pynvim
# edit ~/.config/nvim
# edit ~/.profile.d

sudo pacman -S openssh
# edit ~/.ssh/config
# edit ~/.profile.d

sudo pacman -S android-udev android-tools
sudo gpasswd -a azon adbusers

sudo pacman -S bash-completion

# ------------------------------------------------------------------------------

mkdir ~/.bashrc.d
# edit ~/.bashrc

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

yay -S xdg-utils
# edit ~/.bashrc.d
source ~/.bashrc

yay -S xclip
# edit ~/.bashrc.d
source ~/.bashrc

yay -S tmux
# edit ~/.tmux.conf

yay -S texlive-most texlive-langjapanese
# edit ~/.latexmkrc

yay -S unarchiver

yay -S zip

yay -S gnu-netcat

yay -S mtr

yay -S clang

yay -S gopls

yay -S jq

yay -S namcap

yay -S gnuplot

yay -S bind

yay -S ffmpeg

yay -S youtube-dl

sudo npm install -g hexo-cli

# edit ~/.bashrc
source ~/.bashrc

yay -S lightdm lightdm-gtk-greeter
sudo systemctl enable lightdm

yay -S xorg-server
# edit /etc/X11/xorg.conf.d
# edit ~/.xprofile

localectl set-x11-keymap jp sun_type7_jp_usb

yay -S pulseaudio pulseaudio-alsa

yay -S xfce4 ristretto xfce4-taskmanager xfce4-notifyd xfce4-screenshooter xfce4-clipman-plugin lightdm-gtk-greeter-settings pavucontrol xfce4-pulseaudio-plugin network-manager-applet blueberry light-locker gvfs gvfs-gphoto2 gvfs-mtp qt5-styleplugins
# edit ~/.profile.d

yay -S noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-cica
# edit /etc/fonts/local.conf

yay -S fcitx-im fcitx-mozc fcitx-configtool
# edit ~/.profile.d

yay -S cups
sudo systemctl enable cups
yay -S brother-mfc-l9570cdw

yay -S wireshark-qt
sudo gpasswd -a azon wireshark

yay -S virtualbox virtualbox-host-modules-arch
sudo gpasswd -a azon vboxusers

# ------------------------------------------------------------------------------

# PulseAudio configulation

# Xfce configulation
## 個人設定/Xfce ターミナル設定/一般/スクロール/スクロールバー
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
## 個人設定/外観/フォント/レンダリング
## ハードウェア/ディスプレイ/全般/1/周波数
## ハードウェア/ディスプレイ/詳細/接続中のディスプレイ/プロファイル
## ハードウェア/ディスプレイ/詳細/接続中のディスプレイ/新しくディスプレイが接続されたとき設定する
## ハードウェア/ディスプレイ/詳細/接続中のディスプレイ/新しくディスプレイが接続されたときプロファイルを自動的に有効にする
## ハードウェア/電源管理/一般/ボタン
## ハードウェア/電源管理/システム
## ハードウェア/電源管理/ディスプレイ
## ハードウェア/電源管理/セキュリティ
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/logind-handle-lid-switch -s false
## システム/LightDM GTK+ Greeterの設定/外観/テーマ
## システム/LightDM GTK+ Greeterの設定/外観/アイコン
## azon のログアウト/S

# Fcitx configulation
## 全体の設定/ホットキー/入力メソッドのオンオフ
## Mozc プロパティ/一般/基本設定/句読点

# CUPS configulation

yay -S google-chrome
# Google Chrome configulation
## デザイン/フォントをカスタマイズ
# Xfce configulation
## システム/デフォルトアプリケーション/インターネット/ウェブブラウザー

yay -S tor-browser

yay -S slack-desktop

yay -S zoom

yay -S discord

yay -S f5vpn

yay -S transmission-gtk

yay -S evince-no-gnome

yay -S gimp

yay -S intellij-idea-community-edition
# IntelliJ IDEA configulation

yay -S slackcat

yay -S zotero

yay -S obs-studio

yay -S coqide

yay -S networkmanager-pptp

yay -S networkmanager-l2tp libreswan
sudo systemctl enable ipsec
sudo systemctl start ipsec
