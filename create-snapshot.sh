#!/bin/bash
#

DOMAIN="$1"

if [ -z "$DOMAIN" ]; then
        echo "Usage: ./vm-backup <domain>"
        exit 1
fi

echo "Creating Snapshot for $DOMAIN"
#
# Get the list of targets (disks) and the image paths.
#
TARGETS=`virsh domblklist "$DOMAIN" --details | grep file | awk '{print $3}'`
IMAGES=`virsh domblklist "$DOMAIN" --details | grep file | awk '{print $4}'`

#
# Create the snapshot.
#
DISKSPEC=""
for t in $TARGETS; do
        DISKSPEC="$DISKSPEC --diskspec $t,snapshot=external"
done
virsh snapshot-create-as --domain "$DOMAIN" --name backup --no-metadata \
                --atomic --disk-only $DISKSPEC >/dev/null
if [ $? -ne 0 ]; then
        echo "Failed to create snapshot for $DOMAIN"
        exit 1
fi


echo "Snapshot created for $DOMAIN"
exit 0