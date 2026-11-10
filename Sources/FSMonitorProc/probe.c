#include "fsmonitor_proc.h"

#include <string.h>

#if defined(__APPLE__)
#include <errno.h>
#include <libproc.h>
#include <sys/resource.h>

int fsmonitor_proc_rusage(
    int pid,
    uint64_t *bytes_read,
    uint64_t *bytes_written,
    uint64_t *logical_writes,
    int *out_errno
) {
    struct rusage_info_v4 usage;
    memset(&usage, 0, sizeof(usage));
    /* proc_pid_rusage's third argument is declared as rusage_info_t *, while
       callers pass the address of the struct. The kernel fills that struct.
       These fields are whole-process counters, not per-directory I/O. */
    int rc = proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage);
    if (rc != 0) {
        if (out_errno != NULL) {
            *out_errno = errno;
        }
        return rc;
    }
    if (bytes_read != NULL) {
        *bytes_read = usage.ri_diskio_bytesread;
    }
    if (bytes_written != NULL) {
        *bytes_written = usage.ri_diskio_byteswritten;
    }
    if (logical_writes != NULL) {
        *logical_writes = usage.ri_logical_writes;
    }
    return 0;
}

int fsmonitor_pid_count(void) {
    return proc_listallpids(NULL, 0);
}

int fsmonitor_copy_pids(int *buffer, int capacity) {
    if (buffer == NULL || capacity <= 0) {
        return -1;
    }
    return proc_listallpids(buffer, capacity * (int)sizeof(int));
}

int fsmonitor_process_name(int pid, char *buffer, int capacity) {
    if (buffer == NULL || capacity <= 0) {
        return -1;
    }
    buffer[0] = '\0';
    int path_bytes = proc_pidpath(pid, buffer, (uint32_t)capacity);
    if (path_bytes > 0) {
        return path_bytes;
    }
    return proc_name(pid, buffer, (uint32_t)capacity);
}

#else

int fsmonitor_proc_rusage(
    int pid,
    uint64_t *bytes_read,
    uint64_t *bytes_written,
    uint64_t *logical_writes,
    int *out_errno
) {
    (void)pid;
    (void)bytes_read;
    (void)bytes_written;
    (void)logical_writes;
    if (out_errno != NULL) {
        *out_errno = 0;
    }
    return -1;
}

int fsmonitor_pid_count(void) {
    return -1;
}

int fsmonitor_copy_pids(int *buffer, int capacity) {
    (void)buffer;
    (void)capacity;
    return -1;
}

int fsmonitor_process_name(int pid, char *buffer, int capacity) {
    (void)pid;
    if (buffer != NULL && capacity > 0) {
        buffer[0] = '\0';
    }
    return -1;
}

#endif
