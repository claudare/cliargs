const std = @import("std");

// TODO: this needs a build.zig

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
