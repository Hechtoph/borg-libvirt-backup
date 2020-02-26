#!/bin/bash
# BorgBackup Libvirt Backup Script V1.0

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 configfile (located in folder ./config)" >&2
  exit 1
fi

##INPUT
JOBNAME=$1
##INPUT
WORKINGDIRECTORY=$(dirname "$BASH_SOURCE")
CONFIGFILE="$WORKINGDIRECTORY/config/$JOBNAME"
TIMESTAMP="$(date +"%Y-%m-%d-%H-%M-%S")"

#QUIT IF CONFIGFILE DOES NOT EXIST
if [ ! -f $CONFIGFILE ]
then
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):ERROR: Configfile not found, aborting."
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------UNSUCCESSFULLY FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP----------"
        exit 2
fi

chmod +x $CONFIGFILE
. $CONFIGFILE
export BORG_PASSPHRASE=$BORG_PASSPHRASE

HOST=$(hostname)
CREATESNAP="$WORKINGDIRECTORY/create-snapshot.sh"
COMMITSNAP="$WORKINGDIRECTORY/commit-snapshot.sh"


#Dateien
TIMESTAMPFILE="$WORKINGDIRECTORY/timestamps/$JOBNAME"
LOCKFILE="$WORKINGDIRECTORY/locks/$JOBNAME"
LOGFILE="$WORKINGDIRECTORY/logs/$JOBNAME-$TIMESTAMP"
XMLDUMPFILE="$WORKINGDIRECTORY/xml-dumps/$DOMAIN.xml"


#Ordnerstruktur erstellen, falls nicht existent
DIRTIMESTAMPFILE="$WORKINGDIRECTORY/timestamps/"
DIRLOCKFILE="$WORKINGDIRECTORY/locks/"
DIRLOGFILE="$WORKINGDIRECTORY/logs/"
DIRXMLDUMPS="$WORKINGDIRECTORY/xml-dumps/"
mkdir -p $DIRTIMESTAMPFILE $DIRLOCKFILE $DIRLOGFILE $DIRXMLDUMPS

#Logfile erstellen
touch $LOGFILE

echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------STARTING BACKUP OF $HOST $JOBNAME ON $TIMESTAMP----------" | tee -a $LOGFILE

##QUIT IF LOCKFILE EXISTS
if [ -f $LOCKFILE ]
then
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):ERROR: Lockfile found, aborting." | tee -a $LOGFILE
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------UNSUCCESSFULLY FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP----------" | tee -a $LOGFILE
        sendemail -f $MAILFROM -t $MAILTO -u "ERROR: BORGBACKUP $HOST $JOBNAME ON $TIMESTAMP" -m ":(" -s $MAILHOST -xu $MAILUSER -xp $MAILPASSWORD -o tls=yes -a $LOGFILE
        exit 3
fi

##CREATE LOCKFILE
touch $LOCKFILE


##CREATE SNAPSHOT
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----CREATING SNAPSHOT----" | tee -a $LOGFILE
$CREATESNAP $DOMAIN | tee -a $LOGFILE
if [ $PIPESTATUS -ne 0 ]
then
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):ERROR: Snapshot could not be created, aborting."  | tee -a $LOGFILE
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------UNSUCCESSFULLY FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP----------" | tee -a $LOGFILE
        sendemail -f $MAILFROM -t $MAILTO -u "ERROR: BORGBACKUP $HOST $JOBNAME ON $TIMESTAMP" -m ":(" -s $MAILHOST -xu $MAILUSER -xp $MAILPASSWORD -o tls=yes -a $LOGFILE
        rm $LOCKFILE
        exit 4
fi
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----FINISHED CREATING SNAPSHOT----" | tee -a $LOGFILE

