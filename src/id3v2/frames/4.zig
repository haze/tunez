const std = @import("std");
const frames = @import("4.frames.zig");
pub const log = std.log.scoped(.id3v2_4);

// TODO(haze): these should get their own custom frames:
//  TLAN
pub const Frame = union(enum) {
    TIT1: frames.StringFrame(.{}),
    TIT2: frames.StringFrame(.{}),
    TIT3: frames.StringFrame(.{}),
    TALB: frames.StringFrame(.{}),
    TOAL: frames.StringFrame(.{}),
    TRCK: frames.NumericStringFrame(u16, .{ .maybe_delimiter_char = '/' }),
    TPOS: frames.NumericStringFrame(u16, .{ .maybe_delimiter_char = '/' }),
    TSST: frames.StringFrame(.{}),
    TSRC: frames.StringFrame(.{}),
    TPE1: frames.StringFrame(.{}),
    TPE2: frames.StringFrame(.{}),
    TPE3: frames.StringFrame(.{}),
    TPE4: frames.StringFrame(.{}),
    TOPE: frames.StringFrame(.{}),
    TEXT: frames.StringFrame(.{}),
    TOLY: frames.StringFrame(.{}),
    TCOM: frames.StringFrame(.{}),
    TMCL: frames.StringFrame(.{}),
    TIPL: frames.StringFrame(.{}),
    TENC: frames.StringFrame(.{}),
    TBPM: frames.NumericStringFrame(u16, .{}),
    TLEN: frames.NumericStringFrame(u16, .{}),
    TKEY: frames.StringFrame(.{}),
    TLAN: frames.StringFrame(.{}),
    TCON: frames.StringFrame(.{}),
    TFLT: frames.StringFrame(.{}),
    TMED: frames.StringFrame(.{}),
    TMOO: frames.StringFrame(.{}),
    TCOP: frames.StringFrame(.{}),
    TPRO: frames.StringFrame(.{}),
    TPUB: frames.StringFrame(.{}),
    TOWN: frames.StringFrame(.{}),
    TRSN: frames.StringFrame(.{}),
    TRSO: frames.StringFrame(.{}),
    TOFN: frames.StringFrame(.{}),
    TDLY: frames.NumericStringFrame(u64, .{}),
    TDEN: frames.TimestampFrame,
    TDOR: frames.TimestampFrame,
    TDRC: frames.TimestampFrame,
    TDRL: frames.TimestampFrame,
    TDTG: frames.TimestampFrame,
    TSSE: frames.StringFrame(.{}),
    TSOA: frames.StringFrame(.{}),
    TSOT: frames.StringFrame(.{}),
    TSOP: frames.StringFrame(.{}),
    TXXX: frames.TXXX,
};

const ExtendedHeaderFlagKind = enum {
    crc_data_present,
    tag_is_update,
    tag_has_restrictions,
};

pub const ExtendedHeaderTagRestrictions = struct {
    pub const FrameSizeRestriction = enum {
        no_more_than_128_frames_1mb_tag_size,
        no_more_than_64_frames_128kb_tag_size,
        no_more_than_32_frames_40kb_tag_size,
        no_more_than_32_frames_4kb_tag_size,
    };

    pub const TextEncodingRestriction = enum {
        only_iso_8859_1_or_utf8,
    };

    pub const TextFieldSizeRestriction = enum {
        no_string_longer_than_1024_char,
        no_string_longer_than_128_char,
        no_string_longer_than_30_char,
    };

    pub const ImageEncodingRestriction = enum { png_or_jpeg_only };

    pub const ImageSizeRestriction = enum {
        all_are_256x256_or_smaller,
        all_are_64x64_or_smaller,
        all_are_exactly_64x64,
    };

    frame_size_restriction: FrameSizeRestriction,
    text_encoding_restriction: ?TextEncodingRestriction,
    text_field_size_restriction: ?TextFieldSizeRestriction,
    image_encoding_restriction: ?ImageEncodingRestriction,
    image_size_restriction: ?ImageSizeRestriction,

    fn fromByte(source: u8) ExtendedHeaderTagRestrictions {
        var restrictions: ExtendedHeaderTagRestrictions = undefined;

        // 0xPP000000
        restrictions.frame_size_restriction = switch (source & 0b11000000) {
            0b11000000 => .no_more_than_128_frames_1mb_tag_size,
            0b10000000 => .no_more_than_64_frames_128kb_tag_size,
            0b01000000 => .no_more_than_32_frames_40kb_tag_size,
            0b00000000 => .no_more_than_32_frames_4kb_tag_size,
            else => unreachable,
        };

        restrictions.text_encoding_restriction = switch (source & 0b00100000) {
            0b00100000 => .only_iso_8859_1_or_utf8,
            0b00000000 => null,
            else => unreachable,
        };

        restrictions.text_field_size_restriction = switch (source & 0b00011000) {
            0b00011000 => .no_string_longer_than_30_char,
            0b00001000 => .no_string_longer_than_1024_char,
            0b00010000 => .no_string_longer_than_128_char,
            0b00000000 => null,
            else => unreachable,
        };

        restrictions.image_encoding_restriction = switch (source & 0b00000100) {
            0b00000100 => .png_or_jpeg_only,
            0b00000000 => null,
            else => unreachable,
        };

        restrictions.image_size_restriction = switch (source & 0b00000011) {
            0b00000011 => .all_are_exactly_64x64,
            0b00000010 => .all_are_64x64_or_smaller,
            0b00000001 => .all_are_256x256_or_smaller,
            0b00000000 => null,
            else => unreachable,
        };

        return restrictions;
    }
};

