const std = @import("std");
const util = @import("4.util.zig");
const log = std.log.scoped(.id3v2_4_0);

pub const Payload = struct {
    allocator: std.mem.Allocator,
    frame_size: usize,
};

/// helper frames
pub const StringFrameOptions = struct {
    expect_language: bool = false,
};

pub fn StringFrame(comptime options: StringFrameOptions) type {
    return struct {
        const Self = @This();
        pub const String = util.String(.{ .expect_language = options.expect_language });

        value: String,

        pub fn parse(reader: anytype, payload: Payload) !Self {
            return Self{
                .value = try String.parse(reader, .{
                    .allocator = payload.allocator,
                    .bytes_left = payload.frame_size - 1,
                }),
            };
        }

        pub fn deinit(self: *Self) void {
            self.value.deinit();
            self.* = undefined;
        }
    };
}
