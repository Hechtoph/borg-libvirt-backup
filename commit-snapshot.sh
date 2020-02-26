#!/bin/bash
#

DOMAIN="$1"

if [ -z "$DOMAIN" ]; then
        echo "Usage: ./vm-backup <domain>"
        exit 1
fi

echo "Commiting Snapshot for $DOMAIN"
#
# Get the list of targets (disks) and the image paths.
#
TARGETS=`virsh domblklist "$DOMAIN" --details | grep file | awk '{print $3}'`
IMAGES=`virsh domblklist "$DOMAIN" --details | grep file | awk '{print $4}'`
#
# Merge changes back.
#
BACKUPIMAGES=`virsh domblklist "$DOMAIN" --details | grep file | awk '{print $4}'`
for t in $TARGETS; do
        virsh blockcommit "$DOMAIN" "$t" --active --pivot >/dev/null
        if [ $? -ne 0 ]; then
                echo "Could not merge changes for disk $t of $DOMAIN. VM may be in invalid state."
                exit 1
        fi
done

#
# Cleanup left over backup images.
#
for t in $BACKUPIMAGES; do
        rm -f "$t"
done
#/kvm/scripts/create_timestamp_file.sh
echo "Snapshot commited"
exit 0