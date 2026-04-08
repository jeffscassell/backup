. "/f/.backup/programming/bash/backup/backup.sh"


# Configuration
###############

# Testing config.
RESOURCES="/f/.backup/programming/bash/backup/tests/_resources"

# Module config.
LOG_FILE=  # Disable logging.


# Tests
#######

test_log() {
   local LOG_FILE="$RESOURCES/log/backups.log"
   
   [ ! -f "$LOG_FILE" ] || rm "$LOG_FILE"
   assert ! -e "$LOG_FILE"

   assert ! log
   assert log "pass message 1" "assert_test"

   assert log "error message" "assert_test" fail
   assert -n "$(tail -1 "$LOG_FILE" | grep "[ERROR]")"

   [ -f "$LOG_FILE" ] && rm "$LOG_FILE"
   LOG_FILE=""
   assert ! log "fail message 1" "assert_test"
}


test_getJobName() {
   assert "$(getJobName /a/full/path/test.backup)" = test
   assert "$(getJobName something.backup)" = something
   assert -z "$(getJobName something.else)"

   local JOB_SUFFIX=".else"
   assert "$(getJobName something.else)" = something

   local JOB_SUFFIX=
   assert -z "$(getJobName something)"
}


test_getBackupName() {
   assert "$(getBackupName /a/path/file.txt)" = file.txt.old
   assert "$(getBackupName /a/path/a.longer.file.txt)" = a.longer.file.txt.old
   assert "$(getBackupName file.txt)" = file.txt.old
   assert "$(getBackupName /a/path/directory)" = directory.old
   assert "$(getBackupName directory)" = directory.old
}


test_getObjects() {
   local -a objects
   local job
   local directory="$RESOURCES/get_objects"
   
   # Job contains a space and has a single file with a space.
   job="$directory/single space.backup"
   readarray -t objects < <(getObjects "$job")
   assert $(arraysize objects) = 1
   assert getObjects "$job"

   # Object has quotes.
   job="$directory/quotes.backup"
   readarray -t objects < <(getObjects "$job")
   assert $(arraysize objects) = 1
   assert getObjects "$job"

   # Job contains multiple real files and directories.
   job="$directory/multiple.backup"
   readarray -t objects < <(getObjects "$job")
   assert $(arraysize objects) = 4
   assert getObjects "$job"

   # Duplicate objects: return only unique objects.
   job="$directory/duplicates.backup"
   readarray -t objects < <(getObjects "$job")
   assert $(arraysize objects) = 1
   assert getObjects "$job"

   # Job specifies a destination: return only objects.
   job="$directory/complex.backup"
   readarray -t objects < <(getObjects "$job")
   assert $(arraysize objects) = 3
   assert getObjects "$job"

   # Job contains real and fake objects: return only real ones.
   job="$directory/mixed.backup"
   readarray -t objects < <(getObjects "$job")
   assert $(arraysize objects) = 2
   assert getObjects "$job"

   # Job contains only fake objects: return nothing.
   job="$directory/fake.backup"
   readarray -t objects < <(getObjects "$job")
   assert $(arraysize objects) = 0
   assert ! getObjects "$job"

   # Job contains nothing: return nothing.
   job="$directory/empty.backup"
   readarray -t objects < <(getObjects "$job")
   assert $(arraysize objects) = 0
   assert ! getObjects "$job"

   # Job doesn't exist: return nothing.
   job="$directory/nonexistent.backup"
   readarray -t objects < <(getObjects "$job")
   assert $(arraysize objects) = 0
   assert ! getObjects "$job"

   # JOB_SUFFIX is wrong: return nothing.
   job="$directory/wrong.suffix"
   readarray -t objects < <(getObjects "$job")
   assert $(arraysize objects) = 0
   assert ! getObjects "$job"

   # JOB_SUFFIX not set: return nothing.
   local JOB_SUFFIX=
   job="$directory/single space.backup"
   readarray -t objects < <(getObjects "$job")
   assert $(arraysize objects) = 0
   assert ! getObjects "$job"
}


