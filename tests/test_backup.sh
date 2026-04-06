. "/f/.backup/programming/bash/backup/backup.sh"


# Configuration
###############

# Testing config.
RESOURCES="/f/.backup/programming/bash/backup/tests/_resources"

# Module config.
LOG_LOCATION=  # Disable logging.


# Tests
#######

test_log() {
   local LOG_LOCATION="$RESOURCES/log/backups.log"
   
   [ ! -f "$LOG_LOCATION" ] || rm "$LOG_LOCATION"
   assert ! -e "$LOG_LOCATION"

   assert ! log
   assert log "pass message 1" "assert_test"

   assert log "error message" "assert_test" fail
   assert -n "$(tail -1 "$LOG_LOCATION" | grep "[ERROR]")"

   [ -f "$LOG_LOCATION" ] && rm "$LOG_LOCATION"
   LOG_LOCATION=""
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

   # Job contains multiple real files and directories.
   job="$directory/multiple.backup"
   readarray -t objects < <(getObjects "$job")
   assert $(arraysize objects) = 4
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

   # JOBS variable not set and no specified directory.
   local JOBS=
   readarray -t jobs < <(getJobs)
   assert $(arraysize jobs) = 0
   assert ! getJobs

   # JOBS variable is set, no specified directory.
   JOBS="$RESOURCES/get_jobs"
   readarray -t jobs < <(getJobs)
   assert ${#jobs[@]} = 3
   assert getJobs

   # Get jobs from a specified directory instead of JOBS variable.
   directory="$RESOURCES/_known_good"
   readarray -t jobs < <(getJobs "$directory")
   assert $(arraysize jobs) = 1
   assert getJobs "$directory"
   
   # Specified directory doesn't exist.
   directory="/a/directory"
   readarray -t jobs < <(getJobs "$directory")
   assert $(arraysize jobs) = 0
   assert ! getJobs "$directory"

   # Directory contains no jobs.
   directory="$RESOURCES/_backup_destination"
   readarray -t jobs < <(getJobs "$directory")
   assert $(arraysize jobs) = 0
   assert ! getJobs "$directory"

   # Job suffix is changed from default .backup.
   local JOB_SUFFIX=.else
   readarray -t jobs < <(getJobs)
   assert ${#jobs[@]} = 2

   # Job suffix not set.
   local JOB_SUFFIX=
   readarray -t jobs < <(getJobs)
   assert $(arraysize jobs) = 0
   assert ! getJobs
}


test_getDestination() {
   local directory="$RESOURCES/get_destination"
   local BACKUPS_DESTINATION="$directory/default dir"
   local job destination

   # Job file has a real destination provided.
   job="$directory/has_destination.backup"
   assert "$(getDestination "$job")" = "$directory/override dir"
   assert getDestination "$job"
   
   # Job file does not have a destination provided: use default.
   job="$directory/no_destination.backup"
   destination="$BACKUPS_DESTINATION/no_destination"
   assert "$(getDestination "$job")" = "$destination"
   assert getDestination "$job"

   # Destination in job doesn't exist: return anyway.
   job="$directory/fake_destination.backup"
   destination="$RESOURCES/fake/destination"
   assert "$(getDestination "$job")" = "$destination"
   assert getDestination "$job"
   
   # Job file has wrong suffix: return empty.
   job="$directory/wrong.suffix"
   assert -z "$(getDestination "$job")"
   assert ! getDestination "$job"

   # Job file doesn't exist: return empty.
   job="/a/job.backup"
   assert -z "$(getDestination "$job")"
   assert ! getDestination "$job"

   # Has multiple destinations: only use the first.
   job="$directory/multiple_destination.backup"
   assert "$(getDestination "$job")" = "$directory/override dir"
   assert getDestination "$job"

   # Default BACKUPS_DESTINATION variable isn't set, and no destination in job:
   # return empty.
   BACKUPS_DESTINATION=
   job="$directory/no_destination.backup"
   assert -z "$(getDestination "$job")"
   assert ! getDestination "$job"
}


test_getBackups() {
   local directory="$RESOURCES/get_backups"
   local destination="$directory/destination"
   local backupName
   local -a backups

   # Destination and backup object exist: return array of names.
   backupName=foo.txt.old
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 1

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
   local BACKUPS_LIMIT=3
   local -a backups
   local object="$directory/foo.txt"
   local backupName="$(getBackupName "$object")"

   # Backups are within limit.
   rm "$destination"/*
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 0
   assert backupObject "$object" "$destination"
   (cd "$destination" && touch 202{2,3}-01-01_"$backupName")
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 3
   assert cleanupBackups "$destination" "$backupName"
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 3

   # Backups exceed limit by more than 5: remove 5 oldest backups. Because there
   # are still more that might need to be removed, return failure.
   (cd "$destination" && touch 201{0..5}-01-01_"$backupName")
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 9
   assert ! cleanupBackups "$destination" "$backupName"
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 4

   # Backups exceed limit by less than 5: remove oldest until within limit.
   BACKUPS_LIMIT=1
   assert cleanupBackups "$destination" "$backupName"
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 1

   # Missing BACKUPS_LIMIT: fail.
   BACKUPS_LIMIT=
   (cd "$destination" && touch 202{2,3}-01-01_"$backupName")
   assert ! cleanupBackups "$destination" "$backupName"
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 3

   # Missing destination: fail.
   assert ! cleanupBackups "" "$backupName"

   # Destination doesn't exist: fail.
   local fake="$directory/fake"
   assert ! cleanupBackups "$fake" "$backupName"
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 3

   # Missing backup name: fail.
   assert ! cleanupBackups "$destination"
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 3
}


test_backupObject() {
   local directory="$RESOURCES/backup_object"
   local destination="$directory/destination"
   local object backupName
   local -a backups

   # Object file exists and destination exist: backup.
   object="$directory/foo.txt"
   backupName="$(getBackupName "$object")"
   assert "$backupName" = foo.txt.old
   assert -d "$destination"
   assert -f "$object"
   assert backupObject "$object" "$destination"
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 1

   # Object directory exists and destination exist: backup.
   object="$directory/bar"
   backupName="$(getBackupName "$object")"
   assert "$backupName" = bar.old
   assert -d "$destination"
   assert -d "$object"
   assert backupObject "$object" "$destination"
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 1

   # Object doesn't exist: fail.
   object="$directory/fake.txt"
   backupName="$(getBackupName "$object")"
   assert "$backupName" = fake.txt.old
   assert -d "$destination"
   assert ! -e "$object"
   assert ! backupObject "$object" "$destination"
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 0

   # Destination doesn't exist: create destination.
   [ -d "$destination" ] && rm -rf "$destination"
   object="$directory/foo.txt"
   backupName="$(getBackupName "$object")"
   assert "$backupName" = foo.txt.old
   assert ! -d "$destination"
   assert -f "$object"
   assert backupObject "$object" "$destination"
   assert -d "$destination"
   readarray -t backups < <(getBackups "$destination" "$backupName")
   assert $(arraysize backups) = 1

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
