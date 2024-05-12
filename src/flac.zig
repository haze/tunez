const std = @import("std");
const metadata_block = @import("flac/metadata_block.zig");

pub fn Parser(comptime ReaderType: type) type {
    return struct {
        const Self = @This();

        const State = enum {
            reading_flac_header,
            reading_metadata_block,
            finished,
        };

        pub const Result = union(enum) {
            metadata_block: metadata_block.MetadataBlock,

            pub fn deinit(self: Result, allocator: std.mem.Allocator) void {
                switch (self) {
                    .metadata_block => |block| block.deinit(allocator),
                }
            }
        };

        reader: ReaderType,
        state: State = .reading_flac_header,
        allocator: std.mem.Allocator,

        pub fn nextItem(self: *Self) !?Result {
            while (self.state != .finished) {
                switch (self.state) {
                    .reading_flac_header => {
                        var magic_bytes: [4]u8 = undefined;
                        _ = try self.reader.readAll(&magic_bytes);
                        if (!std.mem.eql(u8, &magic_bytes, "fLaC")) return error.InvalidFlac;
                        self.state = .reading_metadata_block;
                    },
                    .reading_metadata_block => {
                        const block = try metadata_block.MetadataBlock.parse(self.reader, self.allocator);
                        if (block.header.is_last_block) {
                            self.state = .finished;
                        }
                        return Result{ .metadata_block = block };
                    },
                    .finished => unreachable,
                }
            }
            return null;
        }
    };
}

test {
    const file_contents = @embedFile("mario.flac");
    var stream = std.io.fixedBufferStream(file_contents);
    const reader = stream.reader();
    var parser = Parser(@TypeOf(reader)){
        .allocator = std.testing.allocator,
        .reader = reader,
    };

    while (try parser.nextItem()) |*item| {
        defer item.deinit(std.testing.allocator);
        std.log.warn("{}", .{item});
    }
}