// TODO(haze): look into turning the CRC into a [5]u8
pub const ExtendedHeader = struct {
    allocator: std.mem.Allocator,
    flags: []ExtendedHeaderFlag,

    pub fn format(
        self: ExtendedHeader,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll("ExtendedHeader { flags: [");
        for (self.flags) |flag|
            try writer.print("{}", .{flag});
        try writer.writeAll("]}");
    }

    pub fn deinit(self: *ExtendedHeader) void {
        for (self.flags) |*flag|
            flag.deinit(self.allocator); // free the crc data
        self.allocator.free(self.flags);
        self.* = undefined;
    }
};

pub const ExtendedHeaderFlag = struct {
    /// If this flag is set, the present tag is an update of a tag found
    /// earlier in the present file or stream. If frames defined as unique
    /// are found in the present tag, they are to override any
    /// corresponding ones found in the earlier tag. This flag has no
    /// corresponding data.
    tag_is_update: bool,

    // If this flag is set, a CRC-32 [ISO-3309] data is included in the
    // extended header. The CRC is calculated on all the data between the
    // header and footer as indicated by the header's tag length field,
    // minus the extended header. Note that this includes the padding (if
    // there is any), but excludes the footer. The CRC-32 is stored as an
    // 35 bit synchsafe integer, leaving the upper four bits always
    // zeroed.
    maybe_crc_data: ?[]u8,

    // For some applications it might be desired to restrict a tag in more
    // ways than imposed by the ID3v2 specification. Note that the
    // presence of these restrictions does not affect how the tag is
    // decoded, merely how it was restricted before encoding. If this flag
    // is set the tag is restricted as follows:
    maybe_restrictions: ?ExtendedHeaderTagRestrictions,

    pub fn format(
        self: ExtendedHeaderFlag,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        try writer.print("ExtHeaderFlag {{ tag_is_update: {}, ", .{self.tag_is_update});

        if (self.maybe_crc_data) |crc_data| {
            try writer.print("crc_data: <{} bytes>, ", .{crc_data.len});
        } else {
            try writer.writeAll("crc_data: null, ");
        }

        if (self.maybe_restrictions) |restrictions| {
            try writer.print("restrictions: {}", .{restrictions});
        } else {
            try writer.writeAll("restrictions: null");
        }

        try writer.writeAll(" }");
    }

    pub fn deinit(self: *ExtendedHeaderFlag, allocator: std.mem.Allocator) void {
        if (self.maybe_crc_data) |crc_data|
            allocator.free(crc_data);
        self.* = undefined;
    }
};

