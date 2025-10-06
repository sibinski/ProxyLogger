import Foundation
import Network

// Create and open a log file at /tmp/proxy_log.txt with a purpose of storing timestamped proxy activity
let logFilePath = "/tmp/proxy_log.txt"
if !FileManager.default.fileExists(atPath: logFilePath) {
    FileManager.default.createFile(atPath: logFilePath, contents: nil, attributes: nil)
}
let logFile = FileHandle(forWritingAtPath: logFilePath)
logFile?.seekToEndOfFile()

// Define logging function with a purpose of writing to both terminal and file
func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)"
    print(line)
    if let data = "\(line)\n".data(using: .utf8) {
        logFile?.write(data)
    }
}

// Declare global listener, signal handler, and mitmdump process with a purpose of managing lifecycle and connections
var listener: NWListener!
var signalSource: DispatchSourceSignal?
var mitmProcess: Process?

// Enable system proxy settings with a purpose of redirecting browser traffic to local port 8080
func setSystemProxy() {
    let httpProxy = Process()
    httpProxy.launchPath = "/usr/sbin/networksetup"
    httpProxy.arguments = ["-setwebproxy", "Wi-Fi", "127.0.0.1", "8080"]
    httpProxy.launch()
    httpProxy.waitUntilExit()

    let httpsProxy = Process()
    httpsProxy.launchPath = "/usr/sbin/networksetup"
    httpsProxy.arguments = ["-setsecurewebproxy", "Wi-Fi", "127.0.0.1", "8080"]
    httpsProxy.launch()
    httpsProxy.waitUntilExit()

    log("System proxy (HTTP & HTTPS) set to 127.0.0.1:8080")
}

// Disable system proxy settings with a purpose of restoring normal network behavior on shutdown
func disableSystemProxy() {
    let disableHTTP = Process()
    disableHTTP.launchPath = "/usr/sbin/networksetup"
    disableHTTP.arguments = ["-setwebproxystate", "Wi-Fi", "off"]
    disableHTTP.launch()
    disableHTTP.waitUntilExit()

    let disableHTTPS = Process()
    disableHTTPS.launchPath = "/usr/sbin/networksetup"
    disableHTTPS.arguments = ["-setsecurewebproxystate", "Wi-Fi", "off"]
    disableHTTPS.launch()
    disableHTTPS.waitUntilExit()

    log("System proxy (HTTP & HTTPS) disabled")
}

// Monitor for termination flag file with a purpose of triggering graceful shutdown externally
DispatchQueue.global().async {
    while true {
        if FileManager.default.fileExists(atPath: "/tmp/proxylogger.stop") {
            log("Termination flag detected. Shutting down.")
            disableSystemProxy()
            do {
                try FileManager.default.removeItem(atPath: "/tmp/proxylogger.stop")
            } catch {
                log("Could not clean up termination flag file.")
            }
            logFile?.closeFile()
            exit(0)
        }
        sleep(2)
    }
}

// Setup SIGINT handler with a purpose of allowing Ctrl+C to cleanly stop the proxy and restore system state
func setupSignalHandler() {
    signal(SIGINT, SIG_IGN)
    signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signalSource?.setEventHandler {
        log("Proxy shutting down via SIGINT (Ctrl + C)")
        listener.cancel()
        disableSystemProxy()
        logFile?.closeFile()
        exit(0)
    }
    signalSource?.resume()
}

// Create bidirectional TCP relay with a purpose of forwarding traffic between browser and mitmdump
func tunnel(_ client: NWConnection, _ server: NWConnection) {
    func relay(from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
            if let data = data {
                to.send(content: data, completion: .contentProcessed { _ in
                    relay(from: from, to: to)
                })
            } else {
                from.cancel()
                to.cancel()
            }
        }
    }
    relay(from: client, to: server)
    relay(from: server, to: client)
}

// Launch mitmdump subprocess with a purpose of intercepting and logging HTTP/HTTPS traffic
func startMitmproxyAndCaptureOutput() {
    let mitm = Process()
    mitm.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/mitmdump")
    mitm.arguments = ["--listen-port", "8081", "--mode", "regular", "-v"]

    let pipe = Pipe()
    mitm.standardOutput = pipe
    mitm.standardError = pipe
    let outputHandle = pipe.fileHandleForReading

    // Parse mitmdump output with a purpose of extracting and logging visible URLs
    outputHandle.readabilityHandler = { handle in
        if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = trimmed.range(of: #"https?://[^\s]+"#, options: .regularExpression) {
                let url = String(trimmed[range])
                log("URL: \(url)")
            }
        }
    }

    do {
        try mitm.run()
        mitmProcess = mitm
        log("mitmproxy started on port 8081")
    } catch {
        log("Failed to start mitmproxy: \(error)")
    }
}

// Wait for mitmdump to bind to port 8081 with a purpose of ensuring readiness before forwarding traffic
func waitForMitmproxyReady(timeout: Int = 5) {
    for _ in 0..<timeout {
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-i", ":8081"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if output.contains("mitmdump") {
            log("Confirmed mitmdump is listening on port 8081")
            return
        }
        sleep(1)
    }
    log("Timeout waiting for mitmdump to bind to port 8081")
}

// Start TCP listener on port 8080 with a purpose of intercepting browser traffic redirected by system proxy
listener = try! NWListener(using: .tcp, on: 8080)
log("Proxy started on port 8080")

// Handle incoming TCP connections with a purpose of parsing requests and forwarding them to mitmdump
listener.newConnectionHandler = { connection in
    connection.start(queue: .main)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
        guard let data = data,
              let request = String(data: data, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first else {
            connection.cancel()
            return
        }

        // Parse HTTP request line with a purpose of extracting method and target URL/domain
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 3 else {
            connection.cancel()
            return
        }

        let method = parts[0]
        let target = parts[1]

        // Extract User-Agent header with a purpose of identifying browser-originated traffic
        let userAgentLine = request.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("user-agent:") })
        let browserSignatures = ["Mozilla", "Chrome", "Safari", "Firefox"]
        let isBrowser = browserSignatures.contains { sig in
            userAgentLine?.lowercased().contains(sig.lowercased()) ?? false
        }

        // Log HTTPS domains unconditionally with a purpose of capturing encrypted traffic targets
        if method == "CONNECT" {
            log("HTTPS domain: \(target)")
        }
        // Log HTTP URLs only if User-Agent matches known browser signatures with a purpose of filtering noise
        else if isBrowser {
            log("URL: \(target)")
        }

        // Forward raw request to mitmdump with a purpose of enabling deeper inspection and logging
        let mitm = NWConnection(host: "127.0.0.1", port: 8081, using: .tcp)
        mitm.start(queue: .main)
        mitm.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                log("Failed to send to mitmdump: \(error)")
                connection.cancel()
                mitm.cancel()
            } else {
                tunnel(connection, mitm)
            }
        })
    }
}

// Initialize proxy components with a purpose of activating full logging and interception flow
setSystemProxy()
setupSignalHandler()
startMitmproxyAndCaptureOutput()
waitForMitmproxyReady()
listener.start(queue: .main)
RunLoop.main.run()
