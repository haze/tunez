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

    allocator: std.mem.Allocator,
    encoding: TextEncodingDescriptionByte,
    bytes: []const u8,

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self.encoding) {
            .ISO_8859_1 => try writer.writeAll(self.bytes),
            .UTF_16 => {
                var utf8_buf: [256]u8 = undefined;
                const utf8_buf_end = std.unicode.utf16leToUtf8(
                    &utf8_buf,
                    // TODO(haze): this is misaligned access
                    @intToPtr([*]const u16, @ptrToInt(self.bytes.ptr))[0 .. self.bytes.len / 2],
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
        const slice = try payload.allocator.alloc(u8, payload.bytes_left);

        _ = try reader.readAll(slice);

        return Self{
            .allocator = payload.allocator,
            .encoding = text_encoding,
            .bytes = slice,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};
