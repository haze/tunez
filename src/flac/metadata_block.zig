//! https://xiph.org/flac/format.html#metadata_block_header
const std = @import("std");
const vorbis_comment = @import("../vorbis_comment.zig");

pub const BlockKind = enum(u8) {
    stream_info = 0,
    padding = 1,
    application = 2,
    seek_table = 3,
    vorbis_comment = 4,
    cue_sheet = 5,
    picture = 6,
    invalid = 127,
    _,
};

pub const StreamInfo = struct {
    min_block_size: u16,
    max_block_size: u16,
    min_frame_size: u24,
    max_frame_size: u24,
    sample_rate_hz: u20,
    channel_count: u3,
    bits_per_sample: u5,
    total_samples: u36,
    md5_signature: u128,
};

pub const Header = struct {
    is_last_block: bool,
    block_kind: BlockKind,
    block_length: u24,
};

pub const Body = union(BlockKind) {
    stream_info: StreamInfo,
    vorbis_comment: []vorbis_comment.Comment,
    padding: void,
    application: void,
    seek_table: void,
    cue_sheet: void,
    picture: void,
    invalid: void,

    pub fn deinit(self: Body, allocator: std.mem.Allocator) void {
        switch (self) {
            .vorbis_comment => |comments| {
                for (comments) |comment|
                    comment.deinit(allocator);
                allocator.free(comments);
            },
            else => {},
        }
    }
};

pub const MetadataBlock = struct {
    header: Header,
    maybe_body: ?Body,

    pub fn parse(reader: anytype, allocator: std.mem.Allocator) !MetadataBlock {
        var block: MetadataBlock = undefined;

        var header_and_block_kind = try reader.readByte();
        const is_last_block = (header_and_block_kind & (1 << 7)) != 0;
        const block_kind = @intToEnum(BlockKind, header_and_block_kind & 0b01111111);
        const block_length = try reader.readIntBig(u24);
        block.header = Header{
            .is_last_block = is_last_block,
            .block_kind = block_kind,
            .block_length = block_length,
        };

        switch (block_kind) {
            .vorbis_comment => {
                var comments = std.ArrayList(vorbis_comment.Comment).init(allocator);
                var comment_parser = vorbis_comment.Parser(@TypeOf(reader), .{ .expect_framing_bit = false, .endian = .Little }){
                    .allocator = allocator,
                    .reader = reader,
                };
                while (try comment_parser.nextItem()) |*result| {
                    switch (result.*) {
                        .header => |*header| header.deinit(allocator),
                        .comment => |comment| try comments.append(comment),
                    }
                }
                block.maybe_body = .{ .vorbis_comment = comments.toOwnedSlice() };
            },
            else => {
                _ = try reader.skipBytes(block_length, .{});
                block.maybe_body = null;
            },
        }

        return block;
    }

    pub fn deinit(self: MetadataBlock, allocator: std.mem.Allocator) void {
        if (self.maybe_body) |body|
            body.deinit(allocator);
    }
};
