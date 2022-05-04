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
            reading_frame_or_padding: struct {
                bytes_left: u64,
            },
        };

        pub const Result = union(enum) {
            header: Header,
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
                    else => {},
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
                        var first_byte = try self.reader.readByte();
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
                            const source_frame_size = try self.reader.readIntBig(u32);

                            var frame_size: u32 = 0;
                            comptime var mask: u32 = 0x7F000000;
                            inline while (mask > 0) : ({
                                frame_size >>= 1;
                                frame_size |= (source_frame_size & mask);
                                mask >>= 8;
                            }) {}

                            const flags = try self.reader.readIntBig(u16);

                            inline for (@typeInfo(Frame).Union.fields) |field| {
                                if (std.mem.eql(u8, field.name, &frame_id)) {
                                    payload.bytes_left -= (frame_size + 10);
                                    return Result{
                                        .frame = @unionInit(Frame, field.name, try field.field_type.parse(
                                            self.reader,
                                            .{
                                                .allocator = self.allocator,
                                                .frame_size = frame_size,
                                            },
                                        )),
                                    };
                                }
                            }
                            log.warn("unknown frame id: {s}", .{frame_id});

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
                    .reading_header => {
                        const flags = try self.reader.readByte();
                        const source_tag_size = try self.reader.readIntBig(u32);

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
                        self.state = .{ .reading_frame_or_padding = .{ .bytes_left = tag_size } };
                        return Result{ .header = raw_header.interpret() };
                    },
                }
            }

            return null;
        }
    };
}
