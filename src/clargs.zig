const std = @import("std");
const Allocator = std.mem.Allocator;
const AnyWriter = std.io.AnyWriter;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;
const ArgIterator = std.process.ArgIterator;

const debug = std.debug;
const assert = std.debug.assert;

pub fn ClargInitAsLibraryUser(
    allocator: Allocator,
    arg_iterator: *ArgIterator,
    writer: AnyWriter,
) Allocator.Error!Clargs(ArgIterator, ArgIterator.next) {
    return Clargs(ArgIterator, ArgIterator.next).init(
        allocator,
        arg_iterator,
        writer,
    );
}

/// args_iterator must be conforming to *std.process.ArgIterator
/// but i cant use it, as it must be comptime known..
/// so need to pull out the function
pub fn Clargs(
    comptime IArgIterator: type,
    comptime nextFn: *const fn (T: *IArgIterator) ?([:0]const u8),
) type {
    return struct {
        ptr_iter: *IArgIterator,

        allocator: Allocator,
        writer: AnyWriter,

        const CliArgs = @This();

        pub fn init(
            allocator: Allocator,
            ptr_iter: *IArgIterator,
            writer: AnyWriter,
        ) Allocator.Error!CliArgs {
            return CliArgs{
                .ptr_iter = ptr_iter,
                .allocator = allocator,
                .writer = writer,
            };
        }
        pub fn deinit(self: *CliArgs) void {
            _ = self;
        }
        // typesafe functions of the generic parameters

        pub fn next(self: CliArgs) ?([:0]const u8) {
            return nextFn(self.ptr_iter);
        }
    };
}

const testing = std.testing;
const TestArgIterator = @import("test_helpers.zig").TestArgIterator;

test "can init/deinit for tests" {
    var arg_iterator = comptime TestArgIterator.init(&.{
        "hello",
        "world",
    });

    var buff: [100]u8 = undefined;
    var rw = std.io.fixedBufferStream(&buff);

    const writer = rw.writer().any();
    const allocator = testing.allocator;

    var Cli = try Clargs(
        TestArgIterator,
        TestArgIterator.next,
    ).init(allocator, &arg_iterator, writer);

    defer Cli.deinit();

    try testing.expectEqual("hello", Cli.next());
}

test "can init/deinit for real" {
    var arg_iterator = try ArgIterator.initWithAllocator(testing.allocator);
    defer arg_iterator.deinit();

    var Cli = try ClargInitAsLibraryUser(
        testing.allocator,
        &arg_iterator,
        std.io.getStdOut().writer().any(),
    );

    defer Cli.deinit();
}
