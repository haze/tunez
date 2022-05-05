const std = @import("std");

// TODO(haze): support using the same buffer thats allocated during the parser

pub const id3 = @import("id3v2.zig");

pub const AudioInfo = struct {
    allocator: std.mem.Allocator,

    maybe_track_title: ?[]const u8 = null,
    maybe_track_album: ?[]const u8 = null,
    maybe_track_artists: ?[][]const u8 = null,

    pub fn deinit(self: *AudioInfo) void {
        if (self.maybe_track_title) |track_title|
            self.allocator.free(track_title);
        if (self.maybe_track_album) |track_album|
            self.allocator.free(track_album);
        if (self.maybe_track_artists) |track_artists| {
            for (track_artists) |artist|
                self.allocator.free(artist);
            self.allocator.free(track_artists);
        }
        self.* = undefined;
    }
};

pub fn resolveId3(reader: anytype, allocator: std.mem.Allocator) !AudioInfo {
    var parser = id3.Parser(@TypeOf(reader)){
        .allocator = allocator,
        .reader = reader,
    };

    var audio_info = AudioInfo{
        .allocator = allocator,
    };

    var artists = std.ArrayList([]const u8).init(allocator);

    while (try parser.nextItem()) |*result| {
        defer result.deinit();

        switch (result.*) {
            .v3 => |*v3_result| {
                switch (v3_result.*) {
                    .frame => |*frame| switch (frame.*) {
                        .TIT2 => |title_frame| {
                            var utf8_string = try title_frame.value.asUtf8(allocator);
                            defer utf8_string.deinit();
                            audio_info.maybe_track_title = try allocator.dupe(u8, utf8_string.bytes);
                        },
                        .TALB => |album_frame| {
                            var utf8_string = try album_frame.value.asUtf8(allocator);
                            defer utf8_string.deinit();
                            audio_info.maybe_track_album = try allocator.dupe(u8, utf8_string.bytes);
                        },
                        .TPE1 => |artist_frame| {
                            var utf8_string = try artist_frame.value.asUtf8(allocator);
                            defer utf8_string.deinit();
                            try artists.append(try allocator.dupe(u8, utf8_string.bytes));
                        },
                        .TPE2 => |artist_frame| {
                            var utf8_string = try artist_frame.value.asUtf8(allocator);
                            defer utf8_string.deinit();
                            try artists.append(try allocator.dupe(u8, utf8_string.bytes));
                        },
                        else => {},
                    },
                    else => {},
                }
            },
            .v4 => |*v4_result| {
                switch (v4_result.*) {
                    .frame => |*frame| switch (frame.*) {
                        .TIT2 => |title_frame| {
                            var utf8_string = try title_frame.value.asUtf8(allocator);
                            defer utf8_string.deinit();
                            audio_info.maybe_track_title = try allocator.dupe(u8, utf8_string.bytes);
                        },
                        .TALB => |album_frame| {
                            var utf8_string = try album_frame.value.asUtf8(allocator);
                            defer utf8_string.deinit();
                            audio_info.maybe_track_album = try allocator.dupe(u8, utf8_string.bytes);
                        },
                        .TPE1 => |artist_frame| {
                            var utf8_string = try artist_frame.value.asUtf8(allocator);
                            defer utf8_string.deinit();
                            try artists.append(try allocator.dupe(u8, utf8_string.bytes));
                        },
                        .TPE2 => |artist_frame| {
                            var utf8_string = try artist_frame.value.asUtf8(allocator);
                            defer utf8_string.deinit();
                            try artists.append(try allocator.dupe(u8, utf8_string.bytes));
                        },
                        else => {},
                    },
                    else => {},
                }
            },
        }
    }

    if (artists.items.len != 0) {
        audio_info.maybe_track_artists = artists.toOwnedSlice();
    }

    return audio_info;
}

test {
    // std.testing.refAllDecls(id3);
    const file_path = "/Users/haze/Downloads/01_-_Gesaffelstein_-_Out_Of_Line.mp3";
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());

    var audio_info = try resolveId3(buffered_reader.reader(), std.testing.allocator);
    defer audio_info.deinit();

    std.log.warn("{s} - {s}", .{ audio_info.maybe_track_album, audio_info.maybe_track_title });
}
