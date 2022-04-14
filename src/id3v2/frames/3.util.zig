const std = @import("std");

pub const TextEncodingDescriptionByte = enum(u8) {
    ISO_8859_1 = 0x00,
    UTF_16 = 0x01,

    pub fn parse(reader: anytype) !TextEncodingDescriptionByte {
        return @intToEnum(TextEncodingDescriptionByte, try reader.readByte());
    }
};

pub const String = struct {
    const Self = @This();
    const Storage = union(TextEncodingDescriptionByte) {
        ISO_8859_1: []u8,
        UTF_16: []u16,
    };

    allocator: std.mem.Allocator,
    encoding: TextEncodingDescriptionByte,
    storage: Storage,

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self.storage) {
            .ISO_8859_1 => |bytes| try writer.writeAll(bytes),
            .UTF_16 => |slice| {
                var utf8_buf: [256]u8 = undefined;
                const utf8_buf_end = std.unicode.utf16leToUtf8(
                    &utf8_buf,
                    slice,
                ) catch |err|
                    return writer.print("{}", .{err});
                try writer.writeAll(utf8_buf[0..utf8_buf_end]);
            },
        }
    }

    pub fn parse(reader: anytype, payload: struct {
        allocator: std.mem.Allocator,
        bytes_left: usize,
    }) !Self {
        const text_encoding = try TextEncodingDescriptionByte.parse(reader);
        const storage = blk: {
            switch (text_encoding) {
                .ISO_8859_1 => {
                    const slice = try payload.allocator.alloc(u8, payload.bytes_left);
                    _ = try reader.readAll(slice);
                    break :blk Storage{ .ISO_8859_1 = slice };
                },
                .UTF_16 => {
                    const slice = try payload.allocator.alloc(u16, payload.bytes_left / 2);
                    var read_index: usize = 0;
                    while (read_index < slice.len) : (read_index += 1) {
                        slice[read_index] = try reader.readIntLittle(u16);
                    }
                    break :blk Storage{ .UTF_16 = slice };
                },
            }
        };

        return Self{
            .allocator = payload.allocator,
            .encoding = text_encoding,
            .storage = storage,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};
