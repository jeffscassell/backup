. "/f/.backup/programming/bash/backup/backup.sh"


# Configuration
###############

# Testing config.
RESOURCES="/f/.backup/programming/bash/backup/tests/_resources"

# Module config.
JOBS="$RESOURCES/jobs"
BACKUPS_DESTINATION="$RESOURCES/backups"
LOG_LOCATION=  # Disable logging.


# Tests
#######

test_log() {
   local LOG_LOCATION="$RESOURCES/backups.log"
   [ -f "$LOG_LOCATION" ] && rm "$LOG_LOCATION"

   assert ! log
   assert log "test message 1" "assert_test"

   local LOG_LOCATION=""
   assert ! log "test message 2" "assert_test"
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


test_getValidObjects() {
   local -a objects
   readarray -t objects < <(getValidObjects "$JOBS/foo.backup")
   assert ${#objects[@]} = 2

   objects=()
   readarray -t objects < <(getValidObjects "$JOBS/foo_empty.backup")
   assert ${#objects[@]} = 0

   objects=(/a/made/up/file.txt /a/made/up/directory)
   readarray -t objects < <(getValidObjects objects)
   assert ${#objects[@]} = 0
}


test_getJobFiles() {
   local -a jobFiles
   readarray -t jobFiles < <(getJobFiles)
   assert ${#jobFiles[@]} = 2

   jobFiles=()
   readarray -t jobFiles < <(getJobFiles "$OBJECTS_PARENT")
   assert ${#jobFiles[@]} = 0

   assert ! getJobFiles "/a/fake/dir"

   local JOBS=
   assert ! getJobFiles
}


test_backup() {
   local jobDestination jobFile
   local -a files

   jobFile="$JOBS/foo.backup"
   jobDestination="$BACKUPS_DESTINATION/$(getJobName "$jobFile")"
   [ -d "$jobDestination" ] && rm -rf "$jobDestination"
   assert ! -e "$jobDestination"

   assert backup "$jobFile"
   assert -d "$jobDestination"
   readarray -t files < <(find "$jobDestination")
   assert ${#files[@]} = 5

   jobFile="$JOBS/foo_empty.backup"
   jobDestination="$BACKUPS_DESTINATION/$(getJobName "$jobFile")"
   assert ! -e "$jobDestination"
   assert ! backup "$jobFile"
   assert ! -e "$jobDestination"
}


test_backupObject() {
   echo
}


test_cleanupBackups() {
   echo
}
