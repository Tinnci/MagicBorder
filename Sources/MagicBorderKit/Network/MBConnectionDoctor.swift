import Darwin
import Foundation
import Network
private import os

/// Pre-flight network diagnostics and log redaction helpers for MagicBorder pairing.
public enum MBConnectionDoctor: Sendable {
    public enum StageStatus: Equatable, Sendable {
        case passed(String)
        case warning(String)
        case failed(String)
    }

    public struct StageResult: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let status: StageStatus
        public let latencyMs: Int?

        public init(id: String, title: String, status: StageStatus, latencyMs: Int? = nil) {
            self.id = id
            self.title = title
            self.status = status
            self.latencyMs = latencyMs
        }

        public var isError: Bool {
            if case .failed = self.status {
                return true
            }
            return false
        }
    }

    public struct Report: Equatable, Sendable {
        public let host: String
        public let protocolMode: MBProtocolMode
        public let stages: [StageResult]
        public let summary: String

        public var isHealthy: Bool {
            !self.stages.contains(where: \.isError)
        }
    }

    private struct ProbeOutcome: Sendable {
        let reachable: Bool
        let latencyMs: Int?
        let detail: String?
    }

    public static func localIPv4Addresses() -> [String] {
        var addrList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrList) == 0, let firstAddr = addrList else { return [] }
        defer { freeifaddrs(addrList) }

        var results: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let sockAddr = current.pointee.ifa_addr,
                sockAddr.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            var address = sockAddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                continue
            }
            let ipBytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            let ip = String(decoding: ipBytes, as: UTF8.self)
            if !ip.hasPrefix("127."), !ip.hasPrefix("169.254."), !results.contains(ip) {
                results.append(ip)
            }
        }
        return results
    }

    public static func diagnose(
        host: String,
        protocolMode: MBProtocolMode,
        securityKey: String,
        messagePort: UInt16,
        clipboardPort: UInt16,
        timeoutSeconds: Double = 2.0
    ) async -> Report {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var stages: [StageResult] = [
            Self.validateKeyStage(protocolMode: protocolMode, securityKey: securityKey)
        ]

        guard !trimmedHost.isEmpty else {
            stages.append(
                StageResult(
                    id: "host",
                    title: "Target Address",
                    status: .failed("Enter a target IP address or hostname.")))
            return Report(
                host: trimmedHost,
                protocolMode: protocolMode,
                stages: stages,
                summary: "No target host entered.")
        }

        let targetPort = protocolMode == .modern ? UInt16(12345) : messagePort
        let primaryLabel =
            protocolMode == .modern ? "Modern Channel (\(targetPort))" : "MWB Message Port (\(targetPort))"
        let primaryProbe = await Self.probeTCP(
            host: trimmedHost,
            port: targetPort,
            timeoutSeconds: timeoutSeconds)

        if primaryProbe.reachable {
            let rttText = primaryProbe.latencyMs.map { "\($0) ms" } ?? "Connected"
            stages.append(
                StageResult(
                    id: "primary-port",
                    title: primaryLabel,
                    status: .passed("Reachable (\(rttText))"),
                    latencyMs: primaryProbe.latencyMs))
        } else {
            stages.append(
                StageResult(
                    id: "primary-port",
                    title: primaryLabel,
                    status: .failed(primaryProbe.detail ?? "Port \(targetPort) unreachable or blocked by firewall")))
        }

        if protocolMode == .mwbCompatibility {
            let clipProbe = await Self.probeTCP(
                host: trimmedHost,
                port: clipboardPort,
                timeoutSeconds: timeoutSeconds)
            if clipProbe.reachable {
                let rttText = clipProbe.latencyMs.map { "\($0) ms" } ?? "Connected"
                stages.append(
                    StageResult(
                        id: "clipboard-port",
                        title: "MWB Clipboard Port (\(clipboardPort))",
                        status: .passed("Reachable (\(rttText))"),
                        latencyMs: clipProbe.latencyMs))
            } else {
                stages.append(
                    StageResult(
                        id: "clipboard-port",
                        title: "MWB Clipboard Port (\(clipboardPort))",
                        status: .failed(
                            clipProbe.detail
                                ?? "Port \(clipboardPort) blocked; clipboard & file sync will not work")))
            }
        }

        let summary = Self.summarize(stages: stages, protocolMode: protocolMode)
        return Report(host: trimmedHost, protocolMode: protocolMode, stages: stages, summary: summary)
    }

    public static func redact(logs: [String], securityKey: String) -> String {
        var joined = logs.joined(separator: "\n")
        let trimmed = securityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let spaceless = securityKey.replacingOccurrences(of: " ", with: "")
        for secret in [securityKey, trimmed, spaceless] where secret.count >= 4 {
            joined = joined.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        return joined
    }

    private static func validateKeyStage(
        protocolMode: MBProtocolMode,
        securityKey: String
    ) -> StageResult {
        let stripped = securityKey.replacingOccurrences(of: " ", with: "")
        if protocolMode == .mwbCompatibility {
            if stripped.count >= 16 {
                return StageResult(
                    id: "security-key",
                    title: "Security Key",
                    status: .passed("Valid (\(stripped.count) chars)"))
            }
            return StageResult(
                id: "security-key",
                title: "Security Key",
                status: .failed("MWB requires at least 16 non-space characters"))
        }

        if stripped.isEmpty {
            return StageResult(
                id: "security-key",
                title: "Security Key",
                status: .warning("Key is empty; set a matching key for HMAC authentication"))
        }
        return StageResult(
            id: "security-key",
            title: "Security Key",
            status: .passed("Configured (\(stripped.count) chars)"))
    }

    private static func summarize(stages: [StageResult], protocolMode: MBProtocolMode) -> String {
        if let firstFailure = stages.first(where: \.isError) {
            if case .failed(let message) = firstFailure.status {
                return "\(firstFailure.title): \(message)"
            }
        }
        return protocolMode == .mwbCompatibility
            ? "All checks passed. Ready for Mouse Without Borders."
            : "All checks passed. Ready for Modern Mac-to-Mac pairing."
    }

    private static func probeTCP(
        host: String,
        port: UInt16,
        timeoutSeconds: Double
    ) async -> ProbeOutcome {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return ProbeOutcome(reachable: false, latencyMs: nil, detail: "Invalid port \(port)")
        }

        let queue = DispatchQueue(label: "com.magicborder.doctor.probe")
        let connection = NWConnection(to: .hostPort(host: .init(host), port: nwPort), using: .tcp)
        let startedAt = CFAbsoluteTimeGetCurrent()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let finished = OSAllocatedUnfairLock(initialState: false)
                let complete: @Sendable (ProbeOutcome) -> Void = { outcome in
                    let shouldResume = finished.withLock { done -> Bool in
                        guard !done else { return false }
                        done = true
                        return true
                    }
                    if shouldResume {
                        connection.cancel()
                        continuation.resume(returning: outcome)
                    }
                }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let elapsedMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded()))
                        complete(ProbeOutcome(reachable: true, latencyMs: elapsedMs, detail: nil))
                    case .failed(let error):
                        complete(ProbeOutcome(reachable: false, latencyMs: nil, detail: error.localizedDescription))
                    case .waiting(let error):
                        complete(ProbeOutcome(reachable: false, latencyMs: nil, detail: error.localizedDescription))
                    case .cancelled:
                        complete(ProbeOutcome(reachable: false, latencyMs: nil, detail: "Cancelled"))
                    default:
                        break
                    }
                }

                queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                    complete(ProbeOutcome(reachable: false, latencyMs: nil, detail: "Timed out"))
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }
}
