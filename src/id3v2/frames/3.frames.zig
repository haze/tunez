const util = @import("3.util.zig");
const std = @import("std");
const log = @import("3.zig").log;

pub const Payload = struct {
    allocator: std.mem.Allocator,
    frame_size: usize,
};

pub const TYER = struct {
    year: u16,

    pub fn parse(reader: anytype, _: Payload) !TYER {
        const text_encoding_description_byte = try util.TextEncodingDescriptionByte.parse(reader);
        switch (text_encoding_description_byte) {
            .ISO_8859_1 => {
                var year: [4]u8 = undefined;
                _ = try reader.readAll(&year);
                return TYER{ .year = try std.fmt.parseInt(u16, &year, 10) };
            },
            .UTF_16 => {
                const byte_order = try util.Unicode16ByteOrder.parse(reader);
                if (byte_order == .Big) return error.Utf16BeNotSupported;
                var utf8_year: [12]u8 = undefined;
                var utf16_year: [4]u16 = undefined;
                utf16_year[0] = try reader.readIntLittle(u16);
                utf16_year[1] = try reader.readIntLittle(u16);
                utf16_year[2] = try reader.readIntLittle(u16);
                utf16_year[3] = try reader.readIntLittle(u16);
                var utf8_end = try std.unicode.utf16leToUtf8(&utf8_year, &utf16_year);
                return TYER{ .year = try std.fmt.parseInt(u16, utf8_year[0..utf8_end], 10) };
            },
        }
    }
};

// TODO(haze): maybe use a stack based fallback allocator if some fields can get really long?
pub const TRCK = struct {
    track_index: u16,
    maybe_total_tracks: ?u16 = null,

    pub fn parse(reader: anytype, payload: Payload) !TRCK {
        const text_encoding_description_byte = try util.TextEncodingDescriptionByte.parse(reader);
        switch (text_encoding_description_byte) {
            .ISO_8859_1 => {
                var buf: [64]u8 = undefined;
                if (payload.frame_size > buf.len) {
                    log.warn("frame_size is bigger than stack buffer ({})", .{payload.frame_size});
                }
                const slice = buf[0 .. payload.frame_size - 1];
                _ = try reader.readAll(slice);
                if (std.mem.indexOfScalar(u8, slice, '/')) |separator_index| {
                    return TRCK{
                        .track_index = try std.fmt.parseInt(u16, slice[0..separator_index], 10),
                        .maybe_total_tracks = try std.fmt.parseInt(u16, slice[separator_index + 1 ..], 10),
                    };
                } else {
                    return TRCK{
                        .track_index = try std.fmt.parseInt(u16, slice, 10),
                    };
                }
                log.warn("{s}", .{slice});
            },
            else => return error.NotSupported,
        }
        return error.TODO;
    }
};

pub const TPOS = struct {
    part_index: u16,
    maybe_total_parts_in_set: ?u16 = null,

    pub fn parse(reader: anytype, payload: Payload) !TPOS {
        const text_encoding_description_byte = try util.TextEncodingDescriptionByte.parse(reader);
        switch (text_encoding_description_byte) {
            .ISO_8859_1 => {
                var buf: [64]u8 = undefined;
                if (payload.frame_size > buf.len) {
                    log.warn("frame_size is bigger than stack buffer ({})", .{payload.frame_size});
                }
                const slice = buf[0 .. payload.frame_size - 1];
                _ = try reader.readAll(slice);
                if (std.mem.indexOfScalar(u8, slice, '/')) |separator_index| {
                    return TPOS{
                        .part_index = try std.fmt.parseInt(u16, slice[0..separator_index], 10),
                        .maybe_total_parts_in_set = try std.fmt.parseInt(u16, slice[separator_index + 1 ..], 10),
                    };
                } else {
                    return TPOS{
                        .part_index = try std.fmt.parseInt(u16, slice, 10),
                    };
                }
                log.warn("{s}", .{slice});
            },
            else => return error.NotSupported,
        }
        return error.TODO;
    }
};

