#!/bin/bash

# Set flag for whether the space is open or closed (true or false)
isSpaceOpen=$1

# Set configurable variables
source "/opt/uas/Occupancy/ocs.cfg"

set -euo pipefail

###############################################################################
# New Occupancy Service
# Unallocated Space
#   Written by Usako - 2018-07-15
#   filename = ocs_new.sh
#
#  Usage:
#   The php status page executes this script.
#
#   Must have access to /tmp/ to write JPEGs and TXT files
###############################################################################

# log()
# A function to make log messages consistant
log()
{
  echo "[$(date "+%Y-%m-%d %T")]: $*" >> "${OCS_LOGFILE}"
}

# getWallPicture()
# moves camera to preset 'TheWall' and sets flag
# then takes picture and puts it at /tmp/thewall.jpg

getWallPicture ()
{
    log "Call to getWallPicture"
    # curl -s "http://${OCS_AXISCAMERA_IP}/axis-cgi/com/ptz.cgi?gotoserverpresetname=home1&camera=1"
    curl -s "http://${OCS_AXISCAMERA_IP}/axis-cgi/com/ptz.cgi?gotoserverpresetname=TheWall&camera=1"
    #log "0"
    sleep 3
    #log "1"
    curl -s "http://${OCS_AXISCAMERA_IP}/axis-cgi/com/ptz.cgi?camera=1&rzoom=-2500"
    sleep 1
    #log "2"
    curl -s "http://${OCS_AXISCAMERA_IP}/axis-cgi/com/ptz.cgi?camera=1&rzoom=+2500"
    sleep 4
    log "write wall image to temp location"
    wget "http://${OCS_AXISCAMERA_IP}/axis-cgi/jpg/image.cgi" -q -O "${OCS_TMP_WALL}"
    sleep 1
}

###############################################################################
# Website functions
#
# pushStatusToWebsite()
#   moves the /tmp/status file to the websites status file
pushStatusToWebsite ()
{
    log "Call to pushStatusToWebsite"
    ftp -n "${OCS_UAS_URL}" << END_FTP_COMMANDS
        quote USER ${OCS_UAS_USER}
        quote PASS ${OCS_UAS_PASS}
        ascii
        passive
        put ${OCS_TMP_STATUS} ${OCS_UAS_STATUS_FILE}
        quit
END_FTP_COMMANDS
}

# pushWallToWebsite()
#   moves the /tmp/thewall.jpg file to the websites status file
pushWallToWebsite ()
{
    log "Call to pushWallToWebsite"
    stamp=$(date '+%F_%T')
    ftp -n "${OCS_UAS_URL}" << END_FTP_COMMANDS
        quote USER ${OCS_UAS_USER}
        quote PASS ${OCS_UAS_PASS}
        ascii
        passive
        put ${OCS_TMP_WALL} ${OCS_UAS_WALL_FILE}
        put ${OCS_TMP_WALL} ${OCS_UAS_WALL_ARCHIVE_FILEPATH}/${stamp}.jpg
        quit
END_FTP_COMMANDS

    #nc "${OCS_IRC_IP}" "${OCS_IRC_PORT}" \
    #  "!JSON" \
    #  "{\"Service\":${OCS_IRC_SERVICE}, \"Key\":${OCS_IRC_KEY}, \"Data\":\"New Wall Image: http://${OCS_UAS_WALL_ARCHIVE_FILEPATH}/${stamp}.jpg\"}" \
    #  &>/dev/null
}

# openTheSpace()
# Tells the world that we're open by posting to all of our various social media
# and other services
openTheSpace()
{
  # status file
  echo "The space is currently open (Updated: $(date '+%m/%d %H:%M'))" > "${OCS_TMP_STATUS}"

  # website status
  pushStatusToWebsite

  # Tweet (not correct yet)
  python /opt/uas/statustweet/statustweet.py "$(cat "${OCS_TMP_STATUS}") #Unallocated" &>/dev/null

  # IRC
  #curl -X POST 127.0.0.1:9999/ --data '{"Service":"Occupancy","Data":"The space is now open"}'

  #Wall image to website
  getWallPicture
  pushWallToWebsite
}

# closeTheSpace()
# Tells the world that we're closed by posting to all of our various social
# media and other services
closeTheSpace()
{
  #Update flags, IRC, website status file, checkin, logging
  echo "The space is currently closed (Updated: $(date '+%m/%d %H:%M'))" > "${OCS_TMP_STATUS}"
  #website status
  pushStatusToWebsite
  #checkin
  #python "${OCS_CHECKIN_SCRIPT}" "closing"
  # Twitter
  python /opt/uas/statustweet/statustweet.py "$(cat "${OCS_TMP_STATUS}") #Unallocated" &>/dev/null
  # IRC
  #curl -X POST 127.0.0.1:9999/ --data '{"Service":"Occupancy","Data":"The space is now closed"}'
}

# cleanUp()
# Perform any necessary script clean up here like deleting the PID
cleanUp()
{
  log "Caught signal, exiting"
  exit
}

###############################################################################
# main()
# Main logic function
# Checks the status and performs the necessary procedures based on open vs. closed.

main ()
{
    # Capture signals so we clean up the pid file properly.
    trap cleanUp SIGHUP SIGINT SIGTERM

    log "STARTING ocs_new.sh"

    if $isSpaceOpen ; then
      openTheSpace
      log "Space is OPEN"
    else
      closeTheSpace
      log "Space is CLOSED"
    fi
}

###############################################################################
# Script Entry
#   All functions and variables need to be set above these lines
#   (i.e. keep this at the end)

log "starting main"
main

exit 0
