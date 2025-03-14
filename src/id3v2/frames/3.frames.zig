const util = @import("3.util.zig");
const std = @import("std");
const log = @import("3.zig").log;

pub const Payload = struct {
    allocator: std.mem.Allocator,
    frame_size: usize,
};

pub const TXXX = struct {
    const String = util.String(.{});
    allocator: std.mem.Allocator,

    encoding: util.TextEncodingDescriptionByte,
    maybe_utf16_byte_order: ?util.Unicode16ByteOrder,
    description: String.Storage,
    value: String.Storage,

    // TODO(haze): convert to string.asUtf8
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
                switch (self.maybe_utf16_byte_order.?) {
                    .Little => {
                        var desc_utf8_buf: [256]u8 = undefined;
                        var value_utf8_buf: [256]u8 = undefined;
                        const desc_utf8_buf_end = std.unicode.utf16leToUtf8(
                            &desc_utf8_buf,
                            self.description.UTF_16LE,
                        ) catch |err|
                            return writer.print("{}", .{err});
                        const value_utf8_buf_end = std.unicode.utf16leToUtf8(
                            &value_utf8_buf,
                            self.value.UTF_16LE,
                        ) catch |err|
                            return writer.print("{}", .{err});
                        const description = desc_utf8_buf[0..desc_utf8_buf_end];
                        const value = value_utf8_buf[0..value_utf8_buf_end];
                        try writer.print("(desc='{s}', value='{s}')", .{ description, value });
                    },
                    .Big => {
                        @panic("UTF16_BE printing not yet implemented");
                    },
                }
            },
        }
    }

    pub fn parse(reader: anytype, payload: Payload) !TXXX {
        const text_encoding_description_byte = try util.TextEncodingDescriptionByte.parse(reader);
        var maybe_utf16_byte_order: ?util.Unicode16ByteOrder = null;
        var bytes_left = payload.frame_size - 1;

        if (text_encoding_description_byte == .UTF_16) {
            maybe_utf16_byte_order = try util.Unicode16ByteOrder.parse(reader);
            bytes_left -= 2;
        }

        // first, we must read the bytes into a buffer. we then use this buffer to search for the
        // null byte separating the description and value and reinterpret the slices from there
        var bytes = try payload.allocator.alloc(u8, bytes_left);
        defer payload.allocator.free(bytes);

        _ = try reader.readAll(bytes);
        if (std.mem.indexOfScalar(u8, bytes, 0x00)) |separation_index| {
            var fbs = std.io.fixedBufferStream(bytes[0..separation_index]);
            const description_reader = fbs.reader();
            const description = try String.Storage.parse(description_reader, payload.allocator, text_encoding_description_byte, separation_index, maybe_utf16_byte_order);

            var value_fbs = std.io.fixedBufferStream(bytes[separation_index + 1 ..]);
            const value_reader = value_fbs.reader();
            const value = try String.Storage.parse(value_reader, payload.allocator, text_encoding_description_byte, separation_index, maybe_utf16_byte_order);

            return TXXX{
                .maybe_utf16_byte_order = maybe_utf16_byte_order,
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

    pub fn format(
        self: APIC,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("<image={s}; {} bytes: ({s})>", .{ self.mime_type, self.picture_data.len, self.description });
    }

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

                    var working_codepoint = try reader.readInt(u16, .little);

                    while (working_codepoint != 0x00) {
                        try codepoint_storage.append(working_codepoint);
                        working_codepoint = try reader.readInt(u16, .little);
                    }

                    const utf8_desc = try std.unicode.utf16LeToUtf8Alloc(payload.allocator, codepoint_storage.items);
                    break :blk utf8_desc;
                },
            }
        };

        const picture_data = try payload.allocator.alloc(u8, payload.frame_size - counting_reader.bytes_read);
        _ = try reader.readAll(picture_data);

        // var temp_file = try std.fs.cwd().createFile("image.png", .{});
        // defer temp_file.close();
        // var writer = temp_file.writer();
        // _ = try writer.writeAll(picture_data);

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
pub const StringFrameOptions = struct {
    expect_language: bool = false,
};
pub fn StringFrame(options: StringFrameOptions) type {
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

pub const BinaryBlobFrame = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: []const u8,

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        fmt_options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = fmt_options;
        try writer.print("<{} bytes>", .{self.data.len});
    }

    pub fn parse(reader: anytype, payload: Payload) !Self {
        const data = try payload.allocator.alloc(u8, payload.frame_size - 1);
        _ = try reader.readAll(data);
        return Self{
            .data = data,
            .allocator = payload.allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }
};

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
                try writer.print("{}/{?}", .{ self.value, self.second_half });
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
