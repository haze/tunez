const std = @import("std");
const logger = std.log.scoped(.id3v2_4_0_util);

const shared = @import("shared.zig");

pub const Unicode16ByteOrder = shared.Unicode16ByteOrder;

pub const TextEncodingDescriptionByte = enum(u8) {
    ISO_8859_1 = 0x00,
    // with BOM
    UTF_16 = 0x01,
    // without BOM
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

    pub fn format(
        self: Timestamp,
        comptime fmt: []const u8,
        fmt_options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = fmt_options;
        try writer.print("{}", .{self.year});
        if (self.maybe_month) |month| {
            try writer.print("-{}", .{@enumToInt(month)});
        }
        if (self.maybe_day) |day| {
            try writer.print("-{}", .{day});
        }
        if (self.maybe_hour) |hour| {
            try writer.print("T{}", .{hour});
        }
        if (self.maybe_minutes) |minutes| {
            try writer.print(":{}", .{minutes});
        }
        if (self.maybe_seconds) |seconds| {
            try writer.print(":{}", .{seconds});
        }
    }

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

    // TODO(haze): durations?
    pub fn parseUtf8(reader: anytype, bytes_left: usize) !Timestamp {
        const LongestPossibleTimestamp = "yyyy-MM-ddTHH:mm:ss";
        var timestamp_buf: [LongestPossibleTimestamp.len]u8 = undefined;
        const bytes_read = try reader.readAll(timestamp_buf[0..bytes_left]);

        var section_iter = std.mem.tokenize(u8, timestamp_buf[0..bytes_read], "-");
        const year_str = section_iter.next() orelse return error.InvalidTimestampMissingYear;
        var timestamp = Timestamp{
            .year = try std.fmt.parseInt(u16, year_str, 10),
        };
        timestamp.maybe_month = @intToEnum(
            Month,
            try std.fmt.parseInt(
                @typeInfo(Month).Enum.tag_type,
                section_iter.next() orelse return timestamp,
                10,
            ),
        );
        const maybe_day_and_time = section_iter.next();

        if (maybe_day_and_time) |day_and_time| {
            const day_time_sep = std.mem.indexOfScalar(u8, day_and_time, 'T') orelse return error.InvalidTimestampMissingHourForDay;
            timestamp.maybe_day = try std.fmt.parseInt(u5, day_and_time[0..day_time_sep], 10);
            const time = day_and_time[day_time_sep + 1 ..];
            var time_section_iter = std.mem.tokenize(u8, time, ":");
            timestamp.maybe_hour = try std.fmt.parseInt(u5, time_section_iter.next() orelse return error.InvalidTimestampMissingHours, 10);
            if (time_section_iter.next()) |minutes| {
                timestamp.maybe_minutes = try std.fmt.parseInt(u6, minutes, 10);
            }
            if (time_section_iter.next()) |seconds| {
                timestamp.maybe_seconds = try std.fmt.parseInt(u6, seconds, 10);
            }
        }

        return timestamp;
    }

    pub fn parseUtf8FromSlice(slice: []const u8) !Timestamp {
        var reader = std.io.fixedBufferStream(slice).reader();
        return Timestamp.parseUtf8(reader, slice.len);
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
        pub const Storage = union(enum) {
            ISO_8859_1: []u8,
            UTF_8: []u8,
            UTF_16: []u16,

            pub fn parse(reader: anytype, allocator: std.mem.Allocator, text_encoding: TextEncodingDescriptionByte, input_byte_count: usize) !Storage {
                switch (text_encoding) {
                    .ISO_8859_1, .UTF_8 => {
                        const slice = try allocator.alloc(u8, input_byte_count);
                        _ = try reader.readAll(slice);
                        if (text_encoding == .UTF_8) {
                            return Storage{ .UTF_8 = slice };
                        } else {
                            return Storage{ .ISO_8859_1 = slice };
                        }
                    },
                    .UTF_16, .UTF_16BE => {
                        var byte_order: Unicode16ByteOrder = .Big;
                        var byte_count = input_byte_count;
                        if (text_encoding == .UTF_16) {
                            byte_order = try Unicode16ByteOrder.parse(reader);
                            byte_count -= 2;
                        }
                        const slice = try allocator.alloc(u16, byte_count / 2);
                        var read_index: usize = 0;
                        if (byte_order == .Big) {
                            while (read_index < slice.len) : (read_index += 1) {
                                slice[read_index] = try reader.readIntBig(u16);
                            }
                        } else {
                            while (read_index < slice.len) : (read_index += 1) {
                                slice[read_index] = try reader.readIntLittle(u16);
                            }
                        }
                        return Storage{ .UTF_16 = slice };
                    },
                }
            }

            pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
                switch (self.*) {
                    .UTF_16 => |slice| allocator.free(slice),
                    .ISO_8859_1, .UTF_8 => |bytes| allocator.free(bytes),
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

            var fmt_buffer: [128]u8 = undefined;
            var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(&fmt_buffer);

            var utf8_string = self.asUtf8(fixed_buffer_allocator.allocator()) catch |err| {
                try writer.print("<error occured trying to get get utf8 view: {}>", .{err});
                return;
            };
            defer utf8_string.deinit();

            try writer.print("{s}", .{utf8_string.bytes});
        }

        pub const Utf8String = struct {
            bytes: []const u8,
            maybe_allocator: ?std.mem.Allocator = null,

            pub fn deinit(self: *Utf8String) void {
                if (self.maybe_allocator) |allocator|
                    allocator.free(self.bytes);
                self.* = undefined;
            }
        };

        pub fn asUtf8(self: Self, maybe_allocator: ?std.mem.Allocator) !Utf8String {
            switch (self.storage) {
                .ISO_8859_1, .UTF_8 => |bytes| {
                    return Utf8String{
                        .bytes = bytes,
                    };
                },
                .UTF_16 => |codepoints| {
                    var bytes = try std.unicode.utf16leToUtf8Alloc(maybe_allocator orelse return error.MissingAllocator, codepoints);
                    return Utf8String{
                        .bytes = bytes,
                        .maybe_allocator = maybe_allocator,
                    };
                },
            }
        }

        pub const StringParsePayload = struct {
            maybe_known_encoding: ?TextEncodingDescriptionByte = null,
            allocator: std.mem.Allocator,
            bytes_left: usize,
        };

        pub fn parse(reader: anytype, payload: StringParsePayload) !Self {
            const text_encoding =
                if (payload.maybe_known_encoding) |known_encoding|
                known_encoding
            else
                try TextEncodingDescriptionByte.parse(reader);
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