pub const TXXX = struct {
    const String = util.String(.{});
    allocator: std.mem.Allocator,

    encoding: util.TextEncodingDescriptionByte,
    description: String.Storage,
    value: String.Storage,

    pub fn format(
        self: TXXX,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        switch (self.encoding) {
            .ISO_8859_1 => {
                try writer.print("(desc='{s}', value='{s}')", .{ self.description.ISO_8859_1, self.value.ISO_8859_1 });
            },
            .UTF_16 => {
                var desc_utf8_buf: [256]u8 = undefined;
                var value_utf8_buf: [256]u8 = undefined;
                const desc_utf8_buf_end = std.unicode.utf16leToUtf8(
                    &desc_utf8_buf,
                    self.description.UTF_16,
                ) catch |err|
                    return writer.print("{}", .{err});
                const value_utf8_buf_end = std.unicode.utf16leToUtf8(
                    &value_utf8_buf,
                    self.value.UTF_16,
                ) catch |err|
                    return writer.print("{}", .{err});
                const description = desc_utf8_buf[0..desc_utf8_buf_end];
                const value = value_utf8_buf[0..value_utf8_buf_end];
                try writer.print("(desc='{s}', value='{s}')", .{ description, value });
            },
        }
    }

    pub fn parse(reader: anytype, payload: Payload) !TXXX {
        const text_encoding_description_byte = try util.TextEncodingDescriptionByte.parse(reader);

        // first, we must read the bytes into a buffer. we then use this buffer to search for the
        // null byte separating the description and value and reinterpret the slices from there
        var bytes = try payload.allocator.alloc(u8, payload.frame_size - 1);
        defer payload.allocator.free(bytes);

        _ = try reader.readAll(bytes);
        if (std.mem.indexOfScalar(u8, bytes, 0x00)) |separation_index| {
            var description_reader = std.io.fixedBufferStream(bytes[0..separation_index]).reader();
            var description = try String.Storage.parse(description_reader, payload.allocator, text_encoding_description_byte, separation_index);

            var value_reader = std.io.fixedBufferStream(bytes[separation_index + 1 ..]).reader();
            var value = try String.Storage.parse(value_reader, payload.allocator, text_encoding_description_byte, separation_index);

            return TXXX{
                .encoding = text_encoding_description_byte,
                .allocator = payload.allocator,
                .description = description,
                .value = value,
            };
        } else return error.InvalidTXXX;
    }

    pub fn deinit(self: *TXXX) void {
        self.description.deinit(self.allocator);
        self.value.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const PRIV = struct {
    allocator: std.mem.Allocator,
    owner_identifier: []const u8,
    private_data: []const u8,

    pub fn format(
        self: PRIV,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;
        try writer.print("owner_id='{s}', private_data=<{} bytes>", .{ self.owner_identifier, self.private_data.len });
    }

    pub fn parse(reader: anytype, payload: Payload) !PRIV {
        const owner_identifier = (try reader.readUntilDelimiterOrEofAlloc(payload.allocator, 0, 256)) orelse return error.InvalidPRIV;
        const private_data = try payload.allocator.alloc(u8, payload.frame_size - owner_identifier.len - 1);

        _ = try reader.readAll(private_data);

        return PRIV{
            .allocator = payload.allocator,
            .owner_identifier = owner_identifier,
            .private_data = private_data,
        };
    }

    pub fn deinit(self: *PRIV) void {
        self.allocator.free(self.owner_identifier);
        self.allocator.free(self.private_data);
        self.* = undefined;
    }
};

pub const APIC = struct {
    allocator: std.mem.Allocator,
    encoding: util.TextEncodingDescriptionByte,
    mime_type: []const u8,
    description: []const u8,
    picture_data: []const u8,
    picture_type: u8,

    pub fn parse(input_reader: anytype, payload: Payload) !APIC {
        var counting_reader = std.io.countingReader(input_reader);
        var reader = counting_reader.reader();

        const text_encoding_description_byte = try util.TextEncodingDescriptionByte.parse(reader);

        const mime_type = (try reader.readUntilDelimiterOrEofAlloc(payload.allocator, 0, 256)) orelse return error.InvalidAPIC;

        const picture_type = try reader.readByte();

        const description = blk: {
            switch (text_encoding_description_byte) {
                .ISO_8859_1 => {
                    const data = (try reader.readUntilDelimiterOrEofAlloc(payload.allocator, 0, 256)) orelse return error.InvalidAPIC;
                    break :blk data;
                },
                .UTF_16 => {
                    var codepoint_storage = std.ArrayList(u16).init(payload.allocator);
                    defer codepoint_storage.deinit();

                    var working_codepoint = try reader.readIntLittle(u16);

                    while (working_codepoint != 0x00) {
                        try codepoint_storage.append(working_codepoint);
                        working_codepoint = try reader.readIntLittle(u16);
                    }

                    const utf8_desc = try std.unicode.utf16leToUtf8Alloc(payload.allocator, codepoint_storage.items);
                    break :blk utf8_desc;
                },
            }
        };

        const picture_data = try payload.allocator.alloc(u8, payload.frame_size - counting_reader.bytes_read);
        _ = try reader.readAll(picture_data);

        var temp_file = try std.fs.cwd().createFile("image.png", .{});
        defer temp_file.close();
        var writer = temp_file.writer();
        _ = try writer.writeAll(picture_data);

        return APIC{
            .encoding = text_encoding_description_byte,
            .allocator = payload.allocator,
            .mime_type = mime_type,
            .picture_type = picture_type,
            .description = description,
            .picture_data = picture_data,
        };
    }

    pub fn deinit(self: *APIC) void {
        self.allocator.free(self.mime_type);
        self.allocator.free(self.description);
        self.allocator.free(self.picture_data);
        self.* = undefined;
    }
};

/// helper frames
pub const SimpleStringFrameOptions = struct {
    expect_language: bool = false,
};
pub fn SimpleStringFrame(options: SimpleStringFrameOptions) type {
    return struct {
        const Self = @This();
        const String = util.String(.{
            .expect_language = options.expect_language,
        });

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
