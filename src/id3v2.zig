//! https://id3.org/id3v2.3.0

const std = @import("std");
const log = std.log.scoped(.id3v2);

const versions = struct {
    const v2 = @import("id3v2/frames/2.zig");
    const v3 = @import("id3v2/frames/3.zig");
    const v4 = @import("id3v2/frames/4.zig");
};

// const InformationBlock = union(enum) {};

// assert(TagHeader.major_version != 0xFF);
// assert(TagHeader.revision_version != 0xFF);

pub const TagHeader = struct {
    const UnsynchronisationFlagMask = 0b10000000;
    const ExtendedHeaderFlagMask = 0b01000000;
    const ExperimentalFlagMask = 0b00100000;
    const UnreadableFlagMask = 0b0001111;
    // assert(flags & UnreadableFlagMask = 0)
    // assert(msb in size & 0b10000000 != 0b10000000)

    major_version: u8,
    revision_version: u8,
    flags: u8,
    size: u32,
};

pub const ExtendedTagHeader = struct {
    const CRCDataPresentFlagMask = 0b10000000_00000000;
    size: u32,
    flags: u16,
    padding_size: u32,
};

pub fn Parser(comptime ReaderType: type) type {
    return struct {
        const Reader = ReaderType;
        const Self = @This();
        const State = union(enum) {
            reading_universal_header,
            reading_v3: versions.v3.Parser(ReaderType),
            reading_v4: versions.v4.Parser(ReaderType),
            finished: void,
        };
        pub const Result = union(enum) {
            v3: versions.v3.Parser(ReaderType).Result,
            v4: versions.v4.Parser(ReaderType).Result,

            pub fn format(
                self: Result,
                comptime fmt: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = options;
                _ = fmt;
                switch (self) {
                    .v3 => |v3_result| try writer.print("{}", .{v3_result}),
                    .v4 => |v4_result| try writer.print("{}", .{v4_result}),
                }
            }

            pub fn deinit(self: *Result) void {
                switch (self.*) {
                    .v3 => |*result| result.deinit(),
                    .v4 => |*result| result.deinit(),
                }
            }
        };

        reader: ReaderType,
        state: State = .reading_universal_header,
        allocator: std.mem.Allocator,

        pub fn nextItem(self: *Self) !?Result {
            while (self.state != .finished) {
                switch (self.state) {
                    .finished => unreachable,
                    .reading_v3 => |*parser| {
                        while (try parser.nextItem()) |result| {
                            return Result{ .v3 = result };
                        }
                        self.state = .finished;
                    },
                    .reading_v4 => |*parser| {
                        while (try parser.nextItem()) |result| {
                            return Result{ .v4 = result };
                        }
                        self.state = .finished;
                    },
                    .reading_universal_header => {
                        var header_part_buf: [4]u8 = undefined;
                        _ = try self.reader.readAll(&header_part_buf);
                        if (std.mem.eql(u8, header_part_buf[0..2], "ID3")) return error.IncorrectID3Magic;
                        switch (header_part_buf[3]) {
                            0x03 => {
                                _ = try self.reader.readByte(); // skip null version byte
                                log.warn("detected id3v2.3 file, switching parsers...", .{});
                                self.state = .{ .reading_v3 = .{
                                    .reader = self.reader,
                                    .allocator = self.allocator,
                                } };
                            },
                            0x04 => {
                                _ = try self.reader.readByte(); // skip null version byte
                                log.warn("detected id3v2.4 file, switching parsers...", .{});
                                self.state = .{ .reading_v4 = .{
                                    .reader = self.reader,
                                    .allocator = self.allocator,
                                } };
                            },
                            else => {
                                log.warn("encountered unsupported id3 version: {}", .{header_part_buf[3]});
                                return error.UnsupportedID3Version;
                            },
                        }
                    },
                }
            }
            return null;
        }
    };
}

test {
    // const mp3_file = @embedFile("/Users/haze/code/tunez/demo/smoketest/test/omg.mp3");
    const mp3_file = @embedFile("/Users/haze/Downloads/01_-_Gesaffelstein_-_Out_Of_Line.mp3");
    // const mp3_file = @embedFile("/Users/haze/03. #TakinShitDown.mp3");
    // const mp3_file = @embedFile("/Users/haze/Downloads/csrss36f.mp3");
    var reader = std.io.fixedBufferStream(mp3_file).reader();

    const ParserType = Parser(@TypeOf(reader));
    var parser = ParserType{
        .allocator = std.testing.allocator,
        .reader = reader,
    };

    while (try parser.nextItem()) |*result| {
        defer result.deinit();

        log.warn("item = {}", .{result});
    }
}
