mkfs.fat -F32 /dev/nvme0n1p1
cryptsetup luksFormat --cipher aes-xts-plain64 --key-size 512 --hash sha512 --iter-time 5000 --use-random --label=luks /dev/nvme0n1p2
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

pacstrap /mnt base base-devel linux linux-firmware dosfstools btrfs-progs wget vim man-db man-pages efibootmgr intel-ucode pulseaudio pulseaudio-alsa
genfstab -U /mnt >> /mnt/etc/fstab
sed -i -E -e "s/\/mnt(\/\.esp\/EFI\/arch)/\1/g" /mnt/etc/fstab
arch-chroot /mnt

# ------------------------------------------------------------------------------

echo blacklist pcspkr > /etc/modprobe.d/nobeep.conf

ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc --utc

sed -i -E -e "s/#(en_US.UTF-8 UTF-8)/\1/" /etc/locale.gen
sed -i -E -e "s/#(ja_JP.UTF-8 UTF-8)/\1/" /etc/locale.gen
locale-gen
echo LANG=ja_JP.UTF-8 > /etc/locale.conf
echo KEYMAP=jp106 > /etc/vconsole.conf

echo mynewgear > /etc/hostname

sed -i -E -e "s/#(PACKAGER)=\"[^\"]+\"/\1=\"Shu Takayama <syu.takayama@gmail.com>\"/" /etc/makepkg.conf

pacman -S crda
sed -i -E -e "s/#(WIRELESS_REGDOM=\"JP\")/\1/" /etc/conf.d/wireless-regdom

pacman -S networkmanager
cat > /etc/NetworkManager/conf.d/30-mac-randomization.conf << EOF
[connection-mac-randomization]
ethernet.cloned-mac-address=random
wifi.cloned-mac-address=random
EOF
# edit /etc/NetworkManager/dispatcher.d
systemctl enable NetworkManager

sed -i -E -e "s/HOOKS=\(base udev autodetect modconf block filesystems keyboard fsck\)/HOOKS=\(base udev autodetect modconf block keyboard keymap consolefont en-bincrypt filesystems resume fsck\)/" /etc/mkinitcpio.conf
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

sed -i -E -e "s/#(DNSSEC=no)/\1/" /etc/systemd/resolved.conf
cat > /etc/NetworkManager/conf.d/30-zeroconf.conf << EOF
[connection]
connection.mdns=2
connection.llmnr=2
EOF
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable systemd-resolved

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

useradd -m -G wheel -s /bin/bash azon
visudo
passwd azon
passwd -l root

# ------------------------------------------------------------------------------

mkdir ~/.profile.d
cat > ~/.bash_profile << EOF
if [[ -d ~/.profile.d ]]; then
  for file in ~/.profile.d/*.c.sh; do
    source "\$file"
  done
fi

[[ -f ~/.bashrc ]] && . ~/.bashrc
EOF

sudo pacman -S go
cat > ~/.profile.d/10-go.c.sh << EOF
export GOPATH=~/go
export PATH="\$PATH:\$GOPATH/bin"
EOF
chmod a+x ~/.profile.d/10-go.c.sh

sudo pacman -S npm

sudo pacman -S python-pip

sudo pacman -S neovim
sudo npm install -g neovim
sudo pip install neovim
# edit ~/.config/nvim
cat > ~/.profile.d/20-neovim.c.sh << EOF
export EDITOR=nvim
export VISUAL=nvim
EOF
chmod a+x ~/.profile.d/20-neovim.c.sh

sudo pacman -S openssh
# edit ~/.ssh/config
cat > ~/.profile.d/20-ssh-agent.c.sh << EOF
eval \$(ssh-agent)
ssh-add ~/.ssh/id_ed25519
EOF
chmod a+x ~/.profile.d/20-ssh-agent.c.sh

# ------------------------------------------------------------------------------

mkdir ~/.bashrc.d
cat > ~/.bashrc << EOF
# If not running interactively, don't do anything
[[ $- != *i* ]] && return

if [[ -d ~/.bashrc.d ]]; then
  for file in ~/.bashrc.d/*.sh; do
    source "$file"
  done
fi
EOF
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
popd
cat > ~/.bashrc.d/20-yay.sh << EOF
GROUP_LIST="base-devel xfce4 fcitx-im texlive-most"
alias package-list="comm -23 <((yay -Qqe; echo ${GROUP_LIST} | tr ' ' '\n') | sort) <(yay -Qqg ${GROUP_LIST} | sort)"
EOF
chmod a+x ~/.bashrc.d/20-yay.sh
source ~/.bashrc

yay -S thefuck
cat > ~/.bashrc.d/20-thefuck.sh << EOF
eval \$(thefuck --alias)
EOF
chmod a+x ~/.bashrc.d/20-thefuck.sh
source ~/.bashrc

yay -S xdg-utils
cat > ~/.bashrc.d/20-xdg-open.sh << EOF
alias open="xdg-open &>/dev/null"
EOF
chmod a+x ~/.bashrc.d/20-xdg-open.sh
source ~/.bashrc

yay -S xclip
cat > ~/.bashrc.d/20-xclip.sh << EOF
alias pbcopy="xclip -i -selection clipboard"
alias pbpaste="xclip -o -selection clipboard"
EOF
chmod a+x ~/.bashrc.d/20-xclip.sh
source ~/.bashrc

yay -S bash-completion

yay -S gnu-netcat

yay -S tmux
# edit ~/.tmux.conf

yay -S texlive-most texlive-langjapanese
# edit ~/.latexmkrc

yay -S namcap

yay -S lightdm lightdm-gtk-greeter
sudo systemctl enable lightdm.service

yay -S xorg-server
cat > ~/.xprofile << EOF
if [[ -d ~/.profile.d ]]; then
  for file in ~/.profile.d/*.[cg].sh; do
    source "\$file"
  done
fi
EOF

yay -S xfce4 xfce4-taskmanager xfce4-notifyd lightdm-gtk-greeter-settings pavucontrol xfce4-pulseaudio-plugin network-manager-applet light-locker gvfs gvfs-gphoto2 gvfs-mtp numix-gtk-theme gtk-engine-murrine qt5-styleplugins
cat > ~/.profile.d/10-xfce.g.sh << EOF
export QT_QPA_PLATFORMTHEME=gtk2
thunar --daemon &
EOF
chmod a+x ~/.profile.d/10-xfce.g.sh

yay -S noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-cica
# edit ~/.config/fontconfig

yay -S fcitx-im fcitx-mozc fcitx-configtool
cat > ~/.profile.d/20-fcitx.g.sh << EOF
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
EOF
chmod a+x ~/.profile.d/20-fcitx.g.sh

yay -S cups
sudo systemctl enable org.cups.cupsd
yay -S foomatic-db-engine foomatic-db foomatic-db-ppds foomatic-db-nonfree foomatic-db-nonfree-ppds
yay -S brother-mfc-l9570cdw

yay -S wireshark-qt
gpasswd -a azon wireshark

yay -S virtualbox virtualbox-host-modules-arch
gpasswd -a azon vboxusers

# ------------------------------------------------------------------------------

# Xfce configulation

# Fcitx configulation

# CUPS configulation

yay -S chromium

yay -S atomic-tweetdeck

yay -S slack-desktop

yay -S zoom

yay -S evince-no-gnome

yay -S drawio-desktop-bin

yay -S gimp

yay -S gnuplot

yay -S tor-browser

yay -S sylpheed
ln -s /usr/share/applications/sylpheed.desktop ~/.config/autostart/