pub const RawExtendedHeader = struct {
    pub const TagIsUpdateMask = 1 << 6;
    pub const HasCrcDataMask = 1 << 5;
    pub const HasTagRestrictionMask = 1 << 4;

    allocator: std.mem.Allocator,

    flags: []u8,
    size: u32,

    pub fn interpret(self: RawExtendedHeader, reader: anytype) !ExtendedHeader {
        var extended_header: ExtendedHeader = undefined;

        extended_header.allocator = self.allocator;
        extended_header.flags = try self.allocator.alloc(ExtendedHeaderFlag, self.flags.len);

        for (self.flags, 0..) |flag, index| {
            log.warn("flag[{}] = {b}", .{ index, flag });
            var extended_header_flag: ExtendedHeaderFlag = undefined;

            extended_header_flag.tag_is_update = flag & TagIsUpdateMask != 0;

            if (flag & HasCrcDataMask != 0) {
                const crc_data_length = try reader.readByte();
                log.warn("crc_len={}", .{crc_data_length});
                const crc_data = try self.allocator.alloc(u8, crc_data_length);
                _ = try reader.readAll(crc_data);
                extended_header_flag.maybe_crc_data = crc_data;
            } else {
                extended_header_flag.maybe_crc_data = null;
            }

            if (flag & HasTagRestrictionMask != 0) {
                const tag_restriction_size = try reader.readByte();
                _ = tag_restriction_size;
                const raw_restrictions = try reader.readByte();
                extended_header_flag.maybe_restrictions = ExtendedHeaderTagRestrictions.fromByte(raw_restrictions);
            } else {
                extended_header_flag.maybe_restrictions = null;
            }

            extended_header.flags[index] = extended_header_flag;
        }

        return extended_header;
    }

    pub fn deinit(self: *RawExtendedHeader) void {
        self.allocator.free(self.flags);
        self.* = undefined;
    }
};

pub const RawHeader = struct {
    pub const HasUnsynchronisationMask = 1 << 7;
    pub const HasExtendedHeaderMask = 1 << 6;
    pub const IsExperimentalMask = 1 << 5;
    pub const HasFooterMask = 1 << 4;

    flags: u8,
    size: u32,

    pub fn interpret(self: RawHeader) Header {
        return Header{
            .is_unsynchronisation_used = (self.flags & HasUnsynchronisationMask) != 0,
            .has_extended_header = (self.flags & HasExtendedHeaderMask) != 0,
            .is_experimental = (self.flags & IsExperimentalMask) != 0,
            .has_footer = (self.flags & HasFooterMask) != 0,
            .size = self.size,
        };
    }
};

pub const Header = struct {
    is_unsynchronisation_used: bool,
    has_extended_header: bool,
    is_experimental: bool,
    has_footer: bool,
    size: u32,
};

