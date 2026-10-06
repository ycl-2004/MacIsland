// A tiny, event-driven lease owner. It restores only processes it stopped,
// identified by uid, executable name and birth time (safe against PID reuse).
#include <sys/event.h>
#include <sys/proc.h>
#include <libproc.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

struct lease { pid_t pid; uint64_t sec, usec; };
static struct lease leases[8];
static int count;
static int identity(pid_t pid, struct proc_bsdinfo *info) {
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, info, sizeof(*info)) == sizeof(*info)
        && info->pbi_uid == getuid();
}
static void restore(void) {
    for (int i = 0; i < count; i++) {
        struct proc_bsdinfo info;
        if (identity(leases[i].pid, &info) && info.pbi_start_tvsec == leases[i].sec
            && info.pbi_start_tvusec == leases[i].usec) kill(leases[i].pid, SIGCONT);
    }
    count = 0;
}
static void stop_owned(pid_t pid) {
    struct proc_bsdinfo info;
    char name[PROC_PIDPATHINFO_MAXSIZE];
    for (int i = count - 1; i >= 0; i--) {
        struct proc_bsdinfo previous;
        if (!identity(leases[i].pid, &previous) || previous.pbi_start_tvsec != leases[i].sec
            || previous.pbi_start_tvusec != leases[i].usec) leases[i] = leases[--count];
    }
    if (pid <= 1 || pid == getpid() || pid == getppid() || !identity(pid, &info)
        || info.pbi_status == SSTOP || count == 8) return;
#ifdef ATOLL_GUARDIAN_TEST
    const char *expected = "sleep";
#else
    const char *expected = "OSDUIHelper";
#endif
    if (proc_name(pid, name, sizeof(name)) <= 0 || strcmp(name, expected)) return;
    // Record ownership before stopping so every exit path can recover it.
    leases[count++] = (struct lease){pid, info.pbi_start_tvsec, info.pbi_start_tvusec};
    if (kill(pid, SIGSTOP)) count--;
}
int main(void) {
    pid_t parent = getppid();
    if (parent <= 1) return 1;
    int kq = kqueue();
    if (kq < 0) return 1;
    struct kevent changes[5];
    signal(SIGTERM, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    EV_SET(&changes[0], parent, EVFILT_PROC, EV_ADD | EV_ENABLE, NOTE_EXIT, 0, NULL);
    EV_SET(&changes[1], STDIN_FILENO, EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, NULL);
    EV_SET(&changes[2], SIGTERM, EVFILT_SIGNAL, EV_ADD | EV_ENABLE, 0, 0, NULL);
    EV_SET(&changes[3], SIGINT, EVFILT_SIGNAL, EV_ADD | EV_ENABLE, 0, 0, NULL);
    EV_SET(&changes[4], SIGHUP, EVFILT_SIGNAL, EV_ADD | EV_ENABLE, 0, 0, NULL);
    if (kevent(kq, changes, 5, NULL, 0, NULL) < 0) { close(kq); return 1; }
    char command[128];
    size_t length = 0;
    for (;;) {
        struct kevent events[5];
        int n = kevent(kq, NULL, 0, events, 5, NULL);
        if (n < 0) break;
        int exiting = 0;
        for (int i = 0; i < n; i++) {
            if (events[i].filter == EVFILT_PROC || events[i].filter == EVFILT_SIGNAL || events[i].flags & EV_ERROR) exiting = 1;
        }
        if (exiting) break;
        for (int i = 0; i < n; i++) {
            if (events[i].filter != EVFILT_READ) continue;
            char bytes[128];
            ssize_t got = read(STDIN_FILENO, bytes, sizeof(bytes));
            if (got <= 0) { exiting = 1; break; }
            for (ssize_t j = 0; j < got; j++) {
                if (bytes[j] == '\n') {
                    command[length] = 0;
                    if (!strcmp(command, "R")) restore();
                    else if (command[0] == 'S' && command[1] == ' ') stop_owned((pid_t)strtol(command + 2, NULL, 10));
                    length = 0;
                } else if (length < sizeof(command) - 1) command[length++] = bytes[j];
                else { exiting = 1; break; }
            }
        }
        if (exiting) break;
    }
    restore();
    close(kq);
    return 0;
}
