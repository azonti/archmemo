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

pacstrap /mnt base base-devel linux linux-firmware dkms rtl88xxau-aircrack-dkms-git linux-headers dosfstools btrfs-progs wget vim man-db man-pages intel-ucode
genfstab -U /mnt >> /mnt/etc/fstab
sed -i -E -e "s/\/mnt(\/\.esp\/EFI\/arch)/\1/g" /mnt/etc/fstab
arch-chroot /mnt

# ------------------------------------------------------------------------------

echo blacklist pcspkr > /etc/modprobe.d/nobeep.conf
echo blacklist ath10k_pci > /etc/modprobe.d/nointwlan.conf

ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc --utc

sed -i -E -e "s/#(en_US.UTF-8 UTF-8)/\1/" /etc/locale.gen
sed -i -E -e "s/#(ja_JP.UTF-8 UTF-8)/\1/" /etc/locale.gen
locale-gen
echo LANG=ja_JP.UTF-8 > /etc/locale.conf
echo KEYMAP=jp106 > /etc/vconsole.conf

echo mynewgear > /etc/hostname

sed -i -E -e "s/#(PACKAGER)=\"[^\"]+\"/\1=\"Shu Takayama <syu.takayama@gmail.com>\"/" /etc/makepkg.conf

sed -i -E -e "s/#(\[multilib\])/\1/" -e "/\[multilib\]/{n;s/#(.+)/\1/}" /etc/pacman.conf

pacman -S crda
sed -i -E -e "s/#(WIRELESS_REGDOM=\"JP\")/\1/" /etc/conf.d/wireless-regdom

pacman -S networkmanager
# edit /etc/NetworkManager/conf.d
# edit /etc/NetworkManager/dispatcher.d
sed -i -E -e "s/#(DNSSEC=no)/\1/" /etc/systemd/resolved.conf
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable NetworkManager
systemctl enable systemd-resolved

pacman -S bluez
systemctl enable bluetooth

sed -i -E -e "s/HOOKS=\(base udev autodetect modconf block filesystems keyboard fsck\)/HOOKS=\(base udev autodetect modconf block keyboard keymap consolefont encrypt filesystems resume fsck\)/" /etc/mkinitcpio.conf
mkinitcpio -P

passwd

bootctl --path=.esp install
cat > /.esp/loader/entries/arch.conf << EOF
title	Arch Linux
linux	/EFI/arch/vmlinuz-linux
initrd	/EFI/arch/intel-ucode.img
initrd	/EFI/arch/initramfs-linux.img
options	root=LABEL=btrfs rootflags=subvol=/@ rw resume=LABEL=btrfs resume_offset=16400 cryptdevice=LABEL=luks:btrfs pci=noaer
EOF

# ------------------------------------------------------------------------------

timedatectl set-ntp true

localectl set-x11-keymap jp sun_type7_jp_usb OADG109A

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

pacman -S docker
systemctl enable docker

pacman -S docker-compose

pacman -S tor
systemctl enable tor

pacman -S proxychains-ng
# edit /etc/proxychains.conf

useradd -m -G wheel -s /bin/bash azon
EDITOR=vim visudo
passwd azon
passwd -l root

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

# ------------------------------------------------------------------------------

mkdir ~/.bashrc.d
# edit ~/.bashrc
source ~/.bashrc

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
# edit ~/.bashrc.d
source ~/.bashrc

yay -S thefuck
# edit ~/.bashrc.d
source ~/.bashrc

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

yay -S bash-completion

yay -S unarchiver

yay -S zip

yay -S gnu-netcat

yay -S mtr

yay -S jdk-openjdk jdk11-openjdk

yay -S gopls

yay -S php

yay -S jq

sudo npm install -g tldr

yay -S namcap

yay -S gnuplot

yay -S go-ipfs

yay -S hashcash

yay -S bind

yay -S clang

yay -S dex2jar

yay -S youtube-dl

sudo npm install -g hexo-cli

pushd ~/repos
git clone git@github.com:atcoder/ac-library.git
pushd ac-library
git checkout production
popd
popd
sudo ln -s ~/repos/ac-library/atcoder /usr/local/include/

# edit ~/.bashrc
source ~/.bashrc

yay -S lightdm lightdm-gtk-greeter
sudo systemctl enable lightdm.service

yay -S xorg-server
# edit /etc/X11/xorg.conf.d
# edit ~/.xprofile

yay -S pulseaudio pulseaudio-alsa

yay -S xfce4 ristretto xfce4-taskmanager xfce4-notifyd xfce4-screenshooter xfce4-clipman-plugin lightdm-gtk-greeter-settings pavucontrol xfce4-pulseaudio-plugin network-manager-applet blueberry light-locker gvfs gvfs-gphoto2 gvfs-mtp numix-gtk-theme gtk-engine-murrine qt5-styleplugins
# edit ~/.profile.d

yay -S noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-cica
# edit /etc/fonts/fonts.conf
sudo ln -s /etc/fonts/conf.avail/09-autohint-if-no-hinting.conf /etc/fonts/conf.d/
sudo ln -s /etc/fonts/conf.avail/10-hinting-full.conf /etc/fonts/conf.d/
sudo ln -s /etc/fonts/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d/
sudo ln -s /etc/fonts/conf.avail/11-lcdfilter-default.conf /etc/fonts/conf.d/
sudo ln -s /etc/fonts/conf.avail/65-khmer.conf /etc/fonts/conf.d/
sudo ln -s /etc/fonts/conf.avail/70-noto-cjk.conf /etc/fonts/conf.d/

yay -S fcitx-im fcitx-mozc fcitx-configtool
# edit ~/.profile.d

yay -S cups
sudo systemctl enable cups
yay -S foomatic-db-engine foomatic-db foomatic-db-ppds foomatic-db-nonfree foomatic-db-nonfree-ppds
yay -S brother-mfc-l9570cdw

yay -S wireshark-qt
sudo gpasswd -a azon wireshark

yay -S virtualbox virtualbox-host-modules-arch
sudo gpasswd -a azon vboxusers

# ------------------------------------------------------------------------------

# PulseAudio configulation

# Xfce configulation

# Fcitx configulation

# CUPS configulation

yay -S chromium chromium-widevine

yay -S firefox firefox-i18n-ja

yay -S tor-browser

yay -S sylpheed
ln -s /usr/share/applications/sylpheed.desktop ~/.config/autostart/

yay -S atomic-tweetdeck

yay -S slack-desktop

yay -S zoom
ln -s /usr/share/applications/Zoom.desktop ~/.config/autostart/

yay -S discord

yay -S f5vpn

yay -S transmission-gtk

yay -S evince-no-gnome

yay -S gimp

yay -S eclipse-java-bin

yay -S wine wine-mono wine-gecko winetricks
yay  -S --asdeps lib32-libpulse

yay -S jd-gui-bin

yay -S slackcat

yay -S zotero

sudo npm install -g truffle
yay -S ganache-bin

yay -S electrum

yay -S obs-studio
