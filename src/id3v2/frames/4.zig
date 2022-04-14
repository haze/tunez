const impl = @import("4.impl.zig");
pub const FrameBody = union(enum) {
    TDRC: impl.TDRC,
};

// pub const Frame = struct {
//     pub const Header = struct {
//         // meant for the status messages flag byte
//         // (TagAlterPreservationFlagMask & FileAlterPreservationFlagMask): 1 = should discard, 0 = preserve
//         const TagAlterPreservationFlagMask = 0b10000000;
//         const FileAlterPreservationFlagMask = 0b01000000;
//         const ReadOnlyFlagMask = 0b0010000;
//
//         // meant for the encoding flag byte
//         const CompressionFlagMask = 0b10000000;
//         const EncryptionFlagMask = 0b01000000;
//         const GroupingIdentityFlagMask = 0b0010000;
//
//         id: [4]u8,
//         size: u32,
//         status_messages_flag: u8,
//         encoding_flag: u8,
//     };
//
//     pub const Body = union(enum) {
//         v2: versions.v2.FrameBody,
//         v3: versions.v3.FrameBody,
//         v4: versions.v4.FrameBody,
//     };
//
//     header: Header,
//     body: Body,
// };
