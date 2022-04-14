const std = @import("std");
const logger = std.log.scoped(.id3v2_4_0_util);

pub const TextEncodingDescriptionByte = enum(u8) {
    ISO_8859_1 = 0x00,
    UTF_16 = 0x01,
    UTF_16BE = 0x02,
    UTF_8 = 0x03,
    _,

    pub fn parse(reader: anytype) !TextEncodingDescriptionByte {
        return @intToEnum(TextEncodingDescriptionByte, try reader.readByte());
    }
};

pub const Timestamp = struct {
    pub const Month = enum { january, febuary, march, april, may, june, july, august, september, october, november, december };
    year: u16,
    maybe_month: ?Month = null,
    maybe_day: ?u5 = null,
    maybe_hour: ?u5 = null,
    maybe_minutes: ?u6 = null,
    maybe_seconds: ?u6 = null,

    pub fn eql(self: Timestamp, other: Timestamp) bool {
        if (self.year != other.year) return false;
        if (self.maybe_month) |self_month|
            if (other.maybe_month) |other_month| {
                if (self_month != other_month) {
                    return false;
                }
            } else return false;
        if (self.maybe_day) |self_day|
            if (other.maybe_day) |other_day| {
                if (self_day != other_day) {
                    return false;
                }
            } else return false;
        if (self.maybe_hour) |self_hour|
            if (other.maybe_hour) |other_hour| {
                if (self_hour != other_hour) {
                    return false;
                }
            } else return false;
        if (self.maybe_minutes) |self_minutes|
            if (other.maybe_minutes) |other_minutes| {
                if (self_minutes != other_minutes) {
                    return false;
                }
            } else return false;
        if (self.maybe_seconds) |self_seconds|
            if (other.maybe_seconds) |other_seconds| {
                if (self_seconds != other_seconds) {
                    return false;
                }
            } else return false;
        return true;
    }

    pub fn parseUtf8(reader: anytype) !Timestamp {
        var year_buf: [4]u8 = undefined;
        _ = try reader.read(&year_buf);
        var working_timestamp = Timestamp{
            .year = try std.fmt.parseInt(u16, &year_buf, 10),
        };
        return working_timestamp;
    }

    pub fn parseUtf8FromSlice(slice: []const u8) !Timestamp {
        var reader = std.io.fixedBufferStream(slice).reader();
        return Timestamp.parseUtf8(reader);
    }

    test "parse" {
        try std.testing.expect((Timestamp{ .year = 2020 }).eql(Timestamp.parseUtf8FromSlice("2020") catch unreachable));
    }
};
