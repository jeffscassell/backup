#!/usr/bin/env bash
# Jeff Cassell
# 2026MAR22

# Backup
#
# Meant to be used with smaller job files (.backup) that contain objects
# (files/directories) that need to be backed up. Objects should be full paths.
#
# Running with "run" option will gather all jobs in the JOBS directory and
# process them. Running with specific job file(s) will only process those
# jobs.
#
# [Examples]
# bash backup.sh run
# backup.sh run
# bash backup.sh sample_1.backup sample_2.backup
#
#
# --- Sample Job File ---
# [jellyfin.backup]
# /server/config
# /server/cache
#
# --- Sample Backup ---
# [backups/jellyfin]
# 2026-03-23_config.old
# 2026-03-23_cache.old


# Configuration
###############

# Source of backup "scripts".
LOG_LOCATION=/f/.backup/programming/bash/backup/backups.log
JOBS="$(cd -- "$(dirname -- "${BASH_SOURCE}")" &> /dev/null && pwd )"
JOB_SUFFIX=.backup
BACKUPS_LIMIT=2
BACKUPS_DESTINATION=/f/.backup/programming/bash/backup/backups


# Program
#########


# $1=message
error() {
   local message="$1"
   echo >&2
   echo "$message" >&2  # To STDERR.
}


# $1=variable to check
variableIsSet() {
   local -n var="$1"
   local literal="$1"

   if [ -z "$var" ]; then
      error "Variable unset: $literal"
      return 1
   fi

   return 0
}


