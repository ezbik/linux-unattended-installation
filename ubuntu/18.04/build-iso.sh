#!/bin/bash
set -e

# lookup specific binaries
: "${BIN_7Z:=$(type -P 7z)}"
: "${BIN_XORRISO:=$(type -P xorriso)}"
: "${BIN_CPIO:=$(type -P gnucpio || type -P cpio)}"

# get parameters
SSH_PUBLIC_KEY_FILE=${1:-"$HOME/.ssh/id_rsa.pub"}
TARGET_ISO=${2:-"`pwd`/ubuntu-18.04-netboot-amd64-unattended.iso"}

. custom/postinst.var

# check if ssh key exists
if [ ! -f "$SSH_PUBLIC_KEY_FILE" ];
then
    echo "Error: public SSH key $SSH_PUBLIC_KEY_FILE not found!"
    exit 1
fi

# get directories
CURRENT_DIR="`pwd`"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TMP_DOWNLOAD_DIR="`mktemp -d`"
TMP_DISC_DIR="`mktemp -d`"
TMP_INITRD_DIR="`mktemp -d`"

# download and extract netboot iso
SOURCE_ISO_URL="http://$COUNTRY.archive.ubuntu.com/ubuntu/dists/bionic/main/installer-amd64/current/images/netboot/mini.iso"

REQUIRED_SIZE=`curl -I $SOURCE_ISO_URL -Ss  | grep Content-Length: | head -n1 | grep -oP '\d+' `
DETECTED_SIZE=`du -b ./netboot.iso  2>/dev/null | cut -f1`

if [ "$REQUIRED_SIZE" == "$DETECTED_SIZE" ]
then    echo "= considered ISO downloaded ( ./netboot.iso is of size $DETECTED_SIZE)"
else    if curl -o ./netboot.iso -L $SOURCE_ISO_URL
        then    :
        else    rm ./netboot.iso
                exit 2
        fi
fi



#cd "$TMP_DOWNLOAD_DIR"
#wget -4 "$SOURCE_ISO_URL" -O "./netboot.iso"
"$BIN_7Z" x "./netboot.iso" "-o$TMP_DISC_DIR"

# patch boot menu
cd "$TMP_DISC_DIR"
dos2unix "./isolinux.cfg"
patch -p1 -i "$SCRIPT_DIR/custom/boot-menu.patch"

# prepare assets
cd "$TMP_INITRD_DIR"
mkdir "./custom"
cat "$SCRIPT_DIR/custom/preseed.cfg" | sed "
    s#__UBUNTU_HOSTNAME__#$UBUNTU_HOSTNAME#; 
    s#__UBUNTU_USER__#$UBUNTU_USER#; 
    s#__PWHASH__#$PWHASH#;
    s#__COUNTRY__#$COUNTRY#;
    s#__WIFI_NAME__#$WIFI_NAME#;
    s#__WIFI_PASS__#$WIFI_PASS#;
    " > "./preseed.cfg"
cp "$SSH_PUBLIC_KEY_FILE" "./custom/userkey.pub"
cp "$SCRIPT_DIR/custom/ssh-host-keygen.service" "./custom/ssh-host-keygen.service"
cp "$SCRIPT_DIR/custom/postinst2.sh" "$SCRIPT_DIR/custom/postinst.var" "./custom/"

# append assets to initrd image
cd "$TMP_INITRD_DIR"
cat "$TMP_DISC_DIR/initrd.gz" | gzip -d > "./initrd"
echo "./preseed.cfg" | fakeroot "$BIN_CPIO" -o -H newc -A -F "./initrd"
find "./custom" | fakeroot "$BIN_CPIO" -o -H newc -A -F "./initrd"
cat "./initrd" | gzip -9c > "$TMP_DISC_DIR/initrd.gz"

# build iso
cd "$TMP_DISC_DIR"
rm -r '[BOOT]'
"$BIN_XORRISO" -as mkisofs -r -V "ubuntu_1804_netboot_unattended" -J -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -input-charset utf-8 -isohybrid-mbr "$SCRIPT_DIR/custom/isohdpfx.bin" -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat -o "$TARGET_ISO" ./

# go back to initial directory
cd "$CURRENT_DIR"

# delete all temporary directories
rm -r "$TMP_DOWNLOAD_DIR"
rm -r "$TMP_DISC_DIR"
rm -r "$TMP_INITRD_DIR"

# done
echo "Next steps: install system, login via root, adjust the authorized keys, set a root password (if you want to), deploy via ansible (if applicable), enjoy!"
