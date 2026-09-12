import Foundation
import Testing
@testable import KaiLive

struct AudioPipelineTests {
    @Test
    func silenceHasZeroLevel() {
        #expect(AudioPipeline.level(of: Data(repeating: 0, count: 200)) == 0)
    }

    @Test
    func nonSilentPCMHasPositiveLevel() {
        var samples = [Int16](repeating: 8_000, count: 100)
        let data = Data(bytes: &samples, count: samples.count * MemoryLayout<Int16>.size)
        #expect(AudioPipeline.level(of: data) > 0)
    }
}
