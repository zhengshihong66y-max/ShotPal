//
//  ExternalProcessRunner.swift
//  LapianBao
//
//  Centralizes short-lived external command execution.
//

import Darwin
import Foundation

nonisolated protocol ExternalProcessRegistry: AnyObject, Sendable {
    func set(_ process: Process?)
}

nonisolated enum ExternalProcessRunner {
    struct Result: Sendable {
        var terminationStatus: Int32?
        var didTimeOut = false
        var outputData = Data()
        var errorData = Data()

        var succeeded: Bool {
            terminationStatus == 0 && !didTimeOut
        }

        var outputText: String {
            String(data: outputData, encoding: .utf8) ?? ""
        }

        var errorText: String {
            String(data: errorData, encoding: .utf8) ?? ""
        }
    }

    static func run(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        qualityOfService: QualityOfService? = nil,
        timeout: TimeInterval? = nil,
        progressTick: (@Sendable (TimeInterval) -> Void)? = nil,
        outputLineHandler: (@Sendable (String) -> Void)? = nil,
        errorLineHandler: (@Sendable (String) -> Void)? = nil,
        processRegistry: ExternalProcessRegistry? = nil
    ) -> Result {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        if let qualityOfService {
            process.qualityOfService = qualityOfService
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputCollector = PipeDataCollector()
        let errorCollector = PipeDataCollector()
        let outputLineCollector = PipeLineCollector()
        let errorLineCollector = PipeLineCollector()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            outputCollector.append(data)
            for line in outputLineCollector.append(data) {
                outputLineHandler?(line)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            errorCollector.append(data)
            for line in errorLineCollector.append(data) {
                errorLineHandler?(line)
            }
        }

        do {
            try process.run()
        } catch {
            stopCollecting(
                outputPipe: outputPipe,
                errorPipe: errorPipe,
                outputCollector: outputCollector,
                errorCollector: errorCollector,
                outputLineCollector: outputLineCollector,
                errorLineCollector: errorLineCollector,
                outputLineHandler: outputLineHandler,
                errorLineHandler: errorLineHandler
            )
            return Result(
                terminationStatus: nil,
                outputData: outputCollector.data,
                errorData: Data(error.localizedDescription.utf8)
            )
        }

        processRegistry?.set(process)
        let didTimeOut = waitForExit(
            process,
            timeout: timeout,
            progressTick: progressTick
        )
        processRegistry?.set(nil)

        stopCollecting(
            outputPipe: outputPipe,
            errorPipe: errorPipe,
            outputCollector: outputCollector,
            errorCollector: errorCollector,
            outputLineCollector: outputLineCollector,
            errorLineCollector: errorLineCollector,
            outputLineHandler: outputLineHandler,
            errorLineHandler: errorLineHandler
        )

        return Result(
            terminationStatus: didTimeOut ? nil : process.terminationStatus,
            didTimeOut: didTimeOut,
            outputData: outputCollector.data,
            errorData: errorCollector.data
        )
    }

    static func waitForExit(
        _ process: Process,
        timeout: TimeInterval?,
        progressTick: (@Sendable (TimeInterval) -> Void)?
    ) -> Bool {
        guard let timeout else {
            process.waitUntilExit()
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        let waitStartedAt = Date()
        while true {
            let elapsed = Date().timeIntervalSince(waitStartedAt)
            let remaining = timeout - elapsed
            if remaining <= 0 {
                terminateTree(process)
                _ = semaphore.wait(timeout: .now() + 2)
                return true
            }
            if semaphore.wait(timeout: .now() + min(1, remaining)) == .success {
                return false
            }
            progressTick?(Date().timeIntervalSince(waitStartedAt))
        }
    }


    private static func stopCollecting(
        outputPipe: Pipe,
        errorPipe: Pipe,
        outputCollector: PipeDataCollector,
        errorCollector: PipeDataCollector,
        outputLineCollector: PipeLineCollector,
        errorLineCollector: PipeLineCollector,
        outputLineHandler: (@Sendable (String) -> Void)?,
        errorLineHandler: (@Sendable (String) -> Void)?
    ) {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        let outputData = drainAvailableData(from: outputPipe.fileHandleForReading)
        let errorData = drainAvailableData(from: errorPipe.fileHandleForReading)
        outputCollector.append(outputData)
        errorCollector.append(errorData)
        for line in outputLineCollector.finish(with: outputData) {
            outputLineHandler?(line)
        }
        for line in errorLineCollector.finish(with: errorData) {
            errorLineHandler?(line)
        }
    }

    private static func drainAvailableData(from handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        let originalFlags = fcntl(descriptor, F_GETFL, 0)
        if originalFlags >= 0 {
            _ = fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK)
        }
        defer {
            if originalFlags >= 0 {
                _ = fcntl(descriptor, F_SETFL, originalFlags)
            }
        }

        var data = Data()
        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 64 * 1024)
            } catch {
                break
            }
            guard let chunk, !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data
    }
}
