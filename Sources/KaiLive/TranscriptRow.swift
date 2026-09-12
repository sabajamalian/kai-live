import Foundation

struct TranscriptRow: Identifiable, Equatable {
    enum Speaker: String {
        case user = "You"
        case assistant = "Kai"
    }

    let id = UUID()
    let speaker: Speaker
    var text: String
    let startMilliseconds: Int
    var endMilliseconds: Int
}
