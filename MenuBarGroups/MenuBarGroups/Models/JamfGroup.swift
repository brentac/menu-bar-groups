import Foundation

struct JamfGroup: Identifiable {
    let id: Int
    let name: String
    let memberCount: Int
    let type: GroupType

    enum GroupType: String {
        case computer
        case mobile
    }
}
