# Backup.sh

Meant to be used with smaller `job` files (.backup) that contain `objects`
(files/directories) that need to be backed up. Objects should be full paths.



Running with "run" option will gather all jobs in the `JOBS` directory and
process them. Running with specific job file(s) will only process those
jobs.

## Examples

```
# Run all jobs in the JOBS directory.
backup.sh run

# Run only the specified jobs.
backup.sh sample_1.backup sample_2.backup

# Run with a user-specified config, with all jobs in the JOBS directory.
backup.sh -c "backup.conf" run
```

### Sample Job File

```
# jellyfin.backup

/server/config
/server/cache

# Overrides the default centralized directory (optional).
#destination="/customized/directory/for/jellyfin"

# Default:
# $BACKUPS_DESTINATION/<job>
```

### Sample Backed Up Objects

```
# /rpool/backups/jellyfin/

2026-03-23_config.old/
2026-03-23_cache.old/
```

## Configuration

### *JOBS*

>> Directory
>
> Collected job files that should be run with the "run" option.

### *JOB_SUFFIX*

>> File suffix
>
> The suffix that files must have to be considered jobs.
>
> **Default:** .backup

### *BACKUPS_LIMIT*

>> Integer
>
> The maximum number of backups to keep of each job's objects.
>
> **Default:** 2

### *BACKUPS_DESTINATION*

>> Directory
>
> The centralized backups directory to be used if a job doesn't specify one.
> If used, jobs are stored in this directory, under a job's own subdirectory.

### *LOG_FILE*

>> File
>
> The file to be used for logging purposes. Optional.