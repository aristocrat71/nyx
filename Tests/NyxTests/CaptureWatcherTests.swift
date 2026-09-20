import Testing
@testable import Nyx

@Suite("capture watcher")
struct CaptureWatcherTests {
    @Test func skyLightWatcherSymbolsResolve() {
        #expect(CaptureWatcher.isSupported)
    }
}
