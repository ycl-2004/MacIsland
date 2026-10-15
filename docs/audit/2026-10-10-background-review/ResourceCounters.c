// Read-only counters for explicitly supplied PIDs; no arguments, files or content.
#include <libproc.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2 || argc > 10) return 64;
    uint64_t starts[9] = {0};
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS) return 1;
    for (int sample = 0; sample <= 24; sample++) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        for (int i = 1; i < argc; i++) {
            int pid = atoi(argv[i]);
            struct rusage_info_v4 r = {0};
            if (pid <= 1 || proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&r) != 0) return 1;
            if (sample == 0) starts[i-1] = r.ri_proc_start_abstime;
            if (starts[i-1] != r.ri_proc_start_abstime) return 2;
            printf("{\"sample\":%d,\"monotonic\":%.9f,\"pid\":%d,\"cpuMachTicks\":%llu,\"timebaseNumer\":%u,\"timebaseDenom\":%u,\"rssBytes\":%llu,\"footprintBytes\":%llu,\"packageIdleWakeups\":%llu,\"interruptWakeups\":%llu,\"diskBytesRead\":%llu,\"diskBytesWritten\":%llu}\n",
                   sample, now.tv_sec + now.tv_nsec / 1e9, pid,
                   (unsigned long long)(r.ri_user_time + r.ri_system_time),
                   timebase.numer, timebase.denom,
                   (unsigned long long)r.ri_resident_size, (unsigned long long)r.ri_phys_footprint,
                   (unsigned long long)r.ri_pkg_idle_wkups, (unsigned long long)r.ri_interrupt_wkups,
                   (unsigned long long)r.ri_diskio_bytesread, (unsigned long long)r.ri_diskio_byteswritten);
        }
        fflush(stdout);
        if (sample < 24) sleep(5);
    }
    return 0;
}
