const std = @import("std");
const util = @import("4.util.zig");
const log = std.log.scoped(.id3v2_4_0);

pub const Payload = struct {
    allocator: std.mem.Allocator,
    frame_size: usize,
};

pub const TXXX = struct {
    const String = util.String(.{});

    allocator: std.mem.Allocator,
    text_encoding: util.TextEncodingDescriptionByte,

    description: String.Storage,
    value: String.Storage,

    original_string: String,

    pub fn parse(reader: anytype, payload: Payload) !TXXX {
        const string = try String.parse(reader, .{ .allocator = payload.allocator, .bytes_left = payload.frame_size - 1 });

        switch (string.storage) {
            .ISO_8859_1, .UTF_8 => |bytes| {
                if (std.mem.indexOfScalar(u8, bytes, 0x00)) |delimiter_index| {
                    if (string.storage == .UTF_8) {
                        return TXXX{
                            .allocator = payload.allocator,
                            .original_string = string,
                            .text_encoding = string.encoding,
                            .description = String.Storage{ .UTF_8 = bytes[0..delimiter_index] },
                            .value = String.Storage{ .UTF_8 = bytes[delimiter_index + 1 ..] },
                        };
                    } else {
                        return TXXX{
                            .allocator = payload.allocator,
                            .original_string = string,
                            .text_encoding = string.encoding,
                            .description = String.Storage{ .ISO_8859_1 = bytes[0..delimiter_index] },
                            .value = String.Storage{ .ISO_8859_1 = bytes[delimiter_index + 1 ..] },
                        };
                    }
                } else return error.InvalidTXXX;
            },
            .UTF_16LE, .UTF_16BE => |codepoints| {
                if (std.mem.indexOf(u16, codepoints, &[_]u16{ 0, 0 })) |delimiter_index| {
                    if (string.storage == .UTF_16LE) {
                        return TXXX{
                            .allocator = payload.allocator,
                            .original_string = string,
                            .text_encoding = string.encoding,
                            .description = String.Storage{ .UTF_16LE = codepoints[0..delimiter_index] },
                            .value = String.Storage{ .UTF_16LE = codepoints[delimiter_index + 1 ..] },
                        };
                    } else {
                        return TXXX{
                            .allocator = payload.allocator,
                            .original_string = string,
                            .text_encoding = string.encoding,
                            .description = String.Storage{ .UTF_16BE = codepoints[0..delimiter_index] },
                            .value = String.Storage{ .UTF_16BE = codepoints[delimiter_index + 1 ..] },
                        };
                    }
                } else return error.InvalidTXXX;
            },
        }
    }

    pub fn deinit(self: *TXXX) void {
        self.original_string.deinit();
        self.* = undefined;
    }
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

pub const NumericStringFrameOptions = struct {
    maybe_delimiter_char: ?u8 = null,
    radix: u8 = 10,
};

pub fn NumericStringFrame(comptime IntType: type, options: NumericStringFrameOptions) type {
    return struct {
        const Self = @This();

        value: IntType,
        second_half: if (options.maybe_delimiter_char != null) ?IntType else void = if (options.maybe_delimiter_char != null) null else {},

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            fmt_options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = fmt_options;
            if (options.maybe_delimiter_char != null) {
                try writer.print("{}/{}", .{ self.value, self.second_half });
            } else {
                try writer.print("{}", .{self.value});
            }
        }

        pub fn parse(reader: anytype, payload: Payload) !Self {
            var string = try util.String(.{}).parse(reader, .{
                .allocator = payload.allocator,
                .bytes_left = payload.frame_size - 1,
            });
            defer string.deinit();

            var stack_fallback_allocator = std.heap.stackFallback(128, payload.allocator);
            var utf8_string = try string.asUtf8(stack_fallback_allocator.get());
            defer utf8_string.deinit();

            const utf8_bytes = std.mem.trimRight(u8, utf8_string.bytes, "\x00");

            if (options.maybe_delimiter_char) |delimiter| {
                if (std.mem.indexOfScalar(u8, utf8_bytes, delimiter)) |delimiter_index| {
                    return Self{
                        .value = try std.fmt.parseInt(IntType, utf8_bytes[0..delimiter_index], options.radix),
                        .second_half = try std.fmt.parseInt(IntType, utf8_bytes[delimiter_index + 1 ..], options.radix),
                    };
                }
            }
            return Self{
                .value = try std.fmt.parseInt(IntType, utf8_bytes, options.radix),
            };
        }
    };
}
