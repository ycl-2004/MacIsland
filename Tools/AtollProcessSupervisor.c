// Owns one child and reaps it when Atoll exits, including SIGKILL/crash.
// No process-name matching and no signals to processes it did not fork.
#include <sys/event.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>

static volatile sig_atomic_t stopping = 0;
static void stop(int signal_number) { (void)signal_number; stopping = 1; }

int main(int argc, char **argv) {
    if (argc < 2 || argv[1][0] != '/') return 64;
    pid_t parent = getppid();
    if (parent <= 1) return 1;
    int queue = kqueue();
    if (queue < 0) return 1;
    struct kevent change;
    EV_SET(&change, parent, EVFILT_PROC, EV_ADD | EV_ENABLE, NOTE_EXIT, 0, NULL);
    if (kevent(queue, &change, 1, NULL, 0, NULL) < 0 || getppid() != parent) return 1;
    signal(SIGTERM, stop);
    signal(SIGINT, stop);
    pid_t child = fork();
    if (child < 0) return 1;
    if (child == 0) {
        close(queue);
        signal(SIGTERM, SIG_DFL);
        signal(SIGINT, SIG_DFL);
        execv(argv[1], &argv[1]);
        _exit(127);
    }
    int status = 0;
    struct kevent changes[3];
    EV_SET(&changes[0], child, EVFILT_PROC, EV_ADD | EV_ENABLE, NOTE_EXIT, 0, NULL);
    EV_SET(&changes[1], SIGTERM, EVFILT_SIGNAL, EV_ADD | EV_ENABLE, 0, 0, NULL);
    EV_SET(&changes[2], SIGINT, EVFILT_SIGNAL, EV_ADD | EV_ENABLE, 0, 0, NULL);
    // Child exit can race registration; waitpid below handles that case.
    if (kevent(queue, changes, 3, NULL, 0, NULL) < 0 && errno != ESRCH) stopping = 1;
    while (!stopping) {
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) { close(queue); return WIFEXITED(status) ? WEXITSTATUS(status) : 1; }
        if (result < 0 && errno != EINTR) break;
        struct kevent event;
        // No recurring wakes while healthy. Signals are queued as events, too,
        // so TERM arriving just before this wait cannot be lost.
        int count = kevent(queue, NULL, 0, &event, 1, NULL);
        if (count < 0) { if (errno == EINTR) continue; break; }
        if (count > 0 && event.filter == EVFILT_PROC && event.ident == (uintptr_t)child) continue;
        if (count > 0) break;
    }
    kill(child, SIGTERM);
    for (int attempt = 0; attempt < 10; ++attempt) {
        if (waitpid(child, &status, WNOHANG) == child) { close(queue); return 0; }
        usleep(10000);
    }
    kill(child, SIGKILL);
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
    close(queue);
    return 0;
}
