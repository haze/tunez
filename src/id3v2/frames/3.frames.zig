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
            else => return error.NotSupported,
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
    allocator: std.mem.Allocator,

    encoding: util.TextEncodingDescriptionByte,
    description: []const u8,
    value: []const u8,

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
                try writer.print("(desc='{s}', value='{s}')", .{ self.description, self.value });
            },
            .UTF_16 => {
                var desc_utf8_buf: [256]u8 = undefined;
                var value_utf8_buf: [256]u8 = undefined;
                const desc_utf8_buf_end = std.unicode.utf16leToUtf8(
                    &desc_utf8_buf,
                    @ptrCast([*]const u16, @alignCast(@alignOf([*]const u16), self.description.ptr))[0 .. self.description.len / 2],
                ) catch |err|
                    return writer.print("{}", .{err});
                const value_utf8_buf_end = std.unicode.utf16leToUtf8(
                    &value_utf8_buf,
                    @ptrCast([*]const u16, @alignCast(@alignOf([*]const u16), self.value.ptr))[0 .. self.value.len / 2],
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

        const slice = try payload.allocator.alloc(u8, payload.frame_size - 1);
        defer payload.allocator.free(slice);

        _ = try reader.readAll(slice);

        if (std.mem.indexOfScalar(u8, slice, '\x00')) |separation_index| {
            return TXXX{
                .encoding = text_encoding_description_byte,
                .allocator = payload.allocator,
                .description = try payload.allocator.dupe(u8, slice[0..separation_index]),
                .value = try payload.allocator.dupe(u8, slice[separation_index + 1 ..]),
            };
        } else return error.InvalidTXXX;
    }

    pub fn deinit(self: *TXXX) void {
        self.allocator.free(self.description);
        self.allocator.free(self.value);
        self.* = undefined;
    }
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
