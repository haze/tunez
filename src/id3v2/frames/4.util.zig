const std = @import("std");
const logger = std.log.scoped(.id3v2_4_0_util);

pub const TextEncodingDescriptionByte = enum(u8) {
    ISO_8859_1 = 0x00,
    UTF_16 = 0x01,
    UTF_16BE = 0x02,
    UTF_8 = 0x03,

    pub fn parse(reader: anytype) !TextEncodingDescriptionByte {
        return @intToEnum(TextEncodingDescriptionByte, try reader.readByte());
    }
};

pub const Timestamp = struct {
    pub const Month = enum { january, febuary, march, april, may, june, july, august, september, october, november, december };
    year: u16,
    maybe_month: ?Month = null,
    maybe_day: ?u5 = null,
    maybe_hour: ?u5 = null,
    maybe_minutes: ?u6 = null,
    maybe_seconds: ?u6 = null,

    pub fn eql(self: Timestamp, other: Timestamp) bool {
        if (self.year != other.year) return false;
        if (self.maybe_month) |self_month|
            if (other.maybe_month) |other_month| {
                if (self_month != other_month) {
                    return false;
                }
            } else return false;
        if (self.maybe_day) |self_day|
            if (other.maybe_day) |other_day| {
                if (self_day != other_day) {
                    return false;
                }
            } else return false;
        if (self.maybe_hour) |self_hour|
            if (other.maybe_hour) |other_hour| {
                if (self_hour != other_hour) {
                    return false;
                }
            } else return false;
        if (self.maybe_minutes) |self_minutes|
            if (other.maybe_minutes) |other_minutes| {
                if (self_minutes != other_minutes) {
                    return false;
                }
            } else return false;
        if (self.maybe_seconds) |self_seconds|
            if (other.maybe_seconds) |other_seconds| {
                if (self_seconds != other_seconds) {
                    return false;
                }
            } else return false;
        return true;
    }

    pub fn parseUtf8(reader: anytype) !Timestamp {
        var year_buf: [4]u8 = undefined;
        _ = try reader.read(&year_buf);
        var working_timestamp = Timestamp{
            .year = try std.fmt.parseInt(u16, &year_buf, 10),
        };
        return working_timestamp;
    }

    pub fn parseUtf8FromSlice(slice: []const u8) !Timestamp {
        var reader = std.io.fixedBufferStream(slice).reader();
        return Timestamp.parseUtf8(reader);
    }

    test "parse" {
        try std.testing.expect((Timestamp{ .year = 2020 }).eql(Timestamp.parseUtf8FromSlice("2020") catch unreachable));
    }
};

pub const StringOptions = struct {
    expect_language: bool = false,
};

pub fn String(comptime options: StringOptions) type {
    _ = options;
    return struct {
        const Self = @This();
        pub const Storage = union(TextEncodingDescriptionByte) {
            ISO_8859_1: []u8,
            UTF_16: []u16,
            UTF_16BE: []u16,
            UTF_8: []u8,

            pub fn parse(reader: anytype, allocator: std.mem.Allocator, text_encoding: TextEncodingDescriptionByte, byte_count: usize) !Storage {
                switch (text_encoding) {
                    .ISO_8859_1, .UTF_8 => {
                        const slice = try allocator.alloc(u8, byte_count);
                        _ = try reader.readAll(slice);
                        return Storage{ .ISO_8859_1 = slice };
                    },
                    .UTF_16, .UTF_16BE => {
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

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            fmt_options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = fmt_options;
            switch (self.storage) {
                .ISO_8859_1, .UTF_8 => |bytes| try writer.writeAll(bytes),
                .UTF_16BE => @panic("utf16_be printing not implemented"),
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
            const storage = try Storage.parse(reader, payload.allocator, text_encoding, payload.bytes_left);

            return Self{
                .allocator = payload.allocator,
                .encoding = text_encoding,
                .storage = storage,
            };
        }

        pub fn deinit(self: *Self) void {
            self.storage.deinit(self.allocator);
            self.* = undefined;
        }
    };
}
