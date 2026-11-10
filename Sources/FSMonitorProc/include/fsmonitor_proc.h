#ifndef FSMONITOR_PROC_H
#define FSMONITOR_PROC_H

#include <stdint.h>

/* macOS libproc helpers. On other systems every call fails and writes no counters. */
int fsmonitor_proc_rusage(
    int pid,
    uint64_t *bytes_read,
    uint64_t *bytes_written,
    uint64_t *logical_writes,
    int *out_errno
);
int fsmonitor_pid_count(void);
int fsmonitor_copy_pids(int *buffer, int capacity);
int fsmonitor_process_name(int pid, char *buffer, int capacity);

#endif
