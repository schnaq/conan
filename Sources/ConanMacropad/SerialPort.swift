import Foundation

/// A raw, non-blocking serial port. Callbacks run on the main queue.
final class SerialPort {
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?

    private let fd: Int32
    private let source: DispatchSourceRead
    private var closed = false

    init?(path: String) {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        var settings = termios()
        tcgetattr(fd, &settings)
        cfmakeraw(&settings)
        cfsetspeed(&settings, speed_t(B115200)) // ignored by USB CDC, set for completeness
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tcsetattr(fd, TCSANOW, &settings)

        self.fd = fd
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setCancelHandler { Darwin.close(fd) }
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.resume()
    }

    deinit { close() }

    func write(_ data: Data) {
        guard !closed else { return }
        let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        if written < 0 && errno != EAGAIN && errno != EINTR { close() }
    }

    func close() {
        guard !closed else { return }
        closed = true
        source.cancel()
        onClose?()
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 1024)
        let count = read(fd, &buffer, buffer.count)
        if count > 0 {
            onData?(Data(buffer[0..<count]))
        } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
            close() // unplugged
        }
    }
}
