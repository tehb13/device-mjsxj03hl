#!/bin/bash
#
# Create SD card #2
# for configuring freshly flashed OpenIPC firmware
# on a Xiaomi MJSXJ03HL camera
#
# 2023 Paul Philippov, paul@themactep.com
#

show_help() {
    echo "Usage: $0 -d <SD card device>"
    if [ "$EUID" -eq 0 ]; then
        echo -n "Detected devices: "
        fdisk -x | grep -B1 'SD/MMC' | head -1 | awk '{print $2}' | sed 's/://'
    fi
    exit 2
}

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    show_help
    exit 1
fi

# command line arguments
while getopts d: flag; do
    case ${flag} in
        d) card_device=${OPTARG} ;;
    esac
done

if [ -z "$card_device" ]; then
    show_help
    exit 3
fi

if [ ! -e "$card_device" ]; then
    echo "Device $card_device not found."
    exit 4
fi

while mount | grep $card_device > /dev/null; do
    umount $(mount | grep $card_device | awk '{print $1}')
done

read -p "All existing information on the card will be lost! Proceed? [Y/N]: " ret
if [ "$ret" != "Y" ]; then
    echo "Aborting!"
    exit 99
fi

echo
while [ -z "$wlanssid" ]; do
    read -p "Enter Wireless network SSID: " wlanssid
done
while [ -z "$wlanpass" ]; do
    read -p "Enter Wireless network password: " wlanpass
done
echo

echo "Creating a 64MB FAT32 partition on the SD card."
parted -s ${card_device} mklabel msdos mkpart primary fat32 1MB 64MB && mkfs.vfat ${card_device}1 > /dev/null
if [ $? -ne 0 ]; then
    echo "Cannot create a partition."
    exit 4
fi

sdmount=$(mktemp -d)

echo "Mounting the partition to ${sdmount}."
if ! mkdir -p $sdmount; then
    echo "Cannot create ${sdmount}."
    exit 5
fi

if ! mount ${card_device}1 $sdmount; then
    echo "Cannot mount ${card_device}1 to ${sdmount}."
    exit 6
fi

echo "Copying files."
cp -r $(dirname $0)/files ${sdmount}/

echo "Creating installation script."
echo "#!/bin/sh

fw_setenv osmem 39M
fw_setenv rmem 25M@0x2700000

fw_setenv wlanssid \"${wlanssid}\"
fw_setenv wlanpass \"${wlanpass}\"

cp -rv \$(dirname \$0)/files/* /

echo \"
Configuration is done.

Please remove the SD card from the SD card slot of the camera
then restart the camera by disconnecting the USB power supply
and UART adapter, and reconnecting power back after 5 seconds.
\"
" > ${sdmount}/install.sh

echo "Unmounting the SD partition."
sync
umount $sdmount
eject $card_device

echo "
Card #2 created successfully.
The card is unmounted. You can safely remove it from the slot.

To install extra scripts, the wireless driver and perform basic
configuration, place the card into the camera and execute the
/mnt/mmcblk0p1/install.sh script.
"

exit 0
