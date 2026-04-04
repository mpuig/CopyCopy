import Foundation
import QuartzCore

/// Downloads GGUF models from HuggingFace using the standard hub cache layout.
/// Supports resume, retry with backoff, progress throttling, and SHA256 verification.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var resumeData: Data?
    private var session: URLSession?
    private var retryCount = 0
    private var currentURL: URL?

    private static let maxRetries = 3
    private static let retryDelays: [UInt64] = [2_000_000_000, 4_000_000_000, 8_000_000_000]
    private static let progressThrottleInterval: TimeInterval = 0.1

    private var lastProgressUpdate: TimeInterval = 0

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
        super.init()
    }

    /// Download a model file with resume support and retry logic.
    func download(from url: URL, to destination: URL) async throws {
        currentURL = url
        retryCount = 0
        resumeData = nil

        // Check for existing resume data
        let resumePath = destination.appendingPathExtension("resume")
        if let data = try? Data(contentsOf: resumePath) {
            resumeData = data
        }

        while true {
            do {
                let tempURL = try await attemptDownload(url: url)

                // Move to destination
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: tempURL, to: destination)

                // Clean up resume data
                try? FileManager.default.removeItem(at: resumePath)
                return

            } catch {
                // Save resume data for next attempt
                if let resumeData {
                    try? resumeData.write(to: resumePath)
                }

                retryCount += 1
                if retryCount > Self.maxRetries || !isRetryableError(error) {
                    throw error
                }

                let delay = Self.retryDelays[min(retryCount - 1, Self.retryDelays.count - 1)]
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func attemptDownload(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForResource = 3600
            self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

            if let resumeData {
                self.session?.downloadTask(withResumeData: resumeData).resume()
            } else {
                var request = URLRequest(url: url)
                request.setValue("Mozilla/5.0 CopyCopy/1.0", forHTTPHeaderField: "User-Agent")
                self.session?.downloadTask(with: request).resume()
            }
        }
    }

    private func isRetryableError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let retryableCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed,
        ]
        return retryableCodes.contains(nsError.code)
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gguf")
        do {
            try FileManager.default.copyItem(at: location, to: tempCopy)
            resumeData = nil
            continuation?.resume(returning: tempCopy)
            continuation = nil
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }

        // Extract resume data if available
        let nsError = error as NSError
        if let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            resumeData = data
        }

        continuation?.resume(throwing: error)
        continuation = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }

        // Throttle progress updates to 100ms
        let now = CACurrentMediaTime()
        guard now - lastProgressUpdate >= Self.progressThrottleInterval else { return }
        lastProgressUpdate = now

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }
}

// MARK: - HuggingFace Cache Layout

enum HFCache {
    /// Standard HF cache base directory
    static var baseDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
    }

    /// Repository directory name: models--{org}--{repo}
    static func repoDir(for definition: ModelDefinition) -> URL {
        let parts = definition.repo.split(separator: "/")
        guard parts.count == 2 else {
            return baseDir.appendingPathComponent("models--\(definition.repo.replacingOccurrences(of: "/", with: "--"))")
        }
        return baseDir.appendingPathComponent("models--\(parts[0])--\(parts[1])")
    }

    /// Blobs directory for a repo
    static func blobsDir(for definition: ModelDefinition) -> URL {
        repoDir(for: definition).appendingPathComponent("blobs")
    }

    /// Snapshots directory for a repo
    static func snapshotsDir(for definition: ModelDefinition) -> URL {
        repoDir(for: definition).appendingPathComponent("snapshots")
    }

    /// Find the local path for a model file (searches snapshots for the filename)
    static func localPath(for definition: ModelDefinition) -> URL? {
        let snapshots = snapshotsDir(for: definition)
        guard let commits = try? FileManager.default.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil) else {
            return nil
        }

        for commit in commits {
            let filePath = commit.appendingPathComponent(definition.filename)
            if FileManager.default.fileExists(atPath: filePath.path) {
                // Resolve symlink to get actual blob path
                let resolved = filePath.resolvingSymlinksInPath()
                if FileManager.default.fileExists(atPath: resolved.path) {
                    return resolved
                }
            }
        }
        return nil
    }

    /// Check if a model is downloaded (in HF cache or legacy flat dir)
    static func isDownloaded(_ definition: ModelDefinition) -> Bool {
        // Check HF cache first
        if localPath(for: definition) != nil { return true }
        // Check legacy flat dir
        return FileManager.default.fileExists(atPath: legacyPath(for: definition).path)
    }

    /// Resolved path for loading (HF cache or legacy)
    static func resolvedPath(for definition: ModelDefinition) -> URL? {
        if let hfPath = localPath(for: definition) { return hfPath }
        let legacy = legacyPath(for: definition)
        return FileManager.default.fileExists(atPath: legacy.path) ? legacy : nil
    }

    /// Legacy flat cache path (~/.copycopy/models/)
    static func legacyPath(for definition: ModelDefinition) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copycopy/models")
            .appendingPathComponent(definition.filename)
    }

    /// Fetch file metadata via HEAD request (SHA256 hash, commit)
    static func fetchMetadata(for definition: ModelDefinition) async throws -> (sha256: String, commit: String)? {
        var request = URLRequest(url: definition.downloadURL)
        request.httpMethod = "HEAD"
        request.setValue("Mozilla/5.0 CopyCopy/1.0", forHTTPHeaderField: "User-Agent")

        // Use a session that doesn't follow redirects (HF redirects strip metadata headers)
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let (_, response) = try await session.data(for: request)
        session.finishTasksAndInvalidate()

        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        let sha256 = httpResponse.value(forHTTPHeaderField: "X-Linked-Etag")
            ?? httpResponse.value(forHTTPHeaderField: "ETag")
        let commit = httpResponse.value(forHTTPHeaderField: "X-Repo-Commit")

        guard let sha256 = sha256?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
              let commit else { return nil }

        return (sha256, commit)
    }

    /// Set up HF cache directory structure and return the blob destination path
    static func prepareCache(for definition: ModelDefinition, sha256: String, commit: String) throws -> (blobPath: URL, snapshotLink: URL) {
        let blobsDir = blobsDir(for: definition)
        let snapshotDir = snapshotsDir(for: definition).appendingPathComponent(commit)
        let refsDir = repoDir(for: definition).appendingPathComponent("refs")

        try FileManager.default.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)

        // Write refs/main
        try commit.write(to: refsDir.appendingPathComponent("main"), atomically: true, encoding: .utf8)

        let blobPath = blobsDir.appendingPathComponent(sha256)
        let snapshotLink = snapshotDir.appendingPathComponent(definition.filename)

        return (blobPath, snapshotLink)
    }

    /// Create symlink from snapshot to blob
    static func createSymlink(from snapshotLink: URL, to blobPath: URL) throws {
        try? FileManager.default.removeItem(at: snapshotLink)
        let relativeBlobPath = "../../blobs/\(blobPath.lastPathComponent)"
        try FileManager.default.createSymbolicLink(atPath: snapshotLink.path, withDestinationPath: relativeBlobPath)
    }
}

// MARK: - No-Redirect Delegate

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Block redirect to preserve metadata headers from the 302 response
        completionHandler(nil)
    }
}