##CREATE XML DUMP
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----CREATING XML DUMP----" | tee -a $LOGFILE
virsh dumpxml $DOMAIN > $XMLDUMPFILE | tee -a $LOGFILE
if [ $PIPESTATUS -ne 0 ]
then
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):ERROR: XML DUMP could not be created, aborting."  | tee -a $LOGFILE
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------UNSUCCESSFULLY FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP----------" | tee -a $LOGFILE
        sendemail -f $MAILFROM -t $MAILTO -u "ERROR: BORGBACKUP $HOST $JOBNAME ON $TIMESTAMP" -m ":(" -s $MAILHOST -xu $MAILUSER -xp $MAILPASSWORD -o tls=yes -a $LOGFILE
        rm $LOCKFILE
        exit 5
fi
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----FINISHED CREATING XML DUMP----" | tee -a $LOGFILE

##DO BACKUP
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----RUNNING BACKUP JOB----" | tee -a $LOGFILE
$BORGLOCATION create --info --compression $COMPRESSION --stats $REPOSITORY::$JOBNAME-$TIMESTAMP $XMLDUMPFILE $DISKS 2>&1 >/dev/null | tee -a $LOGFILE
BORGERRORLEVEL=$PIPESTATUS
if [ $BORGERRORLEVEL -gt 1 ]
then
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):ERROR: Borg returned error $BORGERRORLEVEL, aborting." | tee -a $LOGFILE
        sudo lvremove -f $SNAPSHOTPATH | tee -a $LOGFILE
        echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------UNSUCCESSFULLY FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP----------" | tee -a $LOGFILE
        sendemail -f $MAILFROM -t $MAILTO -u "ERROR: BORGBACKUP $HOST $JOBNAME ON $TIMESTAMP" -m ":(" -s $MAILHOST -xu $MAILUSER -xp $MAILPASSWORD -o tls=yes -a $LOGFILE
        rm $LOCKFILE
        exit 6
fi
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----FINISHED BACKUP JOB WITH RETURN CODE $ERRORLEVEL----" | tee -a $LOGFILE

##COMMIT SNAPSHOT
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----COMMITING SNAPSHOT----" | tee -a $LOGFILE
$COMMITSNAP $DOMAIN | tee -a $LOGFILE
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----FINISHED COMMITING SNAPSHOT----" | tee -a $LOGFILE

##PRUNE
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----PRUNING BORG REPO----" | tee -a $LOGFILE
$BORGLOCATION prune --force -s -H $KEEPHOURS -d $KEEPDAYS -w $KEEPWEEKS -m $KEEPMONTHS --keep-last $KEEPLAST -P $JOBNAME $REPOSITORY 2>&1 >/dev/null | tee -a $LOGFILE
echo "$(date +"%Y-%m-%d-%H-%M-%S"):----FINISHED PRUNING BORG REPO----" | tee -a $LOGFILE

##FINISH
if [ $BORGERRORLEVEL -gt 0 ]
then
	echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP WITH WARNINGS----------" | tee -a $LOGFILE
	sendemail -f $MAILFROM -t $MAILTO -u "WARNING: BORGBACKUP $HOST $JOBNAME ON $TIMESTAMP" -m ":/" -s $MAILHOST -xu $MAILUSER -xp $MAILPASSWORD -o tls=yes -a $LOGFILE
fi
if [ $BORGERRORLEVEL -eq 0 ]
then
	echo "$(date +"%Y-%m-%d-%H-%M-%S"):----------SUCCESSFULLY FINISHED BACKUP OF $HOST $JOBNAME ON $TIMESTAMP WITHOUT ERROR----------" | tee -a $LOGFILE
	sendemail -f $MAILFROM -t $MAILTO -u "SUCCESS: BORGBACKUP $HOST $JOBNAME ON $TIMESTAMP" -m ":)" -s $MAILHOST -xu $MAILUSER -xp $MAILPASSWORD -o tls=yes -a $LOGFILE
fi
rm $TIMESTAMPFILE
touch $TIMESTAMPFILE
rm $LOCKFILE
exit 0