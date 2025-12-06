// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin.C
#elseif canImport(Android)
    import Android
#else
    #error("Unsupported platform")
#endif

// MARK: - POSIXSerialPort

/// POSIX termios-based serial port implementation.
///
/// Supports macOS (Darwin), Linux (Glibc, Musl), and Android.
///
/// ## Thread Safety
///
/// This implementation is `@unchecked Sendable` because:
/// - File descriptor operations are atomic at OS level
/// - Users must ensure exclusive access (one request at a time)
/// - ModbusRTUClient handles serialization via actor
///
/// ## Platform Notes
///
/// - **Darwin**: Uses `/dev/cu.*` devices (no carrier detect wait)
/// - **Linux**: Uses `/dev/ttyUSB*` or `/dev/ttyS*` devices
/// - **Musl**: Limited to standard baud rates (B9600-B115200)
/// - **Android**: Uses `/dev/ttyUSB*` (requires root or USB permission)
///
/// Reference: POSIX termios(3), pymodbus serial transport
public final class POSIXSerialPort: SerialPort, @unchecked Sendable {
    // MARK: Lifecycle

    /// Creates a POSIX serial port for the given path.
    ///
    /// - Parameter path: Device path (e.g., "/dev/ttyUSB0", "/dev/cu.usbserial")
    public init(path: String) {
        self.path = path
        fileDescriptor = -1
    }

    deinit {
        if fileDescriptor >= 0 {
            // Best effort close, ignore errors
            _ = closeFileDescriptor(fileDescriptor)
        }
    }

    // MARK: Public

    /// Device path.
    public let path: String

    /// Whether the port is currently open.
    public var isOpen: Bool {
        get async {
            fileDescriptor >= 0
        }
    }

    /// Opens the serial port with the given configuration.
    ///
    /// - Parameter configuration: Serial port configuration
    /// - Throws: `SerialPortError` if open or configuration fails
    public func open(configuration: SerialConfiguration) async throws(SerialPortError) {
        guard fileDescriptor < 0 else {
            throw .alreadyOpen
        }

        // Validate path - must be absolute and start with /dev/
        // This prevents path traversal attacks (e.g., "../../../etc/passwd")
        guard path.hasPrefix("/dev/") else {
            throw .invalidPath(path: path)
        }

        // Reject paths with ".." to prevent directory traversal
        guard !path.contains("..") else {
            throw .invalidPath(path: path)
        }

        // Open with O_RDWR | O_NOCTTY | O_NONBLOCK
        // O_NOCTTY: Don't become controlling terminal
        // O_NONBLOCK: Don't block on open (some devices wait for carrier)
        let flags: Int32 = O_RDWR | O_NOCTTY | O_NONBLOCK
        let fd = openPath(path, flags)

        guard fd >= 0 else {
            throw .openFailed(path: path, errno: errno)
        }

        // Configure the port
        do {
            try configurePort(fd: fd, configuration: configuration)
        } catch {
            _ = closeFileDescriptor(fd)
            throw error
        }

        // Clear O_NONBLOCK after configuration - we want blocking reads
        // controlled by VMIN/VTIME, not by file descriptor flags
        var currentFlags = fcntl(fd, F_GETFL)
        if currentFlags >= 0 {
            currentFlags &= ~O_NONBLOCK
            _ = fcntl(fd, F_SETFL, currentFlags)
        }

        fileDescriptor = fd
        self.configuration = configuration
    }

    /// Closes the serial port.
    public func close() async {
        guard fileDescriptor >= 0 else {
            return
        }

        _ = closeFileDescriptor(fileDescriptor)
        fileDescriptor = -1
        configuration = nil
    }

    /// Reads bytes from the serial port.
    ///
    /// - Parameters:
    ///   - maxBytes: Maximum number of bytes to read
    ///   - timeout: Read timeout
    /// - Returns: Bytes read (may be less than maxBytes)
    /// - Throws: `SerialPortError` on failure or timeout
    public func read(maxBytes: Int, timeout: Duration) async throws(SerialPortError) -> [UInt8] {
        guard fileDescriptor >= 0 else {
            throw .notOpen
        }

        // Configure VMIN/VTIME for this read
        try configureReadTimeout(timeout: timeout)

        var buffer = [UInt8](repeating: 0, count: maxBytes)

        // Retry loop for EINTR (signal interruption)
        while true {
            let bytesRead = readFromFD(fileDescriptor, &buffer, maxBytes)

            if bytesRead < 0 {
                let err = errno
                if err == EINTR {
                    // Interrupted by signal - retry
                    continue
                }
                if err == EAGAIN || err == EWOULDBLOCK {
                    throw .readTimeout
                }
                throw .readFailed(errno: err)
            }

            if bytesRead == 0 {
                throw .readTimeout
            }

            return Array(buffer.prefix(bytesRead))
        }
    }

    /// Writes bytes to the serial port.
    ///
    /// - Parameters:
    ///   - bytes: Bytes to write
    ///   - timeout: Write timeout (currently not enforced at OS level)
    /// - Throws: `SerialPortError` on failure
    public func write(_ bytes: [UInt8], timeout _: Duration) async throws(SerialPortError) {
        guard fileDescriptor >= 0 else {
            throw .notOpen
        }

        var totalWritten = 0
        let count = bytes.count

        while totalWritten < count {
            let remaining = count - totalWritten
            let result = bytes.withUnsafeBufferPointer { ptr in
                writeToFD(fileDescriptor, ptr.baseAddress! + totalWritten, remaining)
            }

            if result < 0 {
                let err = errno
                if err == EINTR {
                    // Interrupted by signal - retry
                    continue
                }
                if err == EAGAIN || err == EWOULDBLOCK {
                    // Would block - yield and retry
                    await Task.yield()
                    continue
                }
                throw .writeFailed(errno: err)
            }

            totalWritten += result
        }
    }

    /// Discards all data in input and output buffers.
    public func flush() async throws(SerialPortError) {
        guard fileDescriptor >= 0 else {
            throw .notOpen
        }

        let result = tcflush(fileDescriptor, TCIOFLUSH)
        if result < 0 {
            throw .flushFailed(errno: errno)
        }
    }

    // MARK: Private

    private var fileDescriptor: Int32
    private var configuration: SerialConfiguration?

    /// Configures the serial port with termios.
    private func configurePort(
        fd: Int32,
        configuration: SerialConfiguration,
    ) throws(SerialPortError) {
        var settings = termios()

        // CRITICAL: Always get current settings first (never zero-initialize)
        guard tcgetattr(fd, &settings) == 0 else {
            throw .configurationFailed(errno: errno)
        }

        // Set baud rate
        let speed = try baudRateToSpeed(configuration.baudRate)
        cfsetispeed(&settings, speed)
        cfsetospeed(&settings, speed)

        // Control flags (c_cflag)
        // Clear size bits, then set
        settings.c_cflag &= ~tcflag_t(CSIZE)

        switch configuration.dataBits {
        case .seven:
            settings.c_cflag |= tcflag_t(CS7)
        case .eight:
            settings.c_cflag |= tcflag_t(CS8)
        }

        // Stop bits
        switch configuration.stopBits {
        case .one:
            settings.c_cflag &= ~tcflag_t(CSTOPB)
        case .two:
            settings.c_cflag |= tcflag_t(CSTOPB)
        }

        // Parity
        switch configuration.parity {
        case .none:
            settings.c_cflag &= ~tcflag_t(PARENB)
        case .even:
            settings.c_cflag |= tcflag_t(PARENB)
            settings.c_cflag &= ~tcflag_t(PARODD)
        case .odd:
            settings.c_cflag |= tcflag_t(PARENB | PARODD)
        }

        // Enable receiver, ignore modem control lines
        settings.c_cflag |= tcflag_t(CREAD | CLOCAL)

        // Disable hardware flow control (not used in Modbus RTU)
        #if os(Linux) || os(Android)
            settings.c_cflag &= ~tcflag_t(CRTSCTS)
        #elseif os(macOS)
            settings.c_cflag &= ~tcflag_t(CRTS_IFLOW | CCTS_OFLOW)
        #endif

        // Input flags (c_iflag) - disable all processing
        settings.c_iflag &= ~tcflag_t(
            IGNBRK | BRKINT | PARMRK | ISTRIP |
                INLCR | IGNCR | ICRNL | IXON | IXOFF | IXANY,
        )

        // Output flags (c_oflag) - raw output
        settings.c_oflag &= ~tcflag_t(OPOST)

        // Local flags (c_lflag) - disable canonical mode, echo, signals
        settings.c_lflag &= ~tcflag_t(ICANON | ECHO | ECHOE | ECHONL | ISIG)

        // Control characters (c_cc) - configure blocking behavior
        // VMIN = 1: Block until at least 1 byte available
        // VTIME = 0: No timeout (infinite wait)
        withUnsafeMutableBytes(of: &settings.c_cc) { buffer in
            buffer[Int(VMIN)] = 1
            buffer[Int(VTIME)] = 0
        }

        // Apply settings immediately
        guard tcsetattr(fd, TCSANOW, &settings) == 0 else {
            throw .configurationFailed(errno: errno)
        }
    }

