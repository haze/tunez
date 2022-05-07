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

    var successful_flac_file_count: usize = 0;
    var successful_mp3_file_count: usize = 0;
    var file_count: usize = 0;

    var mp3_file_times = std.ArrayList(u64).init(arena.allocator());
    defer mp3_file_times.deinit();
    var flac_file_times = std.ArrayList(u64).init(arena.allocator());
    defer flac_file_times.deinit();

    var id3_v3_unknown_frames_set = std.StringHashMap(void).init(arena.allocator());
    defer id3_v3_unknown_frames_set.deinit();
    var id3_v4_unknown_frames_set = std.StringHashMap(void).init(arena.allocator());
    defer id3_v4_unknown_frames_set.deinit();

    while (try library_walker.next()) |entry| {
        if (entry.kind != .File) continue;
        const is_mp3 = std.mem.endsWith(u8, entry.basename, "mp3");
        const is_flac = std.mem.endsWith(u8, entry.basename, "flac");
        if (!is_mp3 and !is_flac) continue;

        out.info("Reading {s}", .{entry.basename});
        defer {
            file_count += 1;
        }

        var file = try entry.dir.openFile(entry.basename, .{});
        defer file.close();
        var reader = std.io.bufferedReader(file.reader()).reader();

        var timer = try std.time.Timer.start();
        if (is_mp3) {
            var parser = tunez.id3.Parser(@TypeOf(reader)){
                .allocator = arena.allocator(),
                .reader = reader,
            };
            while (parser.nextItem() catch |err| {
                out.err("error during {s}: {}", .{ entry.basename, err });
                continue;
            }) |*result| {
                defer result.deinit();

                switch (result.*) {
                    .v3 => |*v3_result| switch (v3_result.*) {
                        .unknown_frame => |*data| try id3_v3_unknown_frames_set.put(try arena.allocator().dupe(u8, data.frame_id), {}),
                        else => {},
                    },
                    .v4 => |*v4_result| switch (v4_result.*) {
                        .unknown_frame => |*data| try id3_v4_unknown_frames_set.put(try arena.allocator().dupe(u8, data.frame_id), {}),
                        else => {},
                    },
                }
                out.info("{}", .{result});
            }
            try mp3_file_times.append(timer.read());
            successful_mp3_file_count += 1;
        } else if (is_flac) {
            var parser = tunez.flac.Parser(@TypeOf(reader)){
                .allocator = arena.allocator(),
                .reader = reader,
            };
            while (parser.nextItem() catch |err| {
                out.err("error during {s}: {}", .{ entry.basename, err });
                continue;
            }) |*result| {
                defer result.deinit(arena.allocator());

                out.info("{}", .{result});
            }
            try flac_file_times.append(timer.read());
            successful_flac_file_count += 1;
        }
    }

    var flac_total_time: u64 = 0;
    for (flac_file_times.items) |time|
        flac_total_time += time;

    var mp3_total_time: u64 = 0;
    for (mp3_file_times.items) |time|
        mp3_total_time += time;

    const total_time = mp3_total_time + flac_total_time;

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

    var mp3_avg_time = @intToFloat(f64, mp3_total_time) / @intToFloat(f64, successful_mp3_file_count);
    var flac_avg_time = @intToFloat(f64, flac_total_time) / @intToFloat(f64, successful_flac_file_count);

    const successful_file_count = successful_mp3_file_count + successful_flac_file_count;

    try stdout.print("parsed {} mp3, {} flac ({} total)/{} files in {} ({} avg for mp3, {} avg for flac)\n", .{
        successful_mp3_file_count,
        successful_flac_file_count,
        successful_file_count,
        file_count,
        std.fmt.fmtDuration(total_time),
        std.fmt.fmtDuration(@floatToInt(u64, @round(mp3_avg_time))),
        std.fmt.fmtDuration(@floatToInt(u64, @round(flac_avg_time))),
    });
}
