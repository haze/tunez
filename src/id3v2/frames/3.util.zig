const std = @import("std");
const shared = @import("shared.zig");

pub const Unicode16ByteOrder = shared.Unicode16ByteOrder;

pub const TextEncodingDescriptionByte = enum(u8) {
    ISO_8859_1 = 0x00,
    UTF_16 = 0x01,

    pub fn parse(reader: anytype) !TextEncodingDescriptionByte {
        return try std.meta.intToEnum(TextEncodingDescriptionByte, try reader.readByte());
    }
};

pub const StringOptions = struct {
    expect_language: bool = false,
};

pub const Utf8String = struct {
    bytes: []u8,
    maybe_allocator: ?std.mem.Allocator = null,

    pub fn deinit(self: *Utf8String) void {
        if (self.maybe_allocator) |allocator|
            allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub fn String(options: StringOptions) type {
    return struct {
        const Self = @This();

        pub const Storage = union(enum) {
            ISO_8859_1: []u8,
            UTF_16BE: []u16,
            UTF_16LE: []u16,

            pub fn parse(
                reader: anytype,
                allocator: std.mem.Allocator,
                text_encoding: TextEncodingDescriptionByte,
                byte_count: usize,
                maybe_utf16_byte_order: ?Unicode16ByteOrder,
            ) !Storage {
                switch (text_encoding) {
                    .ISO_8859_1 => {
                        const slice = try allocator.alloc(u8, byte_count);
                        _ = try reader.readAll(slice);
                        return Storage{ .ISO_8859_1 = slice };
                    },
                    .UTF_16 => {
                        const slice = try allocator.alloc(u16, byte_count / 2);
                        var read_index: usize = 0;
                        switch (maybe_utf16_byte_order.?) {
                            .Little => {
                                while (read_index < slice.len) : (read_index += 1) {
                                    slice[read_index] = try reader.readInt(u16, .little);
                                }
                                return Storage{ .UTF_16LE = slice };
                            },
                            .Big => {
                                while (read_index < slice.len) : (read_index += 1) {
                                    slice[read_index] = try reader.readInt(u16, .big);
                                }
                                return Storage{ .UTF_16BE = slice };
                            },
                        }
                    },
                }
            }

            pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
                switch (self.*) {
                    .UTF_16LE, .UTF_16BE => |slice| allocator.free(slice),
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

            var fmt_buffer: [128]u8 = undefined;
            var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&fmt_buffer);

            var utf8_string = self.asUtf8(fixed_buffer_allocator.allocator()) catch |err| {
                try writer.print("<error occured trying to get get utf8 view: {}>", .{err});
                return;
            };
            defer utf8_string.deinit();

            try writer.print("{s}", .{utf8_string.bytes});
        }

        pub const ParseOptions = struct {
            allocator: std.mem.Allocator,
            bytes_left: usize,
        };

        pub fn parse(reader: anytype, payload: ParseOptions) !Self {
            var string = Self{
                .allocator = payload.allocator,
                .encoding = undefined,
                .storage = undefined,
                .language = undefined,
            };
            const text_encoding = try TextEncodingDescriptionByte.parse(reader);
            var maybe_utf16_byte_order: ?Unicode16ByteOrder = null;
            var bytes_left = payload.bytes_left;

            if (text_encoding == .UTF_16) {
                maybe_utf16_byte_order = try Unicode16ByteOrder.parse(reader);
                bytes_left -= 2;
            }

            if (options.expect_language) {
                string.language[0] = try reader.readByte();
                string.language[1] = try reader.readByte();
                string.language[2] = try reader.readByte();
                bytes_left -= 3;
            } else {
                string.language = {};
            }

            const storage = try Storage.parse(reader, payload.allocator, text_encoding, bytes_left, maybe_utf16_byte_order);
            string.storage = storage;
            string.encoding = text_encoding;
            return string;
        }

        /// Cannot fail if string is ISO_8859_1
        pub fn asUtf8(self: Self, allocator: std.mem.Allocator) !Utf8String {
            switch (self.storage) {
                .ISO_8859_1 => |bytes| return Utf8String{
                    .bytes = bytes,
                },
                .UTF_16LE => |utf16_codepoints| {
                    const bytes = try std.unicode.utf16LeToUtf8Alloc(allocator, utf16_codepoints);
                    return Utf8String{
                        .bytes = bytes,
                        .maybe_allocator = allocator,
                    };
                },
                .UTF_16BE => |utf16_codepoints| {
                    _ = utf16_codepoints;
                    @panic("UTF16_BE to UTF8 not yet implemented");
                },
            }
        }

        pub fn deinit(self: *Self) void {
            self.storage.deinit(self.allocator);
            self.* = undefined;
        }
    };
}
