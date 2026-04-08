#!/usr/bin/env bash
# Jeff Cassell
# 2026MAR22

# Backup.sh


# Configuration
###############


SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE}")" &> /dev/null && pwd )"
JOBS="$SCRIPT_DIR/jobs"
JOB_SUFFIX=.backup
BACKUPS_LIMIT=2
BACKUPS_DESTINATION="$SCRIPT_DIR/backups"
LOG_FILE="$BACKUPS_DESTINATION/backups.log"


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
   [ -z "$1" ] && echo -1 && return
   echo ${#array[@]}
}


# $1=array
arrayfilled() {
   local -n array="$1"
   [ -n "$1" ] || return
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
# LOG_FILE is required to be set.
log() {
   [ -n "$1" ] || return
   variableIsSet LOG_FILE || return

   local logDirectory=$(dirname "$LOG_FILE")
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

   echo "$timestamp $status: ($job) $message" >> "$LOG_FILE"
}


# $1=job
isValidJob() {
   echo "$1" | grep -q -E "^.*""$JOB_SUFFIX""$"
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

   if ! variableIsSet JOB_SUFFIX; then
      echo
      return 1
   fi

   if ! isValidJob "$filename"; then
      echo
      return 1
   fi

   echo "$name"
}


# $1=object path
#
# Parse an object and return the name it will use for backups. For files, the
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
getDestination() {
   local job="$1"
   local destination key value
   local jobName="$(getJobName "$job")"

   if ! isValidJob "$job"; then
      log "Not a valid job: $job" "$jobName" fail
      echo
      return 1
   fi

   if [ ! -f "$job" ]; then
      log "Job doesn't exist: $job" "$jobName" fail
      echo
      return 1
   fi

   while read line; do
      key="${line%%=*}"
      value="${line##*=}"
      
      if [ "${key,,}" = "destination" ]; then
         
         # Only assign the first value found.
         [ -z "$destination" ] && destination="$value"
      fi
   done < "$job"

   # Use default if none was set in job, if BACKUPS_DESTINATION set.
   [ -z "$destination" ] && [ -n "$BACKUPS_DESTINATION" ] \
      && destination="$BACKUPS_DESTINATION/$jobName"

   if [ -z "$destination" ]; then
      log "No destination found and BACKUPS_DESTINATION not set" "$jobName" fail
      echo
      return 1
   fi

   echo "$destination"
   return 0
}


# $1=job file
#
# Parse a job file for object paths and return only valid objects. If any
# objects are returned a status code of 0 is returned.
#
# JOB_SUFFIX must be set.
getObjects() {
   local job="$1"
   local status=1
   local jobName="$(getJobName "$job")"

   if [ ! -f "$job" ]; then
      log "Job file doesn't exist: $job" "$jobName" fail
      return 1
   fi

   if [ -z "$JOB_SUFFIX" ]; then
      log "JOB_SUFFIX not set, can't parse job: $job" "$jobName" fail
      return 1
   fi

   if ! isValidJob "$job"; then
      log "File suffix does not match JOB_SUFFIX: $job" "$jobName" fail
      return 1
   fi

   while read line; do
      if [ -e "$line" ]; then
         echo "$line"
         status=0
      fi
   done < "$job"
   
   if [ $status = 1 ]; then
      log "Job contained no valid objects: $job" "$jobName" fail
      return $status
   fi

   return $status
}


# $1=destination; $2=backup name; $3=job name for logging
#
# Find all backed up objects at a job's destination.
getBackups() {
   local destination="$1"
   local backupName="$2"
   local jobName="$3"
   local -a backups

   if [ -z "$destination" ]; then
      log "Missing destination argument to getBackups()" "$jobName" fail
      return 1
   fi

   if [ -z "$backupName" ]; then
      log "Missing backup name argument to getBackups()" "$jobName" fail
      return 1
   fi

   if [ ! -d "$destination" ]; then
      log "getBackups() couldn't find directory: $destination" "$jobName" fail
      return 1
   fi

   # Defunct because it orders files unpredictably (sometimes 1-9 then 0, others
   # 0-9, and others still something else entirely).
   # find "$destination" -maxdepth 1 -name "*$backupName"

   nullglobSetting="$(shopt -p nullglob)"
   shopt -s nullglob
   backups=("$destination"/*"$backupName")
   $nullglobSetting
   arrayfilled backups && printf "%s\n" "${backups[@]}"
}


# $1=destination; $2=backup name; $3=associated job for logging
#
# Requires that BACKUPS_LIMIT be set to an integer.
cleanupBackups() {
   local destination="$1"
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


   if [ ! -d "$destination" ]; then
      log "cleanupBackups(): Destination doesn't exist: $destination" \
         "$jobName" fail
      return 1
   fi

   if [ -z "$backupName" ]; then
      log "cleanupBackups(): Backup name not provided" "$jobName" fail
      return 1
   fi

   if ! variableIsSet BACKUPS_LIMIT; then
      log "Variable not set: BACKUPS_LIMIT" "$backupName" fail
      return 1
   fi

   while [ $failsafe -lt 5 ]; do
      (( failsafe++ ))
      readarray -t backups< <(getBackups "$destination" "$backupName" \
         "$jobName")
      backupsWithinLimit backups && return 0

      local oldestBackup="${backups[0]}"
      rm -rf "$oldestBackup"
      log "Removed oldest backup: $oldestBackup" "$jobName"
   done

   return 1
}


# $1=object; $2=destination; $3=job name for logging
backupObject() {
   local object="$1"
   local destination="$2"
   local jobName="$3"

   if [ -z "$object" ]; then
      log "Object argument missing to backupObject()" "$jobName" fail
      return 1
   fi

   if [ -z "$destination" ]; then
      log "Destination argument missing to backupObject()" "$jobName" ""
      return 1
   fi

   if [ ! -e "$object" ]; then
      log "Object doesn't exist for backup: $object" "$jobName" fail
      return 1
   fi

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

   if [ ! -d "$destination" ]; then
      log "Creating destination directory: $destination" "$jobName"
      mkdir -p "$destination"

      if [ ! -d "$destination" ]; then
         log "Error creating destination: $destination" "$jobName" fail
         return 1
      fi

      log "Created destination directory: $destination" "$jobName"
   fi

   if ! $backupCommand "$object" "${destination}/${datedBackupName}"; then
      log "Failed to backup: $datedBackupName" "$jobName" fail
      return 1
   fi

   log "Backed up: $datedBackupName" "$jobName"
   cleanupBackups "$destination" "$backupName" "$jobName"
}


# $1=job file
#
# Process a job file and back up the associated objects within, then clean up
# any extra backups.
backupJob() {
   local job="$1"
   local jobName destination object
   local -a objects

   if [ -z "$job" ]; then
      log "No job passed to backupJob()" "" fail
      return 1
   fi

   if [ ! -f "$job" ]; then
      log "backupJob(): job file doesn't exist: $job" "" fail
      return 1
   fi

   # Used for storage subdirectory (if JOBS directory used) and logging.
   jobName="$(getJobName "$job")"
   if [ -z "$jobName" ]; then
      log "Couldn't parse job name: $job" "" fail
      return 1
   fi

   log "Starting backup" "$jobName"

   destination="$(getDestination "$job")"
   if [ -z "$destination" ]; then
      log "Couldn't parse backup name: $job" "$jobName" fail
      return 1
   fi

   readarray -t objects < <(getObjects "$job" "$jobName")

   if ! arrayfilled objects; then
      log "No valid objects exist" "$jobName" fail
      return 1
   fi

   for object in "${objects[@]}"; do
      backupObject "$object" "$destination" "$jobName"
   done

   log "Finished backup" "$jobName"
   return 0
}


# $1=jobs directory (optional)
#
# Find job files (.backup) within a directory. Does not recurse into
# subdirectories.
#
# JOB_SUFFIX must be set.
getJobs() {
   local directory="${1-$JOBS}"
   local -a jobs
   local job

   if [ -z "$JOB_SUFFIX" ]; then
      log "JOB_SUFFIX not set, can't parse directory: $directory" "" fail
      return 1
   fi

   if [ -z "$directory" ]; then
      error "No directory argument or JOBS variable set for getJobs()"
      return 1
   fi

   if [ ! -d "$directory" ]; then
      error "Argument passed to getJobFiles() is not a directory: $directory"
      return 1
   fi

   readarray -t jobs < <(find "$directory" -maxdepth 1 -type f \
      -name "*$JOB_SUFFIX")
   
   if ! arrayfilled jobs; then
      log "No jobs found in directory: $directory" "" fail
      return 1
   fi

   printf "%s\n" "${jobs[@]}"
   return 0
}


# $1=backup file(s) (optional)
main() {
   local job
   local -a jobs

   # If job file(s) are passed explicitly, prefer those.
   if [ -n "$1" ]; then
      jobs=("$@")
      for job in "${jobs[@]}"; do
         
         if [ ! -f "$job" ]; then
            log "Could not find file: $job" "" fail
            continue
         fi
      done
   else
      readarray -t jobs < <(getJobs)
   fi

   for job in "${jobs[@]}"; do
      backupJob "$job"
   done
}


readConfig() {
   local config="$1"
   local key value trimmed line
   

   # $1=option
   isConfigOption() {
      local option="$1"
      local variable
      local VARIABLES=("LOG_FILE" "JOBS" "JOB_SUFFIX" "BACKUPS_LIMIT" \
         "BACKUPS_DESTINATION")

      for variable in "${VARIABLES[@]}"; do
         [ "$variable" = "$option" ] && return 0
      done

      return 1
   }


   if [ ! -f "$config" ]; then
      error "Couldn't find config: $config"
      return 1
   fi

   while read line; do
      trimmed="${line%%#*}"  # Remove comments.

      # Remove leading/trailing whitespace.
      trimmed="$(echo "$trimmed" | sed "s/^[[:space:]]*//; s/[[:space:]]*$//")"

      [ -z "$trimmed" ] && continue

      key="${trimmed%%=*}"
      value="${trimmed##*=}"
      value="$(echo "$value" | sed "s/\"//g")"  # Remove any quotes.
      
      [ -z "$value" ] && continue

      if isConfigOption "$key"; then
         eval $key="\$value"
         # eval "echo processed $key: \$$key"  # For debugging.
      fi
   done < "$config"
}


while [ $# -gt 0 ]; do
   case "$1" in
      -c)
         readConfig "$2"
         shift 2
         ;;
      run)
         main
         exit
         ;;
      *)
         main "$@"
         exit
         ;;
   esac
done

# # Run all .backup files found in BACKUPS_SRC directory.
# if [ "$1" = "run" ]; then
#    main
#    exit
# fi

# # Run specific .backup file(s).
# if [ -n "$1" ]; then
#    main "$@"
#    exit
# fi