    /// Configures read timeout via VMIN/VTIME.
    ///
    /// VTIME is in deciseconds (1/10 second), max 255 = 25.5 seconds.
    private func configureReadTimeout(timeout: Duration) throws(SerialPortError) {
        var settings = termios()
        guard tcgetattr(fileDescriptor, &settings) == 0 else {
            throw .configurationFailed(errno: errno)
        }

        // Convert Duration to deciseconds
        let totalNanos = timeout.components.seconds * 1_000_000_000 +
            timeout.components.attoseconds / 1_000_000_000
        let deciseconds = min(255, max(1, totalNanos / 100_000_000))

        withUnsafeMutableBytes(of: &settings.c_cc) { buffer in
            buffer[Int(VMIN)] = 0 // Don't require minimum bytes
            buffer[Int(VTIME)] = UInt8(deciseconds) // Timeout in deciseconds
        }

        guard tcsetattr(fileDescriptor, TCSANOW, &settings) == 0 else {
            throw .configurationFailed(errno: errno)
        }
    }

    /// Converts BaudRate enum to POSIX speed_t constant.
    private func baudRateToSpeed(_ baudRate: BaudRate) throws(SerialPortError) -> speed_t {
        switch baudRate {
        case .b300: return speed_t(B300)
        case .b600: return speed_t(B600)
        case .b1200: return speed_t(B1200)
        case .b2400: return speed_t(B2400)
        case .b4800: return speed_t(B4800)
        case .b9600: return speed_t(B9600)
        case .b19200: return speed_t(B19200)
        case .b38400: return speed_t(B38400)
        case .b57600: return speed_t(B57600)
        case .b115200: return speed_t(B115200)
        case .b230400:
            #if os(Linux) || os(Android)
                return speed_t(B230400)
            #else
                throw .unsupportedBaudRate(baudRate)
            #endif
        }
    }
}

// MARK: - POSIX Wrappers

// These wrappers avoid naming conflicts between Swift and C functions

@inline(__always)
private func openPath(_ path: String, _ flags: Int32) -> Int32 {
    path.withCString { cPath in
        open(cPath, flags)
    }
}

@inline(__always)
private func closeFileDescriptor(_ fd: Int32) -> Int32 {
    close(fd)
}

@inline(__always)
private func readFromFD(_ fd: Int32, _ buffer: UnsafeMutablePointer<UInt8>, _ count: Int) -> Int {
    read(fd, buffer, count)
}

@inline(__always)
private func writeToFD(_ fd: Int32, _ buffer: UnsafePointer<UInt8>, _ count: Int) -> Int {
    write(fd, buffer, count)
}
