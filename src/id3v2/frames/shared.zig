pub const Unicode16ByteOrder = enum {
    Big,
    Little,

    pub fn parse(reader: anytype) !Unicode16ByteOrder {
        var byte_order: [2]u8 = undefined;
        _ = try reader.readAll(&byte_order);
        if (byte_order[0] == 0xFE) return .Big else return .Little;
    }
};
