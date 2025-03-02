const std = @import("std");
const Allocator = std.mem.Allocator;
const AnyWriter = std.io.AnyWriter;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;
const ArgIterator = std.process.ArgIterator;

const debug = std.debug;
const assert = std.debug.assert;

pub fn ClargGenericForLibraryUser(
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
        allocator: Allocator,
        consumer: ArgConsumer,
        writer: AnyWriter,
        diag: Diagnostics,

        const ArgConsumer = struct {
            ptr_iter: *IArgIterator,
            consume_next: bool = true,
            value: ?[:0]const u8 = null,

            pub fn get(self: *ArgConsumer) ?([:0]const u8) {
                if (self.consume_next) {
                    self.consume_next = false;
                    self.value = nextFn(self.ptr_iter);
                }
                return self.value;
            }
            pub fn consumed(self: *ArgConsumer) void {
                self.consume_next = true;
            }
        };

        const CliArgs = @This();

        pub fn init(
            allocator: Allocator,
            ptr_iter: *IArgIterator,
            writer: AnyWriter,
        ) Allocator.Error!CliArgs {
            return CliArgs{
                .allocator = allocator,
                .consumer = ArgConsumer{ .ptr_iter = ptr_iter },
                .writer = writer,
                .diag = Diagnostics.init(allocator),
            };
        }
        pub fn deinit(self: *CliArgs) void {
            _ = self;
        }
        // typesafe functions of the generic parameters

        // this should return a new instance instead of piling things up on Diagnostics
        // this _seems_ to be memory heavy and defragmented
        // but single instance must be used as pointers are preserved?
        // maybe thats why golang flag library doesnt do this?
        pub fn subcommand(self: *CliArgs, name: []const u8, description: []const u8) !bool {
            const value = self.consumer.get();

            // accumulate to the current stack

            if (value == null) {
                return false;
            }

            // do not log errors or consume this. Manual increase later
            const maybe_current = self.input.currentPositional();

            if (maybe_current == null) {
                // its okay? just return false
                return false;
            }
            const current = maybe_current.?;

            const matched = std.mem.eql(u8, current, name);
            if (matched) {
                self.input.consumePositional(null); // no diagnostics, thank you
            }

            // TODO: add to diagnotics
            _ = description;
            // if (self.diagnostics) {
            //     try self.subcommands.append(.{
            //         .name = name,
            //         .description = description,
            //         .matched = matched,
            //     });
            // }

            return matched;
        }

        pub fn roughTest(self: *CliArgs, name: []const u8, default: u64) *u64 {}
    };
}

const Argument = struct {
    short_name: []const u8,
    long_name: []const u8,
    description: []const u8,
    // this was my original issue and it still persists to here
    // the generic type ArrayList(Argument) is not possible
    // so I WILL need to parse everything upfront...
    // It should be efficient as everything is prepared for parsing
    // since all must be available, I should not use the iterator?
    // its just so ugly and combersome to develop for
    value: *T,
};

const Subcommand = struct {
    name: []const u8,
    description: []const u8,
    matched: bool,
};
const ParseError = struct {
    zig_error: anyerror,
    message: []const u8,

    // TODO: template all standard error messages here
    // pub fn badFlag(allocator: Allocator, name: []const u8) ParseError {
    //     return .{
    //         .og = error.ParseError,
    //         .msg = "bad flag value" ++ name,
    //     };
    // }
};

pub const Diagnostics = struct {
    allocator: Allocator,
    error_count: usize = 0, // why is this here?
    // there are 2 subcommand arrays
    // one for all "collected ones" to show help if nothing matched
    // and one for the "stack" aka "server start"
    subcommands: ArrayList(Subcommand),
    errors: ArrayList(ParseError),

    // is help is known right away!
    pub fn init(allocator: Allocator) Diagnostics {
        return .{
            .allocator = allocator,
            .subcommands = ArrayList(Subcommand).init(allocator),
            .errors = ArrayList(ParseError).init(allocator),
        };
    }

    pub fn deinit(self: *Diagnostics) void {
        self.subcommands.deinit();
        for (self.errors.items) |item| {
            self.allocator.free(item.message);
        }
        self.errors.deinit();
    }

    fn addErrorFmt(self: *Diagnostics, original_error: anyerror, comptime fmt: []const u8, args: anytype) !void {
        // assert there is no \n in the end
        if (fmt[fmt.len - 1] == '\n') {
            @compileError("errors must not contain a newline!");
        }

        if (self.is_help)
            return;

        self.error_count += 1;

        const message = try std.fmt.allocPrint(self.allocator, fmt, args);

        try self.errors.append(.{
            .zig_error = original_error,
            .message = message,
        });
    }
};

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

    try testing.expectEqual("hello", Cli.consumer.get());
    try testing.expectEqual("hello", Cli.consumer.get());
    Cli.consumer.consumed();
    try testing.expectEqual("world", Cli.consumer.get());
}

test "can init/deinit for real" {
    // it would be much simpler to use this instead of the iterator
    // as [][]u8 is more portable. But thats more allocations...
    // const all: [][]u8 = try std.process.argsAlloc(testing.allocator);

    var arg_iterator = try ArgIterator.initWithAllocator(testing.allocator);
    defer arg_iterator.deinit();

    var Cli = try ClargGenericForLibraryUser(
        testing.allocator,
        &arg_iterator,
        std.io.getStdOut().writer().any(),
    );

    defer Cli.deinit();
}
