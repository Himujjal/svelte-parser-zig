const std = @import("std");

pub fn eqlNullSlices(comptime T: type, endpoint1: ?[]const T, endpoint2: ?[]const T) bool {
    if (endpoint1) |a| {
        const b = endpoint2 orelse return false;
        return std.mem.eql(T, a, b);
    } else {
        return endpoint2 == null;
    }
}

pub fn toLowerCase(allocator: std.mem.Allocator, str: []const u8) []u8 {
    return std.ascii.allocLowerString(allocator, str) catch unreachable;
}
