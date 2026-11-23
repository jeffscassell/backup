#!/usr/bin/env bash
# Jeff Cassell
# 2026MAR22

# Backup.sh


###############
# Configuration
###############

# =======
# Helpers
# =======

# $1=file path
pathIsRelative(){ [ "${1:0:3}" = "../" ] || [ "${1:0:2}" = "./" ]; }

# $1=value; $2=array
insidearray() {
   if [ -z "$1" ]; then
      echo "insidearray: missing value" >&2
      return 1
   fi

   if [ -z "$2" ]; then
      echo "insidearray: missing array" >&2
      return 1
   fi

   local value="$1"
   local -n _insideArray="$2"

   for element in "${_insideArray[@]}"; do
      [ "$element" = "$value" ] && return 0
   done

   return 1
}


# $1=array
#
# "Returns" to STDOUT; -1 if no array name is passed.
arraysize() {
   [ -z "$1" ] && echo -1 && return
   local -n _sizeArray="$1"
   echo ${#_sizeArray[@]}
}


# $1=array
#
# "Returns" to STDOUT. Does not print anything if array is empty.
returnarray() {
   [ -n "$1" ] || return
   local -n _returnArray=$1

   # Don't return an empty array.
   [ "${#_returnArray[@]}" -gt 0 ] || return
   printf "%s\n" "${_returnArray[@]}"
}


# $1=array
arrayfilled() {
   [ -n "$1" ] || return
   local -n _filledArray="$1"
   [ ${#_filledArray[@]} -gt 0 ]
}


# $1=command to check
commandIsAvailable() { command -v "$1" &> /dev/null; }


# $1=file; $2=suffix
hasSuffix() {
   [ -n "$1" ] && [ -n "$2" ] || return

   local file="$1"
   local suffix="$2"
   echo "$file" | grep -q -E "^.*${suffix}$"
}


# $1=relative path; $2=job
getAbsolute() {
   [ -n "$1" ] && [ -n "$2" ] || return

   local relative="$1"
   local job="$2"
   local resolved

   jobDirectory="$(cd -- "$(dirname -- "$job")" &> /dev/null && pwd)"

   # Resolve any dots (../..).
   resolved="$(readlink -f "$jobDirectory/$relative")"

   echo "$resolved"
}

# =======
# Program
# =======

printUsage() {
   echo
   cat << EOF
NAME
   Backup.sh

SYNOPSIS
   backup.sh [OPTION...] [FILE...]

DESCRIPTION
   Meant to be used with smaller [job] files (.backup) that contain [objects]
   (files/directories) that need to be backed up. Objects should be full paths.
   Multipls files and directories can be used at the same time, they will be
   processed in order. Directories will be searched for job files,
   non-recursively. The [--jobs] option does not conflict with these other
   job files.

   A [job] file can contain directories and files, and can specify an optional
   [destination] variable to override the default backups directory. For a [job]
   named [job_name.backup], the default backup directory is
   [\$BACKUPS_DIR/job_name]. This directory will contain backups of all
   the objects specified in the [job], dated but not timestamped like so:
   [2026-01-01_object_file.txt.old].

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
# If LOG_FILE isn't set, it will still send messages to STDOUT/STDERR, but will
# return a status code of 1 (error).
log() {
   [ -n "$1" ] || return

   local    OK="       "
   local ERROR="[ERROR]"

   local timestamp="$(date "+%F %H:%M:%S")"
   local message="$1"
   local job="${2:-general}"  # "general" is used if nothing is supplied
   local status="${3:+$ERROR}"  # If anything supplied, $ERROR overrides.
   status="${status:-$OK}"  # If empty ("else" above), $OK variable is used.
   local entry="$timestamp $status: ($job) $message"

   if [ "$status" = "$ERROR" ]; then
      echo "$entry" >&2
   else
      echo "$entry"
   fi

   if [ -z "$LOG_FILE" ]; then
      echo "LOG_FILE not set" >&2
      return 1
   fi

   local logDirectory="$(dirname "$LOG_FILE")"

   if [ ! -d "$logDirectory" ]; then
      echo "Log directory does not exist: $logDirectory" >&2
      return 1
   fi

   echo "$entry" >> "$LOG_FILE"
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
   [ -n "$1" ] || return

   local path="$1"  # /a/full/path/job.backup
   local filename="$(basename "$path")"  # job.backup
   local name="$(basename "$filename" "$JOB_SUFFIX")"  # job

   [ -n "$JOB_SUFFIX" ] || return
   hasJobSuffix "$filename" || return

   echo "$name"
}


# $1=object path
#
# "Returns" to STDOUT. Parse an object and return the name it will use for
# backups. For files, the extension is included. Works with relative and
# absolute paths.
#
# /a/path/to/file.txt -> file.txt.old
# /a/path/to/directory -> directory.old
getBackupName() {
   [ -n "$1" ] || return

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
getBackupsLimit(){
   [ -n "$1" ] || return

   local file="$1"
   local limit value
   local jobName="$(getJobName "$file")"

   # Extract only the first line containing "destination=" (case-insensitive).
   # Remove any quotes and leading/trailing whitespace.
   value="$(grep -i "backups_limit=" "$file" | sed \
      's/backups_limit=//; s/"//g; s/^ *//; s/ *$//; q')"

   # First, try to assign value from job file, if present.
   [ -n "$value" ] && limit="$value"

   # Second, try to assign the default (BACKUPS_DIR).
   if [ -z "$limit" ] && [ -n "$BACKUPS_LIMIT" ]; then
      limit="$BACKUPS_LIMIT"
   fi

   # If neither of those work, give up.
   if [ -z "$limit" ]; then
      log "Backups limit could not be determined" "$jobName" fail
      return 1
   fi

   echo "$limit"
}


# $1=job file
getDestination() {
   [ -n "$1" ] || return

   local file="$1"
   local destination value
   local jobName="$(getJobName "$file")"

   # Extract only the first line containing "destination=" (case-insensitive).
   # Remove any quotes and leading/trailing whitespace.
   value="$(grep -i "destination=" "$file" | sed \
      's/destination=//; s/"//g; s/^ *//; s/ *$//; q')"

   if pathIsRelative "$value"; then
      local resolved="$(getAbsolute "$value" "$file")"

      if [ -z "$resolved" ]; then
         log "Relative destination's parent does not exist: $value" \
            "$jobName" fail
         return 1
      fi

      value="$resolved"
   fi

   # First, try to assign value from job file (if it exists).
   [ -n "$value" ] && destination="$value"

   # Second, try to assign the default (BACKUPS_DIR).
   if [ -z "$destination" ] && [ -n "$BACKUPS_DIR" ]; then
      destination="$BACKUPS_DIR/$jobName"
   fi

   # If neither of those work, give up.
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
   [ -n "$1" ] || return

   local file="$1"
   local status=1
   local jobName="$(getJobName "$file")"
   local -A objects  # Associative array is used to prevent duplicates.

   while read -r line; do

      [ -n "$line" ] || continue

      line="${line%%#*}"  # Remove comments.
      [ -n "$line" ] || continue  # Discard empty lines.
      (echo "$line" | grep -q "=") && continue  # Discard lines with "=".

      # Filter any quotes that might exist.
      line="$(echo "$line" | sed "s/\"//g")"

      # Convert relative paths to absolute (relative to the job's directory).
      if pathIsRelative "$line"; then
         line="$(getAbsolute "$line" "$file")"
      fi

      if [ -e "$line" ]; then
         # Use the line as the key to assign the arbitrary value of 1, and later
         # return only the keys. Assigning this way prevents duplicates.
         objects["$line"]=1
         status=0
      fi
   done < "$file"

   [ $status = 0 ] || return
   printf "%s\n" "${!objects[@]}"
}


# $1=DESTINATION; $2=backup NAME; $3=job name for logging
#
# Find all backup objects matching NAME at a given DESTINATION. Oldest are
# first.
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
   returnarray backups
}


# $1=destination; $2=backup name; $3=job name for logging
#
# Counts the number of backups in a destination and determines if there are too
# many. Requires BACKUPS_LIMIT to be set.
backupsWithinLimit() {
   [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] || return

   local limit=$1
   local destination="$2"
   local backupName="$3"
   local jobName="$4"
   local -a backups

   if [ -z "$destination" ] || [ -z "$backupName" ]; then
      return 1
   fi

   readarray -t backups < <(getBackups "$destination" "$backupName" \
      "$jobName")

   if [ ${#backups[@]} -le $limit ]; then
      log "Backups within limit: ${#backups[@]}/${limit}" "$jobName"
      return 0
   else
      log "Backups exceed limit: ${#backups[@]}/${limit}" "$jobName"
      return 1
   fi
}


# $1=destination; $2=backup name; $3=associated job for logging
#
# Removes the oldest backup instance in a destination. Does not perform any
# evaluation on BACKUPS_LIMIT itself, instead it is assumed that it's done prior
# to calling this function.
cleanupBackups() {
   local destination="$1"
   local backupName="$2"
   local jobName="$3"
   local oldestBackup
   local -a backups

   if [ ! -d "$destination" ]; then
      log "cleanupBackups(): Destination doesn't exist: $destination" \
         "$jobName" fail
      return 1
   fi

   if [ -z "$backupName" ]; then
      log "cleanupBackups(): Backup name not provided" "$jobName" fail
      return 1
   fi

   readarray -t backups< <(getBackups "$destination" "$backupName" \
      "$jobName")

   if ! arrayfilled backups; then
      log "No backups could be found for removal" "$jobName"
      return 1
   fi

   oldestBackup="${backups[0]}"
   log "Removing oldest backup: $oldestBackup" "$jobName"

   if rm -rf "$oldestBackup"; then
      log "Remove: OK" "$jobName"
      return 0
   else
      log "Remove: fail" "$jobName" fail
      return 1
   fi
}


# $1=object; $2=destination; $3=job name for logging
backupObject() {
   if [ -z "$1" ]; then
      log "Object argument missing to backupObject()" "$jobName" fail
      return 1
   fi

   if [ -z "$2" ]; then
      log "Destination argument missing to backupObject()" "$jobName" ""
      return 1
   fi

   local object="$1"
   local destination="$2"
   local jobName="$3"
   local backupName=$(getBackupName "$object")
   local datedBackupName="$(date +%F)_$backupName"
   local backupCommand="rsync -a"  # a=archive (AKA copy *all* attributes)

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

   log "Backing up: $datedBackupName" "$jobName"
   $backupCommand "$object" "${destination}/${datedBackupName}" || return
}


# $1=job file
#
# Process a job file and back up the associated objects within, then clean up
# any extra backups.
backupJob() {
   if [ -z "$1" ]; then
      log "No job passed to backupJob()" "" fail
      return 1
   fi

   local file="$1"
   local jobName destination backupName
   local -a objects

   # Used for job's backup location (if JOBS directory used) and logging.
   jobName="$(getJobName "$file")"
   log "Processing job: $file" "$jobName"
   destination="$(getDestination "$file")"
   log "Destination selected: $destination" "$jobName"
   backupsLimit=$(getBackupsLimit "$file")
   log "Backups limit: $backupsLimit" "$jobName"
   readarray -t objects < <(getObjects "$file" "$jobName")

   local object
   for object in "${objects[@]}"; do

      log "Processing object: $object" "$jobName"

      if backupObject "$object" "$destination" "$jobName"; then
         log "Backup: OK" "$jobName"
      else
         log "Backup: fail" "$jobName" fail
         continue
      fi

      backupName="$(getBackupName "$object")"

      while ! backupsWithinLimit $backupsLimit "$destination" "$backupName" \
         "$jobName"; do
         cleanupBackups "$destination" "$backupName" "$jobName" || return
      done
   done
}


# $1=directory containing jobs
#
# Find job files (.backup by default) within a directory. Does not recurse into
# subdirectories.
#
# JOB_SUFFIX must be set.
getJobs() {
   if [ -z "$1" ]; then
      log "No directory argument for getJobs()" "" fail
      return 1
   fi

   local directory="$1"
   local -a jobs

   if [ -z "$JOB_SUFFIX" ]; then
      log "JOB_SUFFIX not set, can't parse directory" "" fail
      return 1
   fi

   if [ ! -d "$directory" ]; then
      log "Not a directory" "" fail
      return 1
   fi

   readarray -t jobs < <(find "$directory" -maxdepth 1 -type f \
      -name "*$JOB_SUFFIX")

   returnarray jobs
}


# $1=job file
validateJobFile(){
   local file="$1"

   if [ ! -f "$file" ]; then
      log "Job file not found: $file" "" fail
      return 1
   fi

   if ! hasJobSuffix "$file"; then
      log "File has wrong suffix: $file" "" fail
      return 1
   fi

   # Used for job's backup location (if JOBS directory used) and logging.
   local jobName="$(getJobName "$file")"
   if [ -z "$jobName" ]; then
      log "Couldn't parse job name" "" fail
      return 1
   fi

   local destination="$(getDestination "$file")"
   if [ -z "$destination" ]; then
      log "No destination selected" "$jobName" fail
      return 1
   fi

   local limit=$(getBackupsLimit "$file")
   if [ -z "$limit" ]; then
      log "No backups_limit could be set" "$jobName" fail
      return 1
   fi

   readarray -t objects < <(getObjects "$file" "$jobName")

   if ! arrayfilled objects; then
      log "Job has no valid objects" "$jobName" fail
      return 1
   fi
}


# $1=files or directories
main() {
   if [ ! $# -gt 0 ]; then
      printUsage
      exit 1
   fi

   local paths=("$@")
   local job validJob jobName
   local -a jobs validJobs

   local path
   for path in "${paths[@]}"; do

      # Validate jobs.
      if [ -f "$path" ]; then
         if validateJobFile "$path"; then
            validJobs=("$path")
         else
            log "Invalid job file: $path" "" fail
            continue
         fi
      elif [ -d "$path" ]; then
         log "Finding jobs in: $path"
         readarray -t jobs < <(getJobs "$path")

         if ! arrayfilled jobs; then
            log "No jobs found in $path" "" fail
            continue
         fi

         for job in "${jobs[@]}"; do
            if validateJobFile "$job"; then
               validJobs+=("$job")
            else
               log "Invalid job file: $job" "" fail
               continue
            fi
         done
      else
         log "Could not find: $path" "" fail
         continue
      fi

      # Backup valid jobs.
      for validJob in "${validJobs[@]}"; do

         jobName="$(getJobName "$validJob")"
         log "Starting job: $validJob" "$jobName"

         if backupJob "$validJob"; then
            log "Finished job" "$jobName"
         else
            log "Error processing job" "$jobName" fail
         fi

      done
   done
}


readConfig() {
   local config="$1"
   local key value


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
      log "Couldn't find config file: $config" "" fail
      return 1
   fi

   if ! hasConfigSuffix "$config"; then
      log "Config file needs .conf suffix: $config" "" fail
      return 1
   fi

   local line
   while read -r line; do

      # Discard empty lines.
      [ -n "$line" ] || continue

      # Discard lines that don't have "=" in it.
      (echo "$line" | grep -q "=") || continue

      # Remove comments.
      line="$(echo "$line" | sed 's/#.*//')"

      key="$(echo "$line" | sed -E 's/^(.*)=.*/\1/')"

      # Remove quotes and leading/trailing whitepsace.
      value="$(echo "$line" | sed -E \
         's/.*=(.*)/\1/; s/"//g; s/^ *//; s/ *$//')"

      if isConfigOption "$key"; then
         eval $key="\$value"
         log "Loaded variable from config: $key=$value"
      fi
   done < "$config"
}




processOptions(){

   SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE}")" &> /dev/null && pwd )"
   JOBS="$SCRIPT_DIR/jobs"
   JOB_SUFFIX=.backup
   BACKUPS_LIMIT=2
   BACKUPS_DIR="$SCRIPT_DIR/backups"
   LOG_FILE="$BACKUPS_DIR/backups.log"

   # Load config first, so --jobs coming before won't cause problems.
   ARGS=("$@")
   for i in "${!ARGS[@]}"; do
      if [ "${ARGS[i]}" = "-c" ] || [ "${ARGS[i]}" = "--config" ]; then
         if readConfig "${ARGS[$(( i + 1 ))]}"; then
            log "Loaded config: ${ARGS[$(( i + 1 ))]}"
         else
            log "Error loading config: ${ARGS[$(( i + 1 ))]}" "" fail
         fi
      fi
   done

   while [ $# -gt 0 ]; do
      case "$1" in
         -h|--help)
            printUsage
            exit 0
            ;;
         -c|--config)
            # Config is processed as priority above, just discard here.
            shift 2
            ;;
         --jobs)
            [ -z "$JOBS" ] && log "JOBS not set" "" fail && exit 1

            main "$JOBS"
            shift 1
            ;;
         -t|--test)
            [ -n "$2" ] || printUsage
            validateJobFile "$2"
            exit
            ;;
         *)
            main "$@"
            exit
            ;;
      esac
   done
}


processOptions "$@"

