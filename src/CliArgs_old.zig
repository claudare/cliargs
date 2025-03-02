const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;

const debug = std.debug;
const assert = std.debug.assert;

const CliArgs = @This();

allocator: Allocator,

// these are exclusively parse results
// so move them into a tokensizer?
application_name: []const u8 = undefined,
input: Input,
// hmmm...
diagnostics: Diagnostics,

// thats also in diagnostics!
// description of the current command
current_subcommand_description: []const u8 = undefined,
// whats the current custom help message
current_custom_help: ?[]const u8 = null,

/// args_iterator must be conforming to *std.process.ArgIterator
pub fn init(temp_allocator: Allocator, args_interator: anytype) Allocator.Error!CliArgs {
    // first arg is always ignored
    // instead it should be as program_name or executable_name or smth...
    const app_name = args_interator.next();

    if (app_name == null) {
        // not possible???
        @panic("args_iterator is bad");
    }

    const input = try Input.init(temp_allocator, args_interator);

    const is_help = input.flags.contains("h") or input.flags.contains("help");

    const diag = Diagnostics.init(temp_allocator, is_help);

    return CliArgs{
        .allocator = temp_allocator,
        .application_name = app_name.?,
        .input = input,
        .diagnostics = diag, // dont use for now!
    };
}

pub fn deinit(self: *CliArgs) void {
    self.input.deinit();
    self.diagnostics.deinit();
}

