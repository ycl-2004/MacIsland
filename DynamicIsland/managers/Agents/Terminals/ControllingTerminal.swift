import Darwin

/// Which terminal device a process belongs to, and what runs in that terminal's
/// foreground, read from the kernel's process table (`sysctl(3)`, `KERN_PROC`).
enum ControllingTerminal {
    /// Programs a terminal returns to once the agent exits. Text typed into one
    /// of them would run as a command, so Atoll never types there.
    static let shells: Set<String> = ["login", "sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "xonsh"]

    /// `NODEV` from <sys/param.h>, a macro Swift does not import.
    private static let noDevice: dev_t = -1

    /// The device path of `pid`'s controlling terminal ("/dev/ttys003"), or of
    /// its nearest ancestor's. A hook the agent runs outside any terminal (a
    /// background service) has none.
    static func device(ofProcess pid: Int32) -> String? {
        var current = pid
        for _ in 0..<6 where current > 1 {
            guard let info = process(current) else { return nil }
            if info.kp_eproc.e_tdev != noDevice, let name = devname(info.kp_eproc.e_tdev, S_IFCHR) {
                return "/dev/" + String(cString: name)
            }
            current = info.kp_eproc.e_ppid
        }
        return nil
    }

    /// Something other than a shell holds the terminal's foreground: the agent
    /// still runs there, so typed text reaches the agent.
    static func agentHoldsForeground(device: String) -> Bool {
        var status = stat()
        guard stat(device, &status) == 0 else { return false }
        let processes = processes(onTerminal: status.st_rdev)
        guard let foreground = processes.first?.kp_eproc.e_tpgid, foreground > 0 else { return false }
        let names = processes.filter { $0.kp_eproc.e_pgid == foreground }.map(commandName)
        return names.contains { !shells.contains($0) }
    }

    private static func process(_ pid: Int32) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    private static func processes(onTerminal device: dev_t) -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_TTY, Int32(bitPattern: UInt32(truncatingIfNeeded: device))]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // Room for processes started between the two calls.
        var list = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 8)
        size = list.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &list, &size, nil, 0) == 0 else { return [] }
        return Array(list.prefix(size / MemoryLayout<kinfo_proc>.stride))
    }

    private static func commandName(_ info: kinfo_proc) -> String {
        var command = info.kp_proc.p_comm
        return withUnsafeBytes(of: &command) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
