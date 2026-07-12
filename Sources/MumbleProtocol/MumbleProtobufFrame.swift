import Foundation
import SwiftProtobuf

public extension MumbleFrame {
    init<Message: SwiftProtobuf.Message>(
        type: MumbleMessageType,
        message: Message
    ) throws {
        self.init(type: type, payload: try message.serializedData())
    }

    func decode<Message: SwiftProtobuf.Message>(
        as type: Message.Type
    ) throws -> Message {
        try Message(serializedBytes: payload)
    }
}
