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
BACKUPS_DIR="$SCRIPT_DIR/backups"
LOG_FILE="$BACKUPS_DIR/backups.log"


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


printUsage() {
   echo
   cat << EOF

NAME
   Backup.sh

SYNOPSIS
   backup.sh [OPTION...] [FILE...]

DESCRIPTION
   Meant to be used with smaller `job` files (.backup) that contain `objects`
   (files/directories) that need to be backed up. Objects should be full paths.
   Multipls files and directories can be used at the same time, they will be
   processed in order. Directories will be searched for job files,
   non-recursively. The `--jobs` option does not conflict with these other
   job files.

   A `job` file can contain directories and files, and can specify an optional
   `destination` variable to override the default backups directory. For a `job`
   named `job_name.backup`, the default backup directory is
   `$BACKUPS_DIR/job_name`. This directory will contain backups of all
   the objects specified in the `job`, dated but not timestamped like so:
   `2026-01-01_object_file.txt.old`.

OPTIONS
   -c, --config <file.conf>
      Use the specified configuration file to override the script's defaults for
      JOBS, JOB_SUFFIX, BACKUPS_LIMIT, BACKUPS_DIR, and/or LOG_FILE.

   -h, --help
      This help message.
   
   --jobs
      Run all job files in the JOBS directory. Can be used while also specifying
      other job files/directories.

EXAMPLES
   # Run all jobs in the JOBS directory.
   backup.sh --jobs

   # Find jobs in a directory and run them.
   backup.sh jobs_directory

   # Run only the specified jobs.
   backup.sh job_1.backup job_2.backup

   # Run with a user-customized config.
   backup.sh -c "backup.conf" job.backup

   # Lots of options and jobs together.
   backup.sh -c backup.conf --run jobs_directory job_1.backup job_2.backup

EOF
}


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


# $1=file; $2=suffix
hasSuffix() {
   local file="$1"
   local suffix="$2"

   if [ -z "$file" ] || [ -z "$suffix" ]; then return 1; fi

   echo "$file" | grep -q -E "^.*""$suffix""$"
}


# $1=job
hasJobSuffix() { hasSuffix "$1" "$JOB_SUFFIX"; }


# $1=config
hasConfigSuffix(){ hasSuffix "$1" ".conf"; }


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

   [ -z "$path" ] && return 1
   ! variableIsSet JOB_SUFFIX && return 1
   ! hasJobSuffix "$filename" && return 1

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

   [ -z "$path" ] && return 1

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

   if [ ! -f "$job" ]; then
      log "Job doesn't exist: $job" "$jobName" fail
      return 1
   fi

   if ! hasJobSuffix "$job"; then
      log "Not a valid job: $job" "$jobName" fail
      return 1
   fi

   while read line || [ -n "$line" ]; do
      key="${line%%=*}"
      value="${line##*=}"
      
      if [ "${key,,}" = "destination" ]; then
         destination="$value"
      fi
   done < "$job"

   # Use default if none was set in job, if BACKUPS_DIR set.
   if [ -z "$destination" ] && [ -n "$BACKUPS_DIR" ]; then
      destination="$BACKUPS_DIR/$jobName"
   fi

   if [ -z "$destination" ]; then
      log "No destination found and BACKUPS_DIR not set" "$jobName" fail
      return 1
   fi

   echo "$destination"
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
   local -A objects

   if [ ! -f "$job" ]; then
      log "Job file doesn't exist: $job" "$jobName" fail
      return 1
   fi

   if [ -z "$JOB_SUFFIX" ]; then
      log "JOB_SUFFIX not set, can't parse job: $job" "$jobName" fail
      return 1
   fi

   if ! hasJobSuffix "$job"; then
      log "File suffix does not match JOB_SUFFIX: $job" "$jobName" fail
      return 1
   fi

   while read line || [ -n "$line" ]; do
      # Filter any quotes that might exist.
      line="$(echo "$line" | sed "s/\"//g")"

      if [ -e "$line" ]; then
         objects["$line"]=1  # Assigning this way prevents duplicates.
         status=0
      fi
   done < "$job"
   
   if [ $status = 1 ]; then
      log "Job contained no valid objects: $job" "$jobName" fail
      return 1
   fi

   printf "%s\n" "${!objects[@]}"
}


# $1=destination; $2=backup name; $3=job name for logging
#
# Find all backed up objects at a job's destination. Oldest are first.
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
   local backupName=$(getBackupName "$object")
   local datedBackupName="$(date +%F)_$backupName"
   local backupCommand="rsync -a"  # a=archive (AKA copy *all* attributes)

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

   if ! commandIsAvailable "rsync"; then
      backupCommand="cp -ru" # r=recurse; u=update older
   fi

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
   return 0
}


# $1=job file
#
# Process a job file and back up the associated objects within, then clean up
# any extra backups.
backupJob() {
   local job="$1"
   local jobName destination object backupName
   local -a objects

   if [ -z "$job" ]; then
      log "No job passed to backupJob()" "" fail
      return 1
   fi

   if [ ! -f "$job" ]; then
      log "backupJob(): job file doesn't exist: $job" "" fail
      return 1
   fi

   if ! hasJobSuffix "$job"; then
      log "backupJob(): job file has wrong suffix: $job" "" fail
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
      log "Skipping, no destination for: $job" "$jobName" fail
      return 1
   fi

   readarray -t objects < <(getObjects "$job" "$jobName")

   if ! arrayfilled objects; then
      log "No valid objects exist" "$jobName" fail
      return 1
   fi

   for object in "${objects[@]}"; do
      backupObject "$object" "$destination" "$jobName"
      backupName="$(getBackupName "$object")"
      cleanupBackups "$destination" "$backupName" "$jobName"
   done

   log "Finished backup" "$jobName"
   return 0
}


# $1=directory containing jobs
#
# Find job files (.backup) within a directory. Does not recurse into
# subdirectories.
#
# JOB_SUFFIX must be set.
getJobs() {
   local directory="$1"
   local -a jobs
   local job

   if [ -z "$JOB_SUFFIX" ]; then
      log "JOB_SUFFIX not set, can't parse directory: $directory" "" fail
      return 1
   fi

   if [ -z "$directory" ]; then
      error "No directory argument for getJobs()"
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


# $1=files or directories
main() {
   local arg job
   local -a args jobs

   [ $# = 0 ] && printUsage

   args=("$@")
   for arg in "${args[@]}"; do
      
      if [ ! -e "$arg" ]; then
         log "Could not find: $arg" "" fail
         continue
      fi
   done

   for arg in "${args[@]}"; do
      if [ -f "$arg" ]; then
         jobs=("$arg")
      elif [ -d "$arg" ]; then
         readarray -t jobs < <(getJobs "$arg")
      fi

      for job in "${jobs[@]}"; do
         backupJob "$job"
      done
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
         "BACKUPS_DIR")

      for variable in "${VARIABLES[@]}"; do
         [ "$variable" = "$option" ] && return 0
      done

      return 1
   }


   if [ ! -f "$config" ]; then
      error "Couldn't find config file: $config"
      return 1
   fi

   if ! hasConfigSuffix "$config"; then
      error "Config file needs .conf suffix: $config"
      return 1
   fi

   while read line || [ -n "$line" ]; do
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
      -h|--help)
         printUsage
         exit 0
         ;;
      -c|--config)
         readConfig "$2"
         shift 2
         ;;
      --jobs)
         [ -z "$JOBS" ] && error "JOBS not set" && exit 1

         main "$JOBS"
         shift 1
         ;;
      *)
         main "$@"
         exit
         ;;
   esac
done
