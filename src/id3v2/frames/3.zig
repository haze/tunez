const frames = @import("3.frames.zig");
const std = @import("std");
pub const log = std.log.scoped(.id3v2_3);

pub const Frame = union(enum) {
    TYER: frames.TYER,
    TRCK: frames.TRCK,
    TPOS: frames.TPOS,
    TXXX: frames.TXXX,
    APIC: frames.APIC,
    TPE1: frames.SimpleStringFrame(.{}),
    TSRC: frames.SimpleStringFrame(.{}),
    TIT2: frames.SimpleStringFrame(.{}),
    TPUB: frames.SimpleStringFrame(.{}),
    TIT1: frames.SimpleStringFrame(.{}),
    TCON: frames.SimpleStringFrame(.{}),
    TPE2: frames.SimpleStringFrame(.{}),
    TALB: frames.SimpleStringFrame(.{}),
    TLEN: frames.SimpleStringFrame(.{}),
    TENC: frames.SimpleStringFrame(.{}),
    USLT: frames.SimpleStringFrame(.{ .expect_language = true }),
    COMM: frames.SimpleStringFrame(.{ .expect_language = true }),

    pub fn format(
        self: Frame,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s} - ", .{@tagName(@as(FrameKind, self))});
        switch (self) {
            .TYER => |frame| try writer.print("{}", .{frame.year}),
            .TRCK => |frame| {
                try writer.print("{}", .{frame.track_index});
                if (frame.maybe_total_tracks) |total_tracks| {
                    try writer.print("/{}", .{total_tracks});
                }
            },
            .TPOS => |frame| {
                try writer.print("{}", .{frame.part_index});
                if (frame.maybe_total_parts_in_set) |total_parts| {
                    try writer.print("/{}", .{total_parts});
                }
            },
            .APIC => |frame| {
                try writer.print("{s}", .{frame.mime_type});
            },
            .TXXX => |frame| {
                try writer.print("{}", .{frame});
            },
            .USLT, .COMM => |frame| {
                try writer.print("{s}: <content...>", .{&frame.value.language});
            },
            .TPE1, .TSRC, .TIT2, .TPUB, .TALB, .TCON, .TIT1, .TPE2, .TENC, .TLEN => |frame| {
                try writer.print("{}", .{frame.value});
            },
        }
    }
};

const FrameKind = @typeInfo(Frame).Union.tag_type.?;

pub const RawHeader = struct {
    pub const HasUnsynchronisationMask = 1 << 7;
    pub const HasExtendedHeaderMask = 1 << 6;
    pub const IsExperimentalMask = 1 << 5;

    flags: u8,
    size: u32,

    pub fn interpret(self: RawHeader) Header {
        return Header{
            .is_unsynchronisation_used = (self.flags & HasUnsynchronisationMask) != 0,
            .has_extended_header = (self.flags & HasExtendedHeaderMask) != 0,
            .is_experimental = (self.flags & IsExperimentalMask) != 0,
            .size = self.size,
        };
    }
};

pub const Header = struct {
    is_unsynchronisation_used: bool,
    has_extended_header: bool,
    is_experimental: bool,
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
                        .TPE1, .TSRC, .TIT2, .TPUB, .TALB => |*frame| frame.deinit(),
                        .TXXX => |*frame| frame.deinit(),
                        else => {},
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
                            const frame_size = try self.reader.readIntBig(u32);
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
                            log.warn("(left={}) unknown frame id: {s}", .{ payload.bytes_left, frame_id });

                            try self.reader.skipBytes(frame_size, .{});
                            const bytes_consumed = frame_size + 10;
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
