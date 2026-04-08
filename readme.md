# Backup.sh

Meant to be used with smaller `job` files (.backup) that contain `objects`
(files/directories) that need to be backed up. Objects should be full paths.

### Job Files

A `job` file can contain directories and files, and can specify an optional
`destination` variable to override the default backups directory. For a `job`
named `job_name.backup`, the default backup directory is
`$BACKUPS_DIRECTORY/job_name`. This directory will contain backups of all
the objects specified in the `job`, dated but not timestamped like so:
`2026-01-01_object_file.txt.old`.

### Options

Running with `--jobs` option will gather all jobs in the `JOBS` directory and
process them. Running with only `job` file(s) will only process those
jobs. Running with a directory will search that directory for `job` files and
process them if found. All can be used together, but `--jobs` (and all options)
should come first. `-c` or `--config` followed by a configuration file will use
that configuration file to override the default configuration values for `JOBS`,
`LOG_FILE`, etc.

# Examples

### At the terminal

```
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
```

### Sample job file (that uses default destination)

```
# jellyfin.backup

/server/config_directory
/server/some_file
/server/cache_directory
```

### Sample job file (that uses custom destination)

```
# jellyfin.backup

/server/config_directory
/server/some_file
/server/cache_directory

destination="/customized/directory/for/jellyfin"
```

### Sample backed up objects

```
# /rpool/backups/jellyfin/

2026-03-23_cache_directory.old/
   file
   subdir/
      ...
2026-03-23_config_directory.old/
   ...
2026-03-23_some_file.txt.old
```

# Configuration

### *JOBS*

>> Directory
>
> Collected job files that should be run with the "--jobs" option.

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

### *BACKUPS_DIR*

>> Directory
>
> The centralized backups directory to be used if a job doesn't specify one.
> If used, jobs are stored in this directory, under a job's own subdirectory.

### *LOG_FILE*

>> File
>
> The file to be used for logging purposes. Optional.