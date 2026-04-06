. "/f/.backup/programming/bash/backup/backup.sh"


# Configuration
###############

# Testing config.
RESOURCES="/f/.backup/programming/bash/backup/tests/_resources"

# Module config.
LOG_LOCATION=  # Disable logging.


# Tests
#######

# test_log() {
#    local LOG_LOCATION="$RESOURCES/log/backups.log"
   
#    [ ! -f "$LOG_LOCATION" ] || rm "$LOG_LOCATION"
#    assert ! -e "$LOG_LOCATION"

#    assert ! log
#    assert log "pass message 1" "assert_test"

#    assert log "error message" "assert_test" fail
#    assert -n "$(tail -1 "$LOG_LOCATION" | grep "[ERROR]")"

#    [ -f "$LOG_LOCATION" ] && rm "$LOG_LOCATION"
#    LOG_LOCATION=""
#    assert ! log "fail message 1" "assert_test"
# }


# test_getJobName() {
#    assert "$(getJobName /a/full/path/test.backup)" = test
#    assert "$(getJobName something.backup)" = something
#    assert -z "$(getJobName something.else)"

#    local JOB_SUFFIX=".else"
#    assert "$(getJobName something.else)" = something

#    local JOB_SUFFIX=
#    assert -z "$(getJobName something)"
# }


# test_getBackupName() {
#    assert "$(getBackupName /a/path/file.txt)" = file.txt.old
#    assert "$(getBackupName /a/path/a.longer.file.txt)" = a.longer.file.txt.old
#    assert "$(getBackupName file.txt)" = file.txt.old
#    assert "$(getBackupName /a/path/directory)" = directory.old
#    assert "$(getBackupName directory)" = directory.old
# }


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


# test_getJobs() {
#    local -a jobs
#    local directory

#    # JOBS variable not set and no specified directory.
#    local JOBS=
#    readarray -t jobs < <(getJobs)
#    assert $(arraysize jobs) = 0
#    assert ! getJobs

#    # JOBS variable is set, no specified directory.
#    JOBS="$RESOURCES/get_jobs"
#    readarray -t jobs < <(getJobs)
#    assert ${#jobs[@]} = 3
#    assert getJobs

#    # Get jobs from a specified directory instead of JOBS variable.
#    directory="$RESOURCES/_known_good"
#    readarray -t jobs < <(getJobs "$directory")
#    assert $(arraysize jobs) = 1
#    assert getJobs "$directory"
   
#    # Specified directory doesn't exist.
#    directory="/a/directory"
#    readarray -t jobs < <(getJobs "$directory")
#    assert $(arraysize jobs) = 0
#    assert ! getJobs "$directory"

#    # Directory contains no jobs.
#    directory="$RESOURCES/_backup_destination"
#    readarray -t jobs < <(getJobs "$directory")
#    assert $(arraysize jobs) = 0
#    assert ! getJobs "$directory"

#    # Job suffix is changed from default .backup.
#    local JOB_SUFFIX=.else
#    readarray -t jobs < <(getJobs)
#    assert ${#jobs[@]} = 2

#    # Job suffix not set.
#    local JOB_SUFFIX=
#    readarray -t jobs < <(getJobs)
#    assert $(arraysize jobs) = 0
#    assert ! getJobs
# }


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


# test_backupJob() {
#    local jobDestination job
#    local -a files
#    local BACKUPS_DESTINATION="$RESOURCES/backup"

#    job="$JOBS/foo.backup"
#    jobDestination="$BACKUPS_DESTINATION/$(getJobName "$job")"
#    [ -d "$jobDestination" ] && rm -rf "$jobDestination"
#    assert ! -e "$jobDestination"

#    assert backup "$job"
#    assert -d "$jobDestination"
#    readarray -t files < <(find "$jobDestination")
#    assert ${#files[@]} = 5

#    job="$JOBS/foo_empty.backup"
#    jobDestination="$BACKUPS_DESTINATION/$(getJobName "$job")"
#    assert ! -e "$jobDestination"
#    assert ! backup "$job"
#    assert ! -e "$jobDestination"
# }


# test_backupObject() {
#    local jobDestination="$BACKUPS_DESTINATION/backup_object"
#    local object="/f/.backup/programming/bash/backup/tests/_resources/\
# backup_object/backup_object_file.txt"

#    [ -d "$jobDestination" ] && rm -rf "$jobDestination"
#    assert ! -e "$jobDestination"
#    assert -f "$object"
#    assert backupObject "$object" "$jobDestination"
#    assert -d "$jobDestination"
# }


# test_cleanupBackups() {
#    echo
# }
