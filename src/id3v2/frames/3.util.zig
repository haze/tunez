const std = @import("std");

pub const Unicode16ByteOrder = enum {
    Big,
    Little,

    pub fn parse(reader: anytype) !Unicode16ByteOrder {
        var byte_order: [2]u8 = undefined;
        _ = try reader.readAll(&byte_order);
        if (byte_order[0] == 0xFE) return .Big else return .Little;
    }
};

pub const TextEncodingDescriptionByte = enum(u8) {
    ISO_8859_1 = 0x00,
    UTF_16 = 0x01,

    pub fn parse(reader: anytype) !TextEncodingDescriptionByte {
        return @intToEnum(TextEncodingDescriptionByte, try reader.readByte());
    }
};

pub const StringOptions = struct {
    expect_language: bool = false,
};
pub fn String(options: StringOptions) type {
    return struct {
        const Self = @This();
        pub const Storage = union(TextEncodingDescriptionByte) {
            ISO_8859_1: []u8,
            UTF_16: []u16,

            pub fn parse(reader: anytype, allocator: std.mem.Allocator, text_encoding: TextEncodingDescriptionByte, byte_count: usize) !Storage {
                switch (text_encoding) {
                    .ISO_8859_1 => {
                        const slice = try allocator.alloc(u8, byte_count);
                        _ = try reader.readAll(slice);
                        return Storage{ .ISO_8859_1 = slice };
                    },
                    .UTF_16 => {
                        const slice = try allocator.alloc(u16, byte_count / 2);
                        var read_index: usize = 0;
                        while (read_index < slice.len) : (read_index += 1) {
                            slice[read_index] = try reader.readIntLittle(u16);
                        }
                        return Storage{ .UTF_16 = slice };
                    },
                }
            }

            pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
                switch (self.*) {
                    .UTF_16 => |slice| allocator.free(slice),
                    .ISO_8859_1 => |bytes| allocator.free(bytes),
                }
                self.* = undefined;
            }
        };

        allocator: std.mem.Allocator,
        encoding: TextEncodingDescriptionByte,
        storage: Storage,
        language: if (options.expect_language) [3]u8 else void,

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            fmt_options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = fmt_options;
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
            var string = Self{
                .allocator = payload.allocator,
                .encoding = undefined,
                .storage = undefined,
                .language = undefined,
            };
            const text_encoding = try TextEncodingDescriptionByte.parse(reader);
            const bytes_left = blk: {
                if (options.expect_language) {
                    string.language[0] = try reader.readByte();
                    string.language[1] = try reader.readByte();
                    string.language[2] = try reader.readByte();
                    break :blk payload.bytes_left - 3;
                } else {
                    string.language = {};
                    break :blk payload.bytes_left;
                }
            };

            const storage = try Storage.parse(reader, payload.allocator, text_encoding, bytes_left);
            string.storage = storage;
            string.encoding = text_encoding;
            return string;
        }

        pub fn deinit(self: *Self) void {
            self.storage.deinit(self.allocator);
            self.* = undefined;
        }
    };
}
