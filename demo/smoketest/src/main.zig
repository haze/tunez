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
    while (try library_walker.next()) |entry| {
        if (entry.kind != .File) continue;
        if (!std.mem.endsWith(u8, entry.basename, "mp3")) continue;
        out.info("Reading {s}", .{entry.basename});
        var file = try entry.dir.openFile(entry.basename, .{});
        var reader = std.io.bufferedReader(file.reader()).reader();

        var parser = tunez.id3.Parser(@TypeOf(reader)){
            .allocator = arena.allocator(),
            .reader = reader,
        };
        while (parser.nextItem() catch continue) |result| {
            out.info("{}", .{result});
        }
    }
}
