const std = @import("std");
pub const id3 = @import("id3v2.zig");

test {
    std.testing.refAllDecls(id3);
}