# $1=array
arraysize() {
   local -n array="$1"
   echo ${#array[@]}
}


# $1=array
arrayfilled() {
   local -n array="$1"
   [ -n "$array" ] || return
   [ ${#array[@]} -gt 0 ]
}


# $1=command to check
commandIsAvailable() { command -v "$1" &> /dev/null; }


# $1=message; $2=associated job/process/etc (optional); $3=status (optional)
#
# Requires at least the first argument (a message), with an optional
# association argument and an optional status argument.
# If any argument for status is supplied, the status is overridden to indicate
# an error occurred. Treat it as a boolean for error.
#
# LOG_LOCATION is required to be set.
log() {
   [ -n "$1" ] || return
   variableIsSet LOG_LOCATION || return

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


# $1=job file
#
# Parse the name of a job file to get its name, and perform
# validation. Requires JOB_SUFFIX to be set.
#
# /a/full/path/job.backup -> job
getJobName() {
   local path="$1"  # /a/full/path/job.backup
   local filename="$(basename "$path")"  # job.backup
   local name="$(basename "$filename" "$JOB_SUFFIX")"  # job


   isValidJobFile() {
      echo "$filename" | grep -q -E "^.*""$JOB_SUFFIX""$"
   }


   if ! variableIsSet JOB_SUFFIX; then
      echo
      return 1
   fi

   if ! isValidJobFile "$filename"; then
      echo
      return 1
   fi

   echo "$name"
}


# $1=object path
#
# Parse and return a backup name based on an object path. For files, the
# extension is included. Works with relative and absolute paths.
#
# /a/path/to/file.txt -> file.txt.old
# /a/path/to/directory -> directory.old
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

# $1=job file
#
# Parse a job file for paths and return only valid paths. If any valid paths
# exist a status code of 0 is returned.
getValidObjects() {
   local jobFile="$1"
   local status=1
   local -a objects
   local object
   local jobName="$(getJobName "$jobFile")"

   [ -f "$jobFile" ] || return
   
   readarray -t objects < "$jobFile"

   if ! arrayfilled objects; then
      log "Objects empty" "$jobName" fail
      return $status
   fi

   for object in "${objects[@]}"; do
      
      # Check that the provided file/directory exists.
      if [ ! -e "$object" ]; then
         log "Doesn't exist: $object" "$jobName" fail
      else
         status=0
         echo "$object"
      fi
   done

   return $status
}


# $1=job destination; $2=backup name
#
# Find all backed up objects at a job's destination.
getBackups() {
   local jobDestination="$1"
   local backupName="$2"

   find "$jobDestination" -maxdepth 1 -name "*$backupName"
}


# $1=job destination; $2=backup name; $3=associated job for logging
#
# Requires that BACKUPS_LIMIT be set to an integer.
cleanupBackups() {
   local jobDestination="$1"
   local backupName="$2"
   local jobName="$3"
   local failsafe=0  # In case of an accidental endless loop.
   local oldestBackup
   local -a backups


   # $1=array of backups paths
   backupsWithinLimit() {
      local -n array="$1"
      local numberOfBackups=${#array[@]}

      [ $numberOfBackups -le $BACKUPS_LIMIT ]
   }


   if [ ! -d "$jobDestination" ]; then
      log "Job destination doesn't exist: $jobDestination" "$jobName" fail
      return 1
   fi

   if [ -z "$backupName" ]; then
      log "Backup name not provided" "$jobName" fail
      return 1
   fi

   if ! variableIsSet BACKUPS_LIMIT; then
      log "Variable not set: BACKUPS_LIMIT" "$backupName" fail
      return 1
   fi

   while [ $failsafe -lt 5 ]; do
      (( failsafe++ ))
      readarray -t backups< <(getBackups "$jobDestination" "$backupName")
      backupsWithinLimit backups && break

      local oldestBackup="${backups[0]}"
      rm -rf "$oldestBackup"
      log "Removed extra backup: $oldestBackup" "$jobName"
   done
}


# $1=object; $2=job destination; $3=job name for logging
backupObject() {
   local object="$1"
   local jobDestination="$2"
   local jobName="$3"

   [ -e "$object" ] || return

   local backupCommand="rsync -a"  # a=archive (AKA copy *all* attributes)
   if ! commandIsAvailable "rsync"; then
      backupCommand="cp -ru" # r=recurse; u=update older
   fi

   local backupName=$(getBackupName "$object")
   local datedBackupName="$(date +%F)_$backupName"

   if [ -z "$backupName" ]; then
      log "Couldn't get backup name, skipping" "$jobName" fail
      return 1
   fi

   if [ ! -d "$jobDestination" ]; then
      log "Creating destination directory: $jobDestination" "$jobName"
      mkdir -p "$jobDestination"

      if [ ! -d "$jobDestination" ]; then
         log "Error creating destination: $jobDestination" "$jobName" fail
         return 1
      fi

      log "Created destination directory: $jobDestination" "$jobName"
   fi

   if ! $backupCommand "$object" "${jobDestination}/${datedBackupName}"; then
      log "Failed to backup: $object" "$jobName" fail
      return 1
   fi

   log "Backed up: $object" "$jobName"
   cleanupBackups "$jobDestination" "$backupName" "$jobName"
}


# $1=job file
#
# Process a job file and back up the associated objects within, then clean up
# any extra backups.
backup() {
   local jobFile="$1"
   local jobName jobDestination object
   local -a objects

   log "Starting backup" "$jobName"

   # Subdirectory for storage in the main backups directory.
   jobName="$(getJobName "$jobFile")"
   if [ -z "$jobName" ]; then
      log "Couldn't parse job name: $jobFile" "" fail
      return 1
   fi

   jobDestination="${BACKUPS_DESTINATION}/${jobName}"
   readarray -t objects < <(getValidObjects "$jobFile" "$jobName")

   if ! arrayfilled objects; then
      log "No valid sources exist" "$jobName" fail
      return 1
   fi

   for object in "${objects[@]}"; do
      backupObject "$object" "$jobDestination" "$jobName"
   done

   log "Finished backup" "$jobName"
   return 0
}


# $1=jobs directory (optional)
getJobFiles() {
   local directory="${1-$JOBS}"
   [ -n "$directory" ] || return
   [ -d "$directory" ] || return

   find "$directory" -maxdepth 1 -name "*$JOB_SUFFIX"
}


# $1=backup file(s) (optional)
main() {
   local jobFile
   local -a jobFiles


   # If job file(s) are passed explicitly, prefer those.
   if [ -n "$1" ]; then
      jobFiles=("$@")
      for jobFile in "${jobFiles[@]}"; do
         
         if [ ! -f "$jobFile" ]; then
            log "Could not find file: $jobFile" "" fail
            continue
         fi
      done
   else
      readarray -t jobFiles < <(getJobFiles)
   fi

   for jobFile in "${jobFiles[@]}"; do
      backup "$jobFile"
   done
}


# Run all .backup files found in BACKUPS_SRC directory.
if [ "$1" = "run" ]; then
   main
   exit
fi

# Run specific .backup file(s).
if [ -n "$1" ]; then
   main "$@"
   exit
fi
