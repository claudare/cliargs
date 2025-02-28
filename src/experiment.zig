const std = @import("std");
const Int = std.builtin.Type.Int;
const Float = std.builtin.Type.Float;

const AnyTag = struct {
    short_name: u8,
    long_name: []const u8,
    description: []const u8,
    ptr: *anyopaque, // or maybe can store as an int?
    config: union(enum) {
        int: Int,
        float: Float,
    },
};

const Testee = struct {
    arg: AnyTag = undefined,

    pub fn setArg(self: *Testee, T: type, value: *T) void {
        // if (@typeInfo(T).Int) {
        //     @panic("bad type bruv");
        // }

        switch (@typeInfo(T)) {
            .Int => |int| {
                self.arg = AnyTag{
                    .short_name = 'l',
                    .long_name = "lala",
                    .description = "lala",
                    .ptr = value,
                    .config = .{ .int = int },
                };
            },
            else => {
                @panic("NOT IMPLEMENTED");
            },
        }
    }

    pub fn override(self: *Testee) void {

        // fuck I cant access this, no way hozee

        const T = @Type(.{ .Int = self.arg.config.int });
        const ptr: *T = @ptrCast(self.arg.ptr);
        ptr.* = 'w';
    }
};

const testing = std.testing;

test "anythings" {
    var testee = Testee{};

    var value: u8 = 'q';

    testee.setArg(u8, &value);
    try testing.expectEqual('q', value);
    testee.override();
    try testing.expectEqual('w', value);
}
