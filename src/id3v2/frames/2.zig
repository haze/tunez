const impl = @import("2.impl.zig");
pub const FrameBody = union(enum) {
    PLHD: impl.PLHD,
};
