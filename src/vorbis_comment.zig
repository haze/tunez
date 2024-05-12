const std = @import("std");

pub const CommentHeader = struct {
    vendor_length: u32,
    vendor_string: []const u8,
    user_comment_list_length: u32,

    pub fn deinit(self: *CommentHeader, allocator: std.mem.Allocator) void {
        allocator.free(self.vendor_string);
        self.* = undefined;
    }
};

pub const Comment = struct {
    field: []const u8,
    field_name: []const u8,
    field_value: []const u8,

    pub fn deinit(self: *Comment, allocator: std.mem.Allocator) void {
        allocator.free(self.field);
        self.* = undefined;
    }
};

pub const OggVorbisCommentParserOptions = struct {
    expect_framing_bit: bool,
    endian: std.builtin.Endian,
};

// NOTE: FLAC ogg vorbis files have no framing bit
pub fn Parser(comptime ReaderType: type, options: OggVorbisCommentParserOptions) type {
    return struct {
        const Self = @This();
        const State = union(enum) {
            reading_header: void,
            reading_comment: u32,
            finished: void,
        };

        pub const Result = union(enum) {
            header: CommentHeader,
            comment: Comment,

            pub fn deinit(self: *Result) void {
                switch (self) {
                    .header => |*header| header.deinit(),
                    .comment => |*comment| comment.deinit(),
                }
                self.* = undefined;
            }
        };

        allocator: std.mem.Allocator,
        reader: ReaderType,
        state: State = .reading_header,

        pub fn nextItem(self: *Self) !?Result {
            while (self.state != .finished) {
                switch (self.state) {
                    .reading_header => {
                        var header: CommentHeader = undefined;
                        header.vendor_length =
                            switch (options.endian) {
                            .Little => try self.reader.readIntLittle(u32),
                            .Big => try self.reader.readIntBig(u32),
                        };

                        const vendor_string = try self.allocator.alloc(u8, @as(usize, @intCast(header.vendor_length)));
                        _ = try self.reader.readAll(vendor_string);
                        header.vendor_string = vendor_string;

                        header.user_comment_list_length =
                            switch (options.endian) {
                            .Little => try self.reader.readIntLittle(u32),
                            .Big => try self.reader.readIntBig(u32),
                        };
                        self.state = .{ .reading_comment = header.user_comment_list_length };
                        return Result{ .header = header };
                    },
                    .reading_comment => |*comments_left| {
                        var comment: Comment = undefined;
                        const comment_length =
                            switch (options.endian) {
                            .Little => try self.reader.readIntLittle(u32),
                            .Big => try self.reader.readIntBig(u32),
                        };
                        const field = try self.allocator.alloc(u8, comment_length);
                        _ = try self.reader.readAll(field);
                        comment.field = field;
                        const field_sep_index = std.mem.indexOfScalar(u8, comment.field, '=') orelse return error.InvalidComment;
                        comment.field_name = comment.field[0..field_sep_index];
                        comment.field_value = comment.field[field_sep_index + 1 ..];
                        comments_left.* -|= 1;
                        if (comments_left.* == 0) {
                            self.state = .finished;
                        }
                        return Result{ .comment = comment };
                    },
                    .finished => unreachable,
                }
            }
            return null;
        }
    };
}