test_getJobs() {
   local -a jobs
   local directory

   # Directory contains no jobs.
   directory="$RESOURCES/_backup_destination"
   readarray -t jobs < <(getJobs "$directory")
   assert ! getJobs "$directory"
   assert $(arraysize jobs) = 0
   
   # Specified directory doesn't exist.
   directory="/a/directory"
   readarray -t jobs < <(getJobs "$directory")
   assert ! getJobs "$directory"
   assert $(arraysize jobs) = 0

   # Normal functioning.
   directory="$RESOURCES/get_jobs"
   readarray -t jobs < <(getJobs "$directory")
   assert getJobs "$directory"
   assert $(arraysize jobs) = 3

   # Job suffix is changed from default .backup.
   local JOB_SUFFIX=.else
   readarray -t jobs < <(getJobs "$directory")
   assert getJobs "$directory"
   assert ${#jobs[@]} = 2

   # Job suffix not set.
   JOB_SUFFIX=
   readarray -t jobs < <(getJobs "$directory")
   assert ! getJobs "$directory"
   assert $(arraysize jobs) = 0
}


test_getDestination() {
   local directory="$RESOURCES/get_destination"
   local BACKUPS_DIR="$RESOURCES/_backup_destination"
   local job destination

   # Job file does not have a destination provided: use default.
   job="$directory/no_destination.backup"
   assert "$(getDestination "$job")" = "$BACKUPS_DIR/no_destination"
   assert getDestination "$job"

   # Destination in job doesn't exist: return anyway.
   job="$directory/fake_destination.backup"
   assert "$(getDestination "$job")" = "$directory/fake_destination"
   assert getDestination "$job"
   
   # Job file has wrong suffix: return empty.
   job="$directory/wrong.suffix"
   assert -z "$(getDestination "$job")"
   assert ! getDestination "$job"

   # Job file doesn't exist: return empty.
   job="/a/job.backup"
   assert -z "$(getDestination "$job")"
   assert ! getDestination "$job"

   # Has multiple destinations: only use the last.
   job="$directory/multiple_destination.backup"
   assert "$(getDestination "$job")" = "$directory/multiple_destination"
   assert getDestination "$job"

   # Default BACKUPS_DIR variable isn't set, and no destination in job:
   # return empty.
   BACKUPS_DIR=
   job="$directory/no_destination.backup"
   assert -z "$(getDestination "$job")"
   assert ! getDestination "$job"

   # Destination is the *ONLY* line in the job (no newline): return destination.
   job="$directory/single_line.backup"
   assert "$(getDestination "$job")" = "$directory/single_line"
   assert getDestination "$job"
}


test_getBackups() {
   local destination="$RESOURCES/get_backups"
   local backupName backup year foundYear
   local -a backups

   # Destination and backup object exist: return array of names.
   backupName=foo.txt.old
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 1

   # Backups are gathered in order of oldest first.
   backupName=order.txt.old
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 3
   year=2020
   for backup in "${backups[@]}"; do
      foundYear="${backup##*/}"
      foundYear="${foundYear%%-*}"
      assert "$foundYear" = $(( year++ ))
   done

   # No backup objects exist: return nothing.
   backupName=fake.txt.old
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 0

   # Destination doesn't exist: return nothing.
   backupName=foo.txt.old
   destination="$directory/fake"
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 0

   # Missing destination argument: return nothing.
   readarray -t backups < <(getBackups "" "$backupName")
   assert $(arraysize backups) = 0

   # Missing backup name argument: return nothing.
   readarray -t backups < <(getBackups "$destination")
   assert $(arraysize backups) = 0
}


test_cleanupBackups() {
   local directory="$RESOURCES/cleanup_backups"
   local destination="$directory/destination"
   local BACKUPS_LIMIT=1
   local -a backups
   local object="$directory/foo.txt"
   local backupName="$(getBackupName "$object")"


   backupsSize(){
      local -a backups
      readarray -t backups < <(getBackups "$destination" "$backupName")
      echo "$(arraysize backups)"
   }

   makeBackups(){
      local count="$1"
      local year
      local -a backups

      readarray -t backups < <(getBackups "$destination" "$backupName")
      year="${backups[0]}"
      year="${year##*/}"
      year="${year%%-*}"
      [ -n "$year" ] && (( year++ ))
      [ -z "$year" ] && year=2000

      while [ "$count" -gt 0 ]; do
         (cd "$destination" && touch "$year"-01-01_"$backupName")
         (( count-- ))
         (( year++ ))
      done
   }


   # Backups are within limit.
   rm "$destination"/*
   makeBackups 1
   assert $(backupsSize) = 1
   assert cleanupBackups "$destination" "$backupName"
   assert $(backupsSize) = 1


   # Backups exceed limit by more than 5: remove 5 oldest backups. Because there
   # are still more that might need to be removed, return failure.
   makeBackups 7
   assert $(backupsSize) = 8
   assert ! cleanupBackups "$destination" "$backupName"
   assert $(backupsSize) = 3

   # Backups exceed limit by less than 5: remove oldest until within limit.
   assert cleanupBackups "$destination" "$backupName"
   assert $(backupsSize) = 1

   # Missing BACKUPS_LIMIT: fail.
   BACKUPS_LIMIT=
   makeBackups 2
   assert $(backupsSize) = 3
   assert ! cleanupBackups "$destination" "$backupName"
   assert $(backupsSize) = 3

   # Missing destination: fail.
   assert ! cleanupBackups "" "$backupName"

   # Destination doesn't exist: fail.
   local fake="$directory/fake"
   assert ! cleanupBackups "$fake" "$backupName"
   assert $(backupsSize) = 3

   # Missing backup name: fail.
   assert ! cleanupBackups "$destination"
   assert $(backupsSize) = 3
}


test_backupObject() {
   local directory="$RESOURCES/backup_object"
   local destination="$directory/destination"
   local object backupName
   local -a backups


   backupsSize(){
      local -a backups
      readarray -t backups < <(getBackups "$destination" "$backupName")
      echo "$(arraysize backups)"
   }


   [ -d "$destination" ] && rm -rf "$destination"

   # Object file exists and destination exist: backup.
   mkdir "$destination"
   object="$directory/foo.txt"
   backupName="$(getBackupName "$object")"
   assert -d "$destination"
   assert -f "$object"
   assert backupObject "$object" "$destination"
   assert $(backupsSize) = 1

   # Object directory exists and destination exist: backup.
   object="$directory/bar"
   backupName="$(getBackupName "$object")"
   assert -d "$destination"
   assert -d "$object"
   assert backupObject "$object" "$destination"
   assert $(backupsSize) = 1

   # Object doesn't exist: fail.
   object="$directory/fake.txt"
   backupName="$(getBackupName "$object")"
   assert -d "$destination"
   assert ! -e "$object"
   assert ! backupObject "$object" "$destination"
   assert $(backupsSize) = 0

   # Destination doesn't exist: create destination.
   [ -d "$destination" ] && rm -rf "$destination"
   object="$directory/foo.txt"
   backupName="$(getBackupName "$object")"
   assert ! -d "$destination"
   assert -f "$object"
   assert backupObject "$object" "$destination"
   assert -d "$destination"
   assert $(backupsSize) = 1

   # Missing object argument: fail.
   assert ! backupObject "" "$destination"

   # Missing destination argument: fail.
   assert ! backupObject "$object"
}


test_backupJob() {
   local directory="$RESOURCES/backup_job"
   local job backupName destination object
   local -a backups objects

   # Job exists, objects exist, destination doesn't exist: backup.
   job="$directory/complete.backup"
   destination="$(getDestination "$job")"
   [ -d "$destination" ] && rm -rf "$destination"
   assert -f "$job"
   assert ! -e "$destination"
   assert backupJob "$job"
   assert -d "$destination"
   readarray -t objects < <(getObjects "$job")
   for object in "${objects[@]}"; do
      backupName="$(getBackupName "$object")"
      readarray -t backups < <(getBackups "$destination" "$backupName")
      assert $(arraysize backups) = 1
   done

   # Backups already exist: backup.
   assert backupJob "$job"
   readarray -t objects < <(getObjects "$job")
   for object in "${objects[@]}"; do
      backupName="$(getBackupName "$object")"
      readarray -t backups < <(getBackups "$destination" "$backupName")
      assert $(arraysize backups) = 1
   done

   # Job exists, objects missing, destination exists: fail.
   job="$directory/empty.backup"
   assert -d "$destination"
   assert ! backupJob "$job"

   # Job doesn't exist: fail.
   rm "$destination"/*
   job="$directory/fake.backup"
   assert ! -f "$job"
   assert ! backupJob "$job"
}


test_readConfig() {
   local directory="$RESOURCES/read_config"
   local config
   local JOBS JOBS_SUFFIX LOG_FILE BACKUPS_LIMIT BACKUPS_DIR

   # Config doesn't exist: fail.
   config="$directory/fake.conf"
   assert ! readConfig "$config"

   # Config has invalid variables: ignore and continue.
   config="$directory/has_invalid.conf"
   readConfig "$config"
   assert "$BACKUPS_LIMIT" = 5
   assert -z "$invalid"
   BACKUPS_LIMIT=

   # Config has whole-line comments: ignore line and continue.
   config="$directory/whole_line_comment.conf"
   readConfig "$config"
   assert "$BACKUPS_LIMIT" = 5
   BACKUPS_LIMIT=

   # Config has comments after values: ignore comment portion and parse.
   config="$directory/partial_line_comment.conf"
   readConfig "$config"
   assert "$BACKUPS_LIMIT" = 5
   BACKUPS_LIMIT=
   assert "$LOG_FILE" = "/log/file.log"
   LOG_FILE=

   # Value has spaces in it with no quotes.
   config="$directory/spaces_no_quotes.conf"
   readConfig "$config"
   assert "$BACKUPS_DIR" = "/backups/directory with/double  spaces"
   BACKUPS_DIR=
   assert "$BACKUPS_LIMIT" = 5
   BACKUPS_LIMIT=

   # Value has spaces with quotes around it.
   config="$directory/spaces_with_quotes.conf"
   readConfig "$config"
   assert "$BACKUPS_DIR" = "/backups/directory with/double  spaces"
   BACKUPS_DIR=
   assert "$BACKUPS_LIMIT" = 5
   BACKUPS_LIMIT=

   # Key is listed twice: use the last value.
   config="$directory/duplicate.conf"
   readConfig "$config"
   assert "$BACKUPS_LIMIT" = 5
   BACKUPS_LIMIT=

   # Config is empty: OK.
   config="$directory/empty.conf"
   readConfig "$config"

   # Normal config with several keys, set values, comments, etc.
   config="$directory/normal.conf"
   readConfig "$config"
   assert "$JOBS" = "/jobs/directory"
   assert "$JOB_SUFFIX" = ".else"
   assert "$LOG_FILE" = "/log/file.log"
   assert "$BACKUPS_DIR" = "/backups/directory with/double  spaces"
   assert "$BACKUPS_LIMIT" = 5
   assert -z "$invalid"
}
