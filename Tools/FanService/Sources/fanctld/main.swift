import Foundation
import FanCore
import SMC

// fanctld — fan control daemon.
//
// Runs the control loop for the configured mode (auto / manual / curve) and
// serves status + config over a Unix socket. Designed to run as a root
// LaunchDaemon; when started unprivileged it serves read-only telemetry.
//
// Safety properties:
//   - restores SMC automatic control on SIGTERM/SIGINT and on fatal errors
//   - failsafe forces max fans if anything reaches 100 °C (or temps go unreadable)
//     while a manual/curve override is active

guard geteuid() == 0 else {
    fputs("Run through the installed system service.\n", stderr)
    exit(1)
}

let controller: FanController
do {
    controller = try FanController()
} catch {
    log("fatal: \(error)")
    exit(1)
}

let server = SocketServer { request in
    switch request.cmd {
    case "status":
        return DaemonResponse(ok: true, status: controller.currentStatus())
    case "set":
        guard let config = request.config else {
            return DaemonResponse(ok: false, error: "set requires a config")
        }
        do {
            let status = try controller.applyConfig(config)
            return DaemonResponse(ok: true, status: status)
        } catch {
            return DaemonResponse(ok: false, error: "\(error)")
        }
    default:
        return DaemonResponse(ok: false, error: "unknown command: \(request.cmd)")
    }
}

func shutdown(_ signalName: String) {
    log("received \(signalName), restoring auto fan control and exiting")
    controller.restoreAuto()
    server.stop()
    exit(0)
}

// A client hanging up mid-reply must not kill the daemon (write() → SIGPIPE
// terminates by default — and a dead daemon can strand fans in forced mode).
signal(SIGPIPE, SIG_IGN)

// Route signals through dispatch sources so we can safely touch the SMC.
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler { shutdown("SIGTERM") }
termSource.resume()
let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
intSource.setEventHandler { shutdown("SIGINT") }
intSource.resume()

do {
    try server.start()
} catch {
    log("fatal: could not start socket server: \(error)")
    exit(1)
}

// Control loop on a dedicated thread. Deliberately NOT a dispatch timer:
// macOS throttles daemons it deems inefficient and can coalesce/starve
// dispatch timers for minutes, which froze the loop mid-control (observed on
// macOS 26 — fans stranded because ticks stopped arriving).
let tickThread = Thread {
    var ticks = 0
    while true {
        controller.tick()
        ticks += 1
        if ticks % 300 == 0 {
            log("heartbeat: \(ticks) ticks")  // every ~10 min, proves the loop is alive
        }
        Thread.sleep(forTimeInterval: 2.0)
    }
}
tickThread.name = "fanctld.tick"
tickThread.qualityOfService = .userInitiated
tickThread.start()

dispatchMain()
