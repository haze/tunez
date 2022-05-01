/// This purpose of this program is to "smoke test" a directory of audio files and print out which
/// ID3 versions and frame kinds that `tunez` does not support. This is meant to get us to an MVP
const std = @import("std");
const tunez = @import("tunez");
const out = std.log.scoped(.smoketest);

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    var arg_iter = try std.process.argsWithAllocator(arena.allocator());
    defer arg_iter.deinit();
    _ = arg_iter.skip();

    var library_path = arg_iter.next() orelse return error.NoLibraryProvided;
    var library_dir = try std.fs.cwd().openDir(library_path, .{ .iterate = true });
    defer library_dir.close();

    var library_walker = try library_dir.walk(arena.allocator());
    var file_count: usize = 0;
    var file_times = std.ArrayList(u64).init(arena.allocator());
    defer file_times.deinit();

    var id3_v3_unknown_frames_set = std.StringHashMap(void).init(arena.allocator());
    defer id3_v3_unknown_frames_set.deinit();
    var id3_v4_unknown_frames_set = std.StringHashMap(void).init(arena.allocator());
    defer id3_v4_unknown_frames_set.deinit();

    while (try library_walker.next()) |entry| {
        if (entry.kind != .File) continue;
        if (!std.mem.endsWith(u8, entry.basename, "mp3")) continue;
        out.info("Reading {s}", .{entry.basename});
        var file = try entry.dir.openFile(entry.basename, .{});
        defer file.close();
        var reader = std.io.bufferedReader(file.reader()).reader();

        var parser = tunez.id3.Parser(@TypeOf(reader)){
            .allocator = arena.allocator(),
            .reader = reader,
        };
        var timer = try std.time.Timer.start();
        while (parser.nextItem() catch continue) |result| {
            switch (result) {
                .v3 => |v3_result| switch (v3_result) {
                    .unknown_frame => |frame_id| try id3_v3_unknown_frames_set.put(try arena.allocator().dupe(u8, frame_id), {}),
                    else => {},
                },
                .v4 => |v4_result| switch (v4_result) {
                    .unknown_frame => |frame_id| try id3_v4_unknown_frames_set.put(try arena.allocator().dupe(u8, frame_id), {}),
                    else => {},
                },
            }
            out.info("{}", .{result});
        }
        try file_times.append(timer.read());
        file_count += 1;
    }
    var total_time: u64 = 0;
    for (file_times.items) |time|
        total_time += time;

    const stdout = std.io.getStdOut().writer();
    try stdout.print("id3v2.3 unknown frames: {}\n", .{id3_v3_unknown_frames_set.count()});
    var id3_v3_unknown_frame_iter = id3_v3_unknown_frames_set.keyIterator();
    if (id3_v3_unknown_frames_set.count() > 0) {
        while (id3_v3_unknown_frame_iter.next()) |frame| {
            defer arena.allocator().free(frame.*);
            try stdout.print("{s}, ", .{frame.*});
        }
        try stdout.writeByte('\n');
    }
    try stdout.print("id3v2.4 unknown frames: {}\n", .{id3_v4_unknown_frames_set.count()});
    var id3_v4_unknown_frame_iter = id3_v4_unknown_frames_set.keyIterator();
    if (id3_v4_unknown_frames_set.count() > 0) {
        while (id3_v4_unknown_frame_iter.next()) |frame| {
            defer arena.allocator().free(frame.*);
            try stdout.print("{s}, ", .{frame.*});
        }
        try stdout.writeByte('\n');
    }
    try stdout.print("parsed {} files in {}\n", .{ file_count, std.fmt.fmtDuration(total_time) });
}
