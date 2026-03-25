#!/usr/bin/env bash
# Jeff Cassell
# 2026MAR22

# Contains backup functions.
# Meant to be used with smaller .backup files that contain source
# files/directories to be backed up. Sources should be full paths.


# [jellyfin.backup]
# /server/config
# /server/cache

# [backups/jellyfin]
# 2026-03-23_config.old
# 2026-03-23_cache.old


### Configuration ###
#####################

# Source of backup "scripts".
BACKUPS_SRC=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd )
BACKUPS_LIMIT=2
# DEFAULT_BACKUP_DESTINATION=/rpool/.backup
DEFAULT_BACKUP_DESTINATION=/f/.backup/programming/bash/backup.d/backups
# LOG_LOCATION=/rpool/.backup/backups.log
LOG_LOCATION=/f/.backup/programming/bash/backup.d/backups/backups.log
BACKUP_SUFFIX=.backup


### Program ###
###############

# $1=message; $2=associated job/process/etc (optional); $3=status (optional)
#
# Requires at least the first argument (a message), with an optional
# association argument and an optional status argument.
# If any argument for status is supplied, the status is overridden to indicate
# an error occurred. Treat it as a boolean for error.
#
# The LOG_LOCATION environment variable is required to be set.
log() {
   [ -n "$1" ] || return

   local logDirectory=$(dirname "$LOG_LOCATION")
   if [ ! -d "$logDirectory" ]; then
      echo "Log directory does not exist: $logDirectory" >&2  # To STDERR.
      return 1
   fi

   local    OK="       "
   local ERROR="[ERROR]"

   local timestamp=$(date "+%F %H:%M:%S")
   local message="$1"
   local job="${2:-general}"  # "general" is used if nothing is supplied
   local status="${3:+$ERROR}"  # If anything supplied, $ERROR overrides.
   status="${status:-$OK}"  # If empty ("else" above), $OK variable is used.

   echo "$timestamp $status: ($job) $message" >> "$LOG_LOCATION"
}


# $1=backup job path
#
# Parse the name of a backup file path to get its name, and perform
# validation.
#
# /a/full/path/job.backup -> job
getJobName() {
   local path="$1"  # /a/full/path/job.backup
   local filename="$(basename "$path")"  # job.backup
   local name="$(basename "$filename" "$BACKUP_SUFFIX")"  # job


   isValidBackupFile() {
      echo "$filename" | grep -q -E "^.*""$BACKUP_SUFFIX""$"
   }


   if ! isValidBackupFile; then
      echo ""
      return
   fi

   echo "$name"
}


# $1=path
#
# Parse and return a backup name based on a path. For files, the extension
# is included. Works with relative and absolute paths.
getBackupName() {
   local path="$1"  # /a/full/path.txt
   local fullname="${path##*/}"  # path.txt
   local suffix=".${fullname##*.}"  # txt
   local name=${fullname%.*}  # path

   # If path is a directory or has no suffix.
   if [ "$suffix" = ".$fullname" ]; then
      suffix=""
      name="$fullname"
   fi

   echo "${name}${suffix}.old"
}


# $1=sources array; $2=associated job for logging purposes
#
# Parse an array of source paths and return only valid paths. If any paths exist
# a status code of 0 is returned.
getValidSources() {
   local -n array1="$1"
   local sources=("${array1[@]}")
   local jobName="$2"
   
   # Might not exist on the first run.
   # [ -d "$destination" ] || logFail "Not a directory: $destination"
   if [ ! "${#sources[@]}" -gt 0 ]; then
      log "Sources empty" "$jobName" fail
      return 1
   fi

   for path in "${sources[@]}"; do
      
      # Check that the provided file/directory exists.
      if [ ! -e "$path" ]; then
         log "Doesn't exist: $path" "$jobName" fail
      else
         echo "$path"
      fi
   done

   return 0
}


# $1=destination; $2=backup name; $3=associated job for logging
#
# Requires that BACKUPS_LIMIT be set to an integer.
cleanupBackups() {

   # $1=destination; $2=backup name to search for (file.old)
   findBackups() {
      local destination="$1"
      local backupName="$2"
      find "$destination" -maxdepth 1 -name "*$backupName"
   }


   # $1=array of backups paths
   backupsWithinLimit() {
      local -n array="$1"
      local numberOfBackups=${#array[@]}

      [ $numberOfBackups -le $BACKUPS_LIMIT ]
   }

   local destination="$1"
   local backupName="$2"
   local jobName="$3"
   local failsafe=0  # In case of an accidental endless loop.

   while [ $failsafe -lt 5 ]; do
      (( failsafe++ ))
      local backups=($(findBackups "$destination" "$backupName"))
      backupsWithinLimit backups && break

      local oldestBackup="${backups[0]}"
      rm -rf "$oldestBackup"
      log "Removed extra backup: $oldestBackup" "$jobName"
   done
}


# $1=sources array; $2=destination; $3=associated job for logging purposes
backup() {
   local -n array="$1"
   local sources=("${array[@]}")
   local destination="$2"
   local jobName="$3"

   # $1=command to check
   commandIsAvailable() { command -v "$1" &> /dev/null; }
   
   local backupCommand
   if commandIsAvailable "rsync"; then
      backupCommand="rsync -a"
   else
      backupCommand="cp -r"
   fi

   log "Starting backup" "$jobName"

   for source in "${sources[@]}"; do
      local backupName=$(getBackupName "$source")
      local datedBackupName="$(date +%F)_$backupName"

      if [ -z "$backupName" ]; then
         log "Couldn't get backup name" "$jobName" fail
         continue
      fi

      if [ ! -d "$destination" ]; then
         mkdir -p "$destination"
         log "Creating destination directory: $destination" "$jobName"
      fi

      if ! $backupCommand "$source" "${destination}/${datedBackupName}"; then
         log "Failed to backup: $source" "$jobName" fail
         continue
      fi

      log "Backed up: $source" "$jobName"

      cleanupBackups "$destination" "$backupName" "$jobName"
   done

   log "Finished backup" "$jobName"
}


main() {

   # $1=sources array
   validSourcesExist() {
      local -n array="$1"
      local sources=("${array[@]}")
      [ "${#sources[@]}" -gt 0 ]
   }


   # Parse through backups source directory to find all backup files (*.backup).
   # `*$BACKUP_SUFFIX` is outside "" for expansion to occur.
   for backupFile in "$BACKUPS_SRC/"*$BACKUP_SUFFIX; do

      # Create name for job (directory for storage).
      local jobName="$(getJobName "$backupFile")"
      if [ -z "$jobName" ]; then
         log "Couldn't parse job name" "" fail
         continue
      fi

      # Re-declare baselines in case anything was overwritten in another job.
      local destination="${DEFAULT_BACKUP_DESTINATION}/${jobName}"
      unset sources

      # Read sources from .backup file.
      sources=($(cat "$backupFile"))
      local validSources=($(getValidSources sources "$jobName"))
      if ! validSourcesExist validSources; then
         log "No valid sources exist" "$jobName" fail
         continue  # Continue processing the rest of the backups.
      fi

      backup validSources "$destination" "$jobName"
   done
}


if [ "$1" = "run" ]; then
   main
fi