pub fn Parser(comptime ReaderType: type) type {
    return struct {
        const State = union(enum) {
            reading_header,
            finished,
            reading_extended_header: struct {
                bytes_left: u64,
            },
            reading_frame_or_padding: struct {
                bytes_left: u64,
            },
        };

        pub const Result = union(enum) {
            header: Header,
            extended_header: ExtendedHeader,
            frame: Frame,
            unknown_frame: struct {
                frame_id: []const u8,
                allocator: std.mem.Allocator,
            },

            pub fn format(
                self: Result,
                comptime fmt: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = fmt;
                _ = options;
                return switch (self) {
                    .header => |header| writer.print("Header {}", .{header}),
                    .extended_header => |header| writer.print("{}", .{header}),
                    .frame => |frame| writer.print("Frame {}", .{frame}),
                    .unknown_frame => |data| writer.print("Unkowwn Frame {s}", .{data.frame_id}),
                };
            }

            pub fn deinit(self: *Result) void {
                switch (self.*) {
                    .frame => |*result_frame| switch (result_frame.*) {
                        .TIT1, .TIT2, .TIT3, .TOAL, .TSST, .TPE3, .TPE4, .TEXT, .TOLY, .TMCL, .TIPL, .TLAN, .TFLT, .TMED, .TPRO, .TPUB, .TALB, .TCOM, .TCON, .TSSE, .TPE1, .TPE2, .TOPE, .TSRC, .TENC, .TKEY, .TCOP, .TMOO, .TOWN, .TRSN, .TRSO, .TOFN, .TSOA, .TSOT, .TSOP => |*frame| frame.deinit(),
                        .TXXX => |*frame| frame.deinit(),
                        // nothing to free in timestamp frames
                        .TDEN, .TDOR, .TDRC, .TDRL, .TDTG => {},
                        // nothing to free in numeric string frames
                        .TRCK, .TPOS, .TBPM, .TDLY, .TLEN => {},
                    },
                    .unknown_frame => |data| data.allocator.free(data.frame_id),
                    .extended_header => |*extended_header| extended_header.deinit(),
                    .header => {},
                }
            }
        };

        reader: ReaderType,
        state: State = .reading_header,
        allocator: std.mem.Allocator,

        pub fn nextItem(self: *@This()) !?Result {
            while (self.state != .finished) {
                switch (self.state) {
                    .finished => unreachable,
                    .reading_frame_or_padding => |*payload| {
                        const first_byte = try self.reader.readByte();
                        if (first_byte == 0x00 or payload.bytes_left == 0) {
                            self.state = .finished;
                            // try self.reader.skipBytes(payload.bytes_left - 1, .{});
                            // var mp3_magic: [4]u8 = undefined;
                            // _ = try self.reader.readAll(&mp3_magic);
                            // log.warn("{}", .{std.fmt.fmtSliceHexUpper(&mp3_magic)});
                            // TODO(haze): this is where we'd begin parsing footers
                        } else {
                            var frame_id: [4]u8 = undefined;
                            frame_id[0] = first_byte;
                            _ = try self.reader.readAll(frame_id[1..]);
                            const source_frame_size = try self.reader.readInt(u32, .big);

                            var frame_size: u32 = 0;
                            comptime var mask: u32 = 0x7F000000;
                            inline while (mask > 0) : ({
                                frame_size >>= 1;
                                frame_size |= (source_frame_size & mask);
                                mask >>= 8;
                            }) {}

                            const flags = try self.reader.readInt(u16, .big);

                            inline for (@typeInfo(Frame).Union.fields) |field| {
                                if (std.mem.eql(u8, field.name, &frame_id)) {
                                    payload.bytes_left -= (frame_size + 10);
                                    return Result{
                                        .frame = @unionInit(Frame, field.name, try field.type.parse(
                                            self.reader,
                                            .{
                                                .allocator = self.allocator,
                                                .frame_size = frame_size,
                                            },
                                        )),
                                    };
                                }
                            }
                            log.warn("unknown frame id: {s} ({any})", .{ frame_id, frame_id });

                            try self.reader.skipBytes(frame_size, .{});
                            const bytes_consumed = frame_size + 10;
                            log.warn("left={}, minus={}", .{ payload.bytes_left, bytes_consumed });
                            payload.bytes_left -= bytes_consumed;
                            log.warn("(consumed={}) left=({}) read {s} (size={} ({}), flags={})", .{ bytes_consumed, payload.bytes_left, frame_id, frame_size, frame_size + frame_id.len, flags });
                            return Result{
                                .unknown_frame = .{
                                    .frame_id = try self.allocator.dupe(u8, &frame_id),
                                    .allocator = self.allocator,
                                },
                            };
                        }
                    },
                    // 0b00100000
                    // 0b0bcd0000
                    .reading_extended_header => |payload| {
                        const extended_header_size = try self.reader.readInt(u32, .big);
                        const number_of_flag_bytes = try self.reader.readByte();
                        log.warn("size={}, num_flags={}", .{ extended_header_size, number_of_flag_bytes });
                        // TODO(haze): we could probably remove this
                        const flag_bytes = try self.allocator.alloc(u8, number_of_flag_bytes);
                        _ = try self.reader.readAll(flag_bytes);
                        var raw_extended_header = RawExtendedHeader{
                            .allocator = self.allocator,
                            .flags = flag_bytes,
                            .size = extended_header_size,
                        };
                        defer raw_extended_header.deinit();
                        self.state = .{ .reading_frame_or_padding = .{ .bytes_left = payload.bytes_left - extended_header_size } };
                        return Result{ .extended_header = try raw_extended_header.interpret(self.reader) };
                    },
                    .reading_header => {
                        const flags = try self.reader.readByte();
                        const source_tag_size = try self.reader.readInt(u32, .big);

                        var tag_size: u32 = 0;
                        comptime var mask: u32 = 0x7F000000;
                        inline while (mask > 0) : ({
                            tag_size >>= 1;
                            tag_size |= (source_tag_size & mask);
                            mask >>= 8;
                        }) {}
                        const raw_header = RawHeader{
                            .flags = flags,
                            .size = tag_size,
                        };
                        const interpreted_header = raw_header.interpret();
                        if (interpreted_header.has_extended_header) {
                            self.state = .{ .reading_extended_header = .{ .bytes_left = tag_size } };
                        } else {
                            self.state = .{ .reading_frame_or_padding = .{ .bytes_left = tag_size } };
                        }
                        return Result{ .header = interpreted_header };
                    },
                }
            }

            return null;
        }
    };
}
