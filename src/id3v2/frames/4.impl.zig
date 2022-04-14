const std = @import("std");
const util = @import("4.util.zig");
const log = std.log.scoped(.id3v2_4_0);

/// The 'Recording time' frame contains a timestamp describing when the
/// audio was recorded. Timestamp format is described in the ID3v2
/// structure document [ID3v2-strct].
pub const TDRC = struct {
    const ParseError = error{};

    timestamp: util.Timestamp,

    pub fn parse(reader: anytype) ParseError!TDRC {
        var text_encoding_description_byte = try util.TextEncodingDescriptionByte.parse(reader);
        log.info("text_encoding={}", .{text_encoding_description_byte});
        return TDRC{
            .timestamp = try util.Timestamp.parseUTF8(reader),
        };
    }

    // TODO(haze): include tests
};
