const std = @import("std");
const util = @import("4.util.zig");
const log = std.log.scoped(.id3v2_4_0);

pub const Payload = struct {
    allocator: std.mem.Allocator,
    frame_size: usize,
};

/// helper frames
pub const SimpleStringFrame = struct {
    const Self = @This();

    value: util.String,

    pub fn parse(reader: anytype, payload: Payload) !Self {
        return Self{
            .value = try util.String.parse(reader, .{
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