pub fn subcommand(self: *CliArgs, name: []const u8, description: []const u8) !bool {
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

pub fn flag(self: *CliArgs, short_name: []const u8, long_name: []const u8, description: []const u8) Allocator.Error!bool {
    // TODO: check the short_name and long_name
    //
    //
    const result = self.input.consumeFlag(short_name, long_name);

    // TODO: diagnostics
    _ = description;
    // if (self.diagnostics) {}

    return result;
}
pub fn argumentOptional(
    self: *CliArgs,
    T: type,
    default: T,
    short_name: []const u8,
    long_name: []const u8,
    description: []const u8,
) Allocator.Error!T {
    // TODO: check the short_name and long_name
    //
    // TODO: diagnostics for help
    _ = description;
    // if (self.diagnostics) {}

    if (self.input.consumeArgument(short_name, long_name)) |value| {

        // convert it into a given type and return to the caller
        return self.convertValue(T, default, value);
    }

    // must return a default
    return default;
}
// default is still needed? hmmm...
pub fn argumentRequired(
    self: *CliArgs,
    T: type,
    short_name: []const u8,
    long_name: []const u8,
    description: []const u8,
) Allocator.Error!T {
    // TODO: check the short_name and long_name
    //
    // TODO: diagnostics for help
    _ = description;

    const default = defaultValue(T);

    if (self.input.consumeArgument(short_name, long_name)) |value| {

        // convert it into a given type and return to the caller
        return self.convertValue(T, default, value);
    }
    // TODO: handle cases of where short_name or long_name could be null
    try self.diagnostics.addErrorFmt(error.MissingRequired, "required argument -{s} or --{s} was not found", .{ short_name, long_name });
    return default;
}
// TODO: argumentConvertedOptional, argumentConvertedRequired... The required is one thing that doesnt add up

/// this returns the next positional value or empty
/// useful when iterator is not needed and lets say we need just 1 positional
pub fn positional(self: *CliArgs) ![]const u8 {
    // TODO: stupid diag with dynamic arrays are ruining error reporting
    // what if there is a static array of errors
    // cause if we get to something like 10+, its already too much
    // same can be done with arguments technically and everything, but then its annoying as shit
    // will still need to throw if OOM, I dont want it to just panic...
    const maybe_value = try self.input.consumePositional(&self.diagnostics); // errors are mandatory added

    if (maybe_value == null) {
        return "";
    }
    return maybe_value.?;
}

pub const PositionalIterator = struct {
    parent: CliArgs,
    pub fn next(self: *PositionalIterator) ?[]const u8 {
        return self.parent.input.consumePositional(&self.parent.diagnostics);
    }
};

/// key function to check if everything is good before proceeding
pub fn hasErrorz(self: *CliArgs) !bool {
    // will check everything
    // even without a diag there should be error! thing

    if (self.diagnostics.is_help) {
        return true;
    }

    var error_count: usize = 0;

    error_count += try self.input.checkAndAddErrorsForUnconsumedArguments(&self.diagnostics);
    error_count += try self.input.checkAndAddErrorsForUnconsumedPositionals(&self.diagnostics);

    return error_count > 0;
}

pub fn printErrors(self: *CliArgs, out_writer: anytype) !void {
    // _ = out_writer;

    for (self.diagnostics.errors.items) |err| {
        try out_writer.print("[printErrors:] {any}, {s}\n", .{ err.zig_error, err.message });
    }
}
pub fn printHelp(out_writer: anytype) void {
    _ = out_writer;
}

fn defaultValue(T: type) T {
    const ti = @typeInfo(T);

    return switch (ti) {
        .Pointer => |pointer| {
            switch (pointer.size) {
                .Slice => {
                    if (pointer.child == u8) {
                        // its a "string, return it as such"
                        return "";
                    }
                },
                else => @compileError("pointer type " ++ @typeName(T) ++ " is not supported yet!"),
            }
        },
        .Int => return 0,
        else => @compileError("type " ++ @typeName(T) ++ " is not supported yet!"),
    };
}

fn convertValue(self: *CliArgs, T: type, default: T, raw: []const u8) T {
    // this will add to the errors if diag is enabled if something is wrong!
    //
    // TODO: use diagnostics, so that errors are supressed
    _ = self;

    const ti = @typeInfo(T);

    switch (ti) {
        .Pointer => |pointer| {
            switch (pointer.size) {
                .Slice => {
                    if (pointer.is_const and pointer.child == u8) {
                        // its a "string, return it as such"
                        return raw;
                    }
                },

                else => @compileError("pointer type " ++ @typeName(T) ++ " is not implemented yet"),
            }
        },
        .Int => |_| {
            return std.fmt.parseInt(T, raw, 10) catch {
                // TODO: add diagnostics

                return default;
            };
        },
        else => @compileError("type " ++ @typeName(T) ++ " is not supported yet!"),
    }
}

const Argument = struct {
    name: []const u8,
    value: []const u8,
};

const ParseToken = union(enum) {
    flag: struct {
        name: []const u8,
    }, // keep it []u8 as string hashmap is used for everything
    argument: Argument,
    positional: struct { value: []const u8 },
    rest_chunk: struct { value: []const u8 }, // aka chunk of value after --, must be reassembled later
};

const ParseError = struct {
    zig_error: anyerror,
    message: []const u8,

    // TODO: template all standard messages here
    // pub fn badFlag(name: []const u8) ParseError {
    //     return .{
    //         .og = error.ParseError,
    //         .msg = "bad flag value" ++ name,
    //     };
    // }
};

// now we are going to do the subcommands
// this is unmanaged
const Input = struct {
    flags: StringHashMap(void),
    arguments: StringHashMap([]const u8), // TODO: also specify if its short or not?
    positionals: ArrayList([]const u8),
    positional_index: usize = 0,
    rest_chunks: ArrayList([]const u8),

    // TODO: dont parse it now, parse when ready
    pub fn init(allocator: Allocator, args_iterator: anytype) Allocator.Error!Input {
        var self = Input{
            .flags = StringHashMap(void).init(allocator), // long also needs to be here
            .arguments = StringHashMap([]const u8).init(allocator),
            .positionals = ArrayList([]const u8).init(allocator),
            .rest_chunks = ArrayList([]const u8).init(allocator),
        };
        var tokenizer = Tokenizer{};

        while (tokenizer.next(args_iterator)) |token| {
            switch (token) {
                .flag => |_flag| {
                    // there could be duplicates
                    // at this stage i cant differentiate that both -a and --along are passed
                    // this will not clobber as resulting type is void?
                    // i must raise this as an error
                    try self.flags.put(_flag.name, {});
                },
                .argument => |argument| {
                    // should i allow multiple args? how are arrays handled in this m8
                    // arrays could be forced to be defined as key=value1,value2,value3
                    // no duplicates are allowed
                    // TODO: handle duplicates... it must result in an error
                    try self.arguments.put(argument.name, argument.value);
                },
                .positional => |_positional| {
                    try self.positionals.append(_positional.value);
                },
                .rest_chunk => |chunk| {
                    try self.rest_chunks.append(chunk.value);
                },
            }
        }
        return self;
    }

    pub fn deinit(self: *Input) void {
        // the actual values are not cleaned up, cause external allocator was used
        self.flags.deinit();
        self.arguments.deinit();
        self.positionals.deinit();
        self.rest_chunks.deinit();
    }

    // will use and consume the flag(aka remove it)
    // but what if there are duplicate -a and --along?
    // then if -a is used, and then --along is asked... we get the error as "unknown flag"
    // which is highly misleading... fuck
    // pub fn useFlag(short: []const u8, long: []const u8) !void {}
    // but I want required flag consumption maybe? flags cant be required!
    pub fn consumeFlag(self: *Input, short: []const u8, long: []const u8) bool {
        // TODO: either one could be 0 length, check for that first!!!

        const found = self.flags.contains(short) or self.flags.contains(long);
        // NOTE: akshuualy its not needed to clean it up, as no duplicates will be provided
        if (found) {
            _ = self.flags.remove(short);
            _ = self.flags.remove(long);
        }
        return found;
    }

    pub fn consumeArgument(self: *Input, short: []const u8, long: []const u8) ?[]const u8 {
        if (self.arguments.get(short)) |value| {
            _ = self.arguments.remove(short);
            _ = self.arguments.remove(long);
            return value;
        } else if (self.arguments.get(long)) |value| {
            _ = self.arguments.remove(short);
            _ = self.arguments.remove(long);
            return value;
        } else {
            return null;
        }
    }

    pub fn currentPositional(self: *Input) ?[]const u8 {
        if (self.positional_index == self.positionals.items.len) {
            return null;
        }
        return self.positionals.items[self.positional_index];
    }

    pub fn consumePositional(self: *Input, maybe_diag: ?*Diagnostics) !?[]const u8 {
        if (self.positional_index == self.positionals.items.len) {
            // error!
            if (maybe_diag) |diag| {
                try diag.addErrorFmt(
                    error.PositionalOutOfBounds,
                    "TODO: too few positional arguments provided. current index: {d}",
                    .{self.positional_index},
                );
            }

            return null;
        }
        const index = self.positional_index;
        self.positional_index += 1;
        return self.positionals.items[index];
    }

    // returns the amount of errors
    // rest chunks do not count?
    pub fn checkAndAddErrorsForUnconsumedArguments(self: *Input, diag: *Diagnostics) !usize {
        var error_count: usize = 0;

        if (self.arguments.count() > 0) {
            // add the needed errors to a diag
            error_count += self.arguments.count();

            // go though them
            var it = self.arguments.keyIterator();
            while (it.next()) |name| {
                const is_short = name.len == 1;

                if (is_short) {
                    try diag.addErrorFmt(error.UnknownArgument, "unknown argument -{s}", .{name.*});
                } else {
                    try diag.addErrorFmt(error.UnknownArgument, "unknown argument --{s}", .{name.*});
                }
            }
        }

        return error_count;
    }

    pub fn checkAndAddErrorsForUnconsumedPositionals(self: *Input, diag: *Diagnostics) !usize {
        var error_count: usize = 0;

        while (self.positional_index < self.positionals.items.len) {
            const index = self.positional_index;

            try diag.addErrorFmt(
                error.TooManyPositionals,
                "TODO this positional was not needed: {s}",
                .{self.positionals.items[index]},
            );

            error_count += 1;
            self.positional_index += 1;
        }

        return error_count;
    }
};

const Tokenizer = struct {
    flag_group_iterator: ?*FlagGroupIterator = null,
    is_rest_group: bool = false,

    const FlagGroupIterator = struct {
        values: [:0]const u8,
        index: usize = 0,
        // TODO: check for invalid values, allow only english things
        // as things like -=+ are not allowed. Also letters are not allowed
        pub fn next(self: *FlagGroupIterator) ?ParseToken {
            const current = self.index;
            if (self.index < self.values.len) {
                self.index += 1;
                return ParseToken{ .flag = .{
                    .name = self.values[current .. current + 1],
                } };
            }
            return null;
        }
    };

    /// og_iterator must be conforming to *std.process.ArgIterator
    fn next(self: *Tokenizer, iterator: anytype) ?ParseToken {
        if (self.flag_group_iterator) |group| {
            if (group.next()) |token| {
                return token;
            } else {
                self.flag_group_iterator = null;
            }
        }

        const maybe_value: ?([:0]const u8) = iterator.next();
        if (maybe_value == null) {
            // debug.print("maybevalue {?s}, issep? {any}\n", .{ maybe_value, self.is_rest_group });
            return null; // we are done
        }
        const value = maybe_value.?;

        // debug.print("value {s}, issep? {any}\n", .{ value, self.is_rest_group });

        // check for rest group
        if (self.is_rest_group) {
            // debug.print("early returning {any}\n", .{ParseToken{ .rest_chunk = .{
            //     .value = value,
            // } }});

            return ParseToken{ .rest_chunk = .{
                .value = value,
            } };
        }

        if (value.len >= 2 and value[0] == '-') {
            if (value[1] == '-') {
                // long flag or long arg or separator (--)
                if (value.len == 2) {
                    // separator (--)
                    // debug.print("separator detected\n", .{});

                    self.is_rest_group = true;
                    // but dont return null, return the next value
                    // try to get next one
                    return self.next(iterator);
                } else if (std.mem.indexOf(u8, value, "=")) |idx| {
                    // long arg

                    // debug.print("long arg detected. value {s}, name {s}, value, {s}\n", .{ value, value[2..idx], value[idx + 1 ..] });
                    return ParseToken{ .argument = .{
                        .name = value[2..idx],
                        .value = value[idx + 1 ..],
                    } };
                } else {
                    // long flag
                    return ParseToken{ .flag = .{
                        .name = value[2..],
                    } };
                }
            } else {
                // singular short flag, group flag, or short arg

                if (value.len == 2) {
                    // singular short flag
                    // debug.print("short flag detected. value {s}, cut {s}\n", .{ value, value[1..2] });
                    return ParseToken{ .flag = .{
                        .name = value[1..2],
                    } };
                } else if (std.mem.indexOf(u8, value, "=")) |idx| {
                    // short arg
                    // debug.print("short arg detected. value {s}, name {s}, value, {s}\n", .{ value, value[1..2], value[idx + 1 ..] });

                    return ParseToken{ .argument = .{
                        .name = value[1..2],
                        .value = value[idx + 1 ..],
                    } };
                } else {
                    // group flag, there are multiple short flags here, 2 or more guaranteed
                    assert(self.flag_group_iterator == null);

                    var flag_group_iterator = FlagGroupIterator{
                        .values = value[1..],
                    };

                    self.flag_group_iterator = &flag_group_iterator;
                    return self.flag_group_iterator.?.next();
                }
            }
        }

        return ParseToken{ .positional = .{
            .value = value,
        } };
    }
};

pub const Diagnostics = struct {
    allocator: Allocator,
    is_help: bool,
    error_count: usize = 0,
    subcommands: ArrayList(Subcommand),
    errors: ArrayList(ParseError),

    const Subcommand = struct {
        name: []const u8,
        description: []const u8,
        matched: bool,
    };

    // is help is known right away!
    pub fn init(allocator: Allocator, is_help: bool) Diagnostics {
        return .{
            .allocator = allocator,
            .is_help = is_help,
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

// when is the parsing done... is it done on the init?

const testing = std.testing;

// for debug
// var it = cliargs.input.flags.iterator();
// while (it.next()) |vv| {
//     debug.print("flagz: {any}\n", .{vv});
// }
test "successful config" {
    var iter = TestArgIterator.init(&.{
        "appName", // required here
        "-f", // short flag
        "--int=10", // long int
        "-s=hello world", // short string
        "positional1", // inline positional
    });
    var cliargs = try CliArgs.init(testing.allocator, &iter);
    defer cliargs.deinit();

    const f = try cliargs.flag("f", "flag", "flag description");
    const int = try cliargs.argumentRequired(u8, "", "int", "int description");
    const string = try cliargs.argumentOptional([]const u8, "default value", "s", "string", "string description");
    const int_optional = try cliargs.argumentOptional(u8, 20, "", "int", "int description");

    // consume the positional
    const positional1 = try cliargs.positional();

    try testing.expectEqual(false, cliargs.hasErrorz());
    try testing.expectEqual(0, cliargs.diagnostics.error_count);

    try testing.expectEqualStrings("appName", cliargs.application_name);
    try testing.expectEqual(true, f);
    try testing.expectEqual(@as(u8, 10), int);
    try testing.expectEqualStrings("hello world", string);
    try testing.expectEqual(@as(u8, 20), int_optional);
    try testing.expectEqualStrings("positional1", positional1);
}

// need to test help
test "help messages" {
    // many cases that all trigger the same help message
    var iter = TestArgIterator.init(&.{
        "appName", // required here
        "-h",
    });
    var cliargs = try CliArgs.init(testing.allocator, &iter);
    defer cliargs.deinit();

    // required and optional arguments get thier default values since its help
    const int = try cliargs.argumentRequired(u8, "", "int", "int description");
    const string = try cliargs.argumentOptional([]const u8, "default value", "s", "string", "string description");

    try testing.expectEqual(true, cliargs.hasErrorz());
    try testing.expectEqual(0, cliargs.diagnostics.error_count); // no errors though

    try testing.expectEqual(@as(u8, 0), int); // sane defauly
    try testing.expectEqualStrings("default value", string);

    // TODO: try printing a help message
}

test "error hanlding" {
    var iter = TestArgIterator.init(&.{
        "appName", // required here
        "-U", // unknown flag
        "--req-badname=hello world", // required argument is not provided
        "positional1", // single positional, unconsumed
    });
    var cliargs = try CliArgs.init(testing.allocator, &iter);
    defer cliargs.deinit();

    const f = try cliargs.flag("f", "", "");
    const req = try cliargs.argumentRequired([]const u8, "r", "req", "");

    try testing.expectEqual(true, cliargs.hasErrorz());
    try testing.expectEqual(3, cliargs.diagnostics.error_count);

    // make sure sane defaults were used
    try testing.expectEqual(false, f);
    try testing.expectEqualStrings("", req);

    var buff: [300]u8 = undefined;
    var rw = std.io.fixedBufferStream(&buff);
    try cliargs.printErrors(rw.writer());

    try testing.expectEqualStrings(
        \\[printErrors:] error.MissingRequired, required argument -r or --req was not found
        \\[printErrors:] error.UnknownArgument, unknown argument --req-badname
        \\[printErrors:] error.TooManyPositionals, TODO this positional was not needed: positional1
        \\
    , rw.getWritten());
}

test Tokenizer {
    // make this a suite

    // megatest
    var iter = TestArgIterator.init(&.{
        "positional1", // positional
        "-a", // short flag
        "-bc", // group flag
        "--dlong", // long flag
        "positional2", // inline positional
        "-", // positional also!
        "-e=arg1", // short arg
        "--flong=arg2", // long arg
        "--", // separator
        "rest1", // rest
    });
    var args = Tokenizer{};

    try testing.expectEqualDeep(ParseToken{ .positional = .{ .value = "positional1" } }, args.next(&iter));
    try testing.expectEqualDeep(ParseToken{ .flag = .{ .name = "a" } }, args.next(&iter));
    try testing.expectEqualDeep(ParseToken{ .flag = .{ .name = "b" } }, args.next(&iter));
    try testing.expectEqualDeep(ParseToken{ .flag = .{ .name = "c" } }, args.next(&iter));
    try testing.expectEqualDeep(ParseToken{ .flag = .{ .name = "dlong" } }, args.next(&iter));
    try testing.expectEqualDeep(ParseToken{ .positional = .{ .value = "positional2" } }, args.next(&iter));
    try testing.expectEqualDeep(ParseToken{ .positional = .{ .value = "-" } }, args.next(&iter));
    try testing.expectEqualDeep(ParseToken{ .argument = .{ .name = "e", .value = "arg1" } }, args.next(&iter));
    try testing.expectEqualDeep(ParseToken{ .argument = .{ .name = "flong", .value = "arg2" } }, args.next(&iter));
    try testing.expectEqualDeep(ParseToken{ .rest_chunk = .{ .value = "rest1" } }, args.next(&iter));
    try testing.expectEqualDeep(null, args.next(&iter));

    // also test more in a test-matrix type of ways
}

// test utils
pub const TestArgIterator = struct {
    values: []const [:0]const u8,
    index: usize = 0,

    pub fn init(values: []const [:0]const u8) TestArgIterator {
        return TestArgIterator{
            .index = 0,
            .values = values,
        };
    }

    pub fn next(self: *TestArgIterator) ?[:0]const u8 {
        if (self.index == self.values.len) return null;

        const s = self.values[self.index];
        self.index += 1;
        return std.mem.sliceTo(s, 0);
    }

    pub fn skip(self: *TestArgIterator) bool {
        if (self.index == self.values.len) return false;

        self.index += 1;
        return true;
    }
};
