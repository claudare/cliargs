const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
// why do it this way?
// well, first all the options will be accumulated
// and pointers to the value are stored

// when checking for errors (parseError or canRun) right before using the arguments
// the parsing of the input will be performed
// it can be a state machine of sorts, where tokens are evaluated
// so this way there is no ambiquiry between flags, arguments, and positionals
// and if help is needed, then no actual parsing and conversion is done
//
// it does seem to be backwards to parse the values before what is what is known
//
// Previous idea requires this crap:
// ./readfile -v build.zig // -v (--verbose) is a flag here
// ./readfile -t binary build.zig // -t binary is an argument, binary is no longer positional
//
// when flag "-v" is consumed, "build.zig" will be interpreted as a positional
// when argument "-t" is consumed, "binary" will not be interpreted as a positional
//

const Subcommand = struct {
    name: []const u8,
    description: []const u8,

    matched: bool,
};
const Flag = struct {
    short_name: u8,
    long_name: []const u8,
    description: []const u8,
    out: *bool,
};
fn Argument(T: type) type {
    return struct {
        short_name: u8,
        long_name: []const u8,
        description: []const u8,
        out: *T,
    };
}

const Positional = struct {
    description: []const u8,
    out: *anyopaque,
};
const ParseError = struct {
    og: anyerror,
    msg: []const u8,
};

// this is used for lookup speed?
// seeing -v would need to first check the flags
// if flags exist then it needs to check short
// this can disambiguate it
// also there is argumentConverted
const AnyTag = union(enum) {
    flag: Flag,
    argument: Argument(void),
    argument_string: Argument([]const u8), // in can store each supported type on here
    // argument_int: Argument(fuckkk), // cant expland ints in this bitch...
    // argument_bool: Argument(bool), // in can store each supported type on here
    // argumentConverted: ArgumentC
};

const ShortMap = std.AutoHashMap(u8, AnyTag);
const LongMap = std.StringHashMap(AnyTag);

// TODO: will need support .rest for arguments after --
// good guide for cli parsing https://clig.dev/#the-basics
pub const CliArgs = struct {
    allocator: Allocator,
    deinited: bool = false,
    is_help: bool = false,

    args: [][]u8,

    // need an array for subcommands
    // need an array for possible_flags
    // need an array for possible_arguments
    // need an array for possible_positionals
    subcommands: ArrayList(Subcommand),
    // flags: ArrayList(Flag),
    // arguments: ArrayList(Argument),
    positionals: ArrayList(Positional),
    positional_index: usize = 1, // for now automatically skip the app name
    errors: ArrayList(ParseError),

    // these get constructed when things are filing up
    // only get filled after the parse() is called
    // short_map: ShortMap,
    // long_map: LongMap,

    short_map: std.AutoHashMap(u8, AnyTag),
    long_map: std.StringHashMap(AnyTag),

    pub fn init(temp_allocator: Allocator, args: [][]u8) CliArgs {
        return .{
            .allocator = temp_allocator,
            .args = args,
            .subcommands = ArrayList(Subcommand).init(temp_allocator),
            .positionals = ArrayList(Positional).init(temp_allocator),
            .errors = ArrayList(ParseError).init(temp_allocator),
            .short_map = ShortMap.init(temp_allocator),
            .long_map = LongMap.init(temp_allocator),
        };
    }

    pub fn deinit(self: *CliArgs) void {
        if (self.deinited)
            return;
        self.deinited = true;

        self.subcommands.deinit();
        self.positionals.deinit();
        for (self.errors.items) |err| {
            self.allocator.free(err.msg);
        }
        self.errors.deinit();
        self.short_map.deinit();
        self.long_map.deinit();
    }

    fn addError(self: *CliArgs, original_error: anyerror, comptime fmt: []const u8, args: anytype) !void {
        if (self.is_help)
            return;

        const msg = try std.fmt.allocPrint(self.allocator, fmt, args);

        try self.errors.append(.{
            .og = original_error,
            .msg = msg,
        });
    }

    // try is needed as memory is allocated for this
    // its quite sad
    pub fn subcommand(self: *CliArgs, name: []const u8, description: []const u8) !bool {
        const current = self.args[self.positional_index];

        const matched = std.mem.eql(u8, current, name);

        if (matched) {
            self.positional_index += 1;
        }

        try self.subcommands.append(.{
            .name = name,
            .description = description,
            .matched = matched,
        });

        return matched;
    }

    pub fn flag(self: *CliArgs, short_name: []const u8, long_name: []const u8, out: *bool, description: []const u8) Allocator.Error!void {
        checkNames(short_name, long_name);

        if (short_name.len != 1) {
            @panic("short name must be 1 long");
        }

        const short_value = short_name[0];

        if (self.short_map.contains(short_value)) {
            // error duplicate, but this cannot be known at compiletime!!
            // @panic("duplicate detected, short arg " ++ short_name ++ " was already defined");
            @panic("duplicate detected, short arg ??? was already defined");
        }
        if (self.long_map.contains(long_name)) {
            // error duplicate, but this cannot be known at compiletime!!
            @panic("duplicate detected, long arg ??? was already defined");
        }

        try self.short_map.put(short_value, AnyTag{ .flag = .{
            .short_name = short_value,
            .long_name = long_name,
            .description = description,
            .out = out,
        } }); // is this okay? but I should not hide allocator failures!
        try self.long_map.put(long_name, AnyTag{ .flag = .{
            .short_name = short_value,
            .long_name = long_name,
            .description = description,
            .out = out,
        } });

        // add flag to the internal list
        // also need to store a hashmap of shortname -> flag
        // and hashmap of long_name -> flag
        //
        // Or I could just iterate though all of them to find it
    }

    pub fn argument(short_name: []const u8, long_name: []const u8, T: type, out: *T, description: []const u8) void {
        _ = short_name;
        _ = long_name;
        _ = description;
        _ = out; // value of out will be set, default is not needed here, as it must be defined ahead of time

    }

    /// custom conversion from strings
    pub fn argumentConverted(
        self: *CliArgs,
        short_name: []const u8,
        long_name: []const u8,
        T: type,
        convert_fn: fn (input: []const u8) anyerror!T,
        out: *T,
        description: []const u8,
    ) T {
        _ = short_name;
        _ = long_name;
        _ = description;

        // if this option not present, return default value
        // return default_value;

        const input: []const u8 = "lalala";

        // otherwise try to convert
        try {
            const converted_value = try convert_fn("hii");
            out.* = converted_value;
        } catch |err| {
            self.addError(err, "failed to convert " ++ @typeName(T) ++ " from " ++ input); // example code
        };
    }

    // could positionals be inside the command? like
    // chmod -R
    pub fn positional(
        out: *[]const u8,
        description: []const u8,
    ) void {
        _ = out;
        _ = description;
    }

    // this will iterate starting from the last read
    pub fn positionalIterator(
        description: []const u8,
    ) void {
        _ = description;
    }
    // get the positional by index, the subcommands are removed
    pub fn positionalByIndex(index: usize) ?[]const u8 {
        _ = index;
        return "lalaal";
    }

    // hmmm, the array needs allocation
    // the idea is that all internal allocations are erased
    // and thats not okay
    pub fn positionals() [][]const u8 {
        // gets next positional... would be nice to also provide an index?
        return null;
    }

    // value of the args after --
    // empty if not exists
    pub fn rest() []const u8 {
        return "";
    }

    /// returns true is the parsing was a success and if all pointers are filled with correct value
    /// returns false if there is an error. If error occurs, it must be printed
    pub fn parse(self: *CliArgs) !bool {

        // this needs to be while(true)
        // so that we start with the current and go next

        // if things were matched, the index was incremented pass it
        //

        while (self.positional_index < self.args.len) {
            const current = self.args[self.positional_index];

            // TODO: failing to parse also needs to be an internal error,
            // not a throw in the scope!
            const extracted = ExtractedArg.parse(current) catch |e| {
                // unknown argument
                try self.addError(e, "bad argument name: {s}", .{current});
                return false;
            };

            std.debug.print("extracted: {any}\n", .{extracted});

            switch (extracted) {
                .short => |shorts| {
                    // if its a single one, then its either a flag or an argument
                    // if there is many of them, then its many flags
                    if (shorts.len == 1) {
                        const v = shorts[0];
                        if (self.short_map.get(v)) |tag| {
                            switch (tag) {
                                // maybe needed by reference
                                .flag => |flagv| {
                                    flagv.out.* = true;
                                },
                                .argument => |argv| {
                                    self.positional_index += 1; //increment by one
                                    const nextv = self.args[self.positional_index];
                                    // TODO: check bounds, or add error
                                    // TODO: this needs to be properly converted to a given type argv.T, or add error
                                    // self.addError(error.TODOnameMe, "sudden end of input", .{});
                                    // argv.out.* = nextv;
                                    _ = argv;
                                    _ = nextv;
                                },
                                else => {
                                    @panic("not implemented");
                                },
                            }
                        } else {
                            try self.addError(error.TODOnameMe, "unknown shortname flag or argument: {c}", .{v});
                        }
                    } else {
                        // this is 100% many flags
                        for (shorts) |v| {
                            // look them all up
                            //
                            //
                            if (self.short_map.get(v)) |tag| {
                                switch (tag) {
                                    // maybe needed by reference
                                    .flag => |flagv| {
                                        flagv.out.* = true;
                                    },
                                    .argument => {
                                        // its not a flag, something is wrong
                                        try self.addError(error.TODOnameMe, "given flag is not a flag, its prob an argument: {c}", .{v});
                                    },
                                    else => {
                                        @panic("not implemented yet");
                                    },
                                }
                            } else {
                                try self.addError(error.TODOnameMe, "unknown shortname flag: {c}", .{v});
                            }

                            // self.short_map.get(v)
                        }
                    }
                },
                .long => |longs| {
                    // same exact logic, but for long...
                    _ = longs;
                    @panic("longs aint supported yet");
                },
                .other => |v| {
                    // positional argument probably
                    // look at first positional that was added and use it instead
                    // TODO: convert to needed type
                    _ = v;
                    @panic("other aint supported yet");

                    // self.positionals.items[0].out.* = v;
                },
            }

            // go to next one
            self.positional_index += 1;
        }

        if (self.errors.items.len == 0) {
            return true;
        }

        return false;
    }

    // it could also be multishort
    // like an array of arrays m8
    const ExtractedArg = union(enum) {
        short: []u8,
        long: []u8,
        other: []u8,

        pub fn parse(value: []u8) !@This() {
            if (value.len > 1) {
                // check for short
                if (value[0] == '-') { // what if its just -? then its an error!

                    // then its a short or a long
                    if (value.len >= 2) {
                        // TODO: this can just be "--"
                        if (value[1] == '-') {
                            return .{
                                .long = value[2..],
                            };
                        }
                        return .{
                            .short = value[1..],
                        };
                    }
                }
                return .{
                    .other = value,
                };
            }
            return error.InvalidArgument;
        }
    };

    // how can this be done if there are many positionals?
    // DONT USE ME
    fn next(self: *CliArgs) ?[]u8 {
        // gets next positional... would be nice to also provide an index?
        //
        if (self.positional_index == self.args.len) {
            return null;
        }
        const current = self.args[self.positional_index];
        self.positional_index += 1;

        return current;
    }

    /// this will print errors and/or help menu
    pub fn printErrors(self: *CliArgs, out_writer: anytype) !void {
        _ = out_writer;

        for (self.errors.items) |err| {
            std.debug.print("[printErrors:] {any}, {s}\n", .{ err.og, err.msg });
        }
    }
    pub fn printHelp(out_writer: anytype) void {
        _ = out_writer;
    }
};
fn checkNames(short: []const u8, long: []const u8) void {
    if (short.len == 0 and long.len == 0) {
        // throw an error here m8
        @panic("must define atleast one argument");
    }

    if (short.len > 0 and std.mem.eql(u8, short, "h")) {
        @panic("short argument -h is reserved");
    }
    if (long.len > 0 and std.mem.eql(u8, long, "help")) {
        @panic("long argument --help is reserved");
    }
}

fn testMakeArgs(allocator: Allocator, values: []const []const u8) ![][]u8 {
    const strings = try allocator.alloc([]u8, values.len);

    for (values, 0..) |value, i| {
        strings[i] = try allocator.dupe(u8, value);
    }

    return strings;
}
fn testFreeArgs(allocator: Allocator, args: [][]u8) void {
    for (args) |string| {
        allocator.free(string);
    }

    allocator.free(args);
}

const testing = std.testing;

test "rough as fuck 1" {
    const arguemnt_list = try testMakeArgs(testing.allocator, &.{
        "appName",
        "-ve",
    });
    defer testFreeArgs(testing.allocator, arguemnt_list);

    var args = CliArgs.init(std.testing.allocator, arguemnt_list);
    defer args.deinit();

    const stdout_writer = std.io.getStdOut().writer();

    // these are global and can be defined just once!
    var verbose = false;
    try args.flag("v", "verbose", &verbose, "print verbose information"); // no short flag!
    var emazing = false;

    try args.flag("e", "emazing", &emazing, "do emazing things"); // no short flag!

    if (!try args.parse()) {
        try args.printErrors(stdout_writer);
        return error.FailedToParse;
    }

    std.debug.print("verbose: {any}, emazing: {any}\n", .{ verbose, emazing });

    try testing.expectEqual(true, verbose);
    try testing.expectEqual(true, emazing);
}
test "rough as fuck 2 - subcommand" {
    const arguemnt_list = try testMakeArgs(testing.allocator, &.{
        "appName",
        "start",
        "-ve",
        "-b",
    });
    defer testFreeArgs(testing.allocator, arguemnt_list);

    var args = CliArgs.init(std.testing.allocator, arguemnt_list);
    defer args.deinit();

    const stdout_writer = std.io.getStdOut().writer();

    // these are global and can be defined just once!
    var verbose = false;
    try args.flag("v", "verbose", &verbose, "print verbose information"); // no short flag!
    var emazing = false;
    try args.flag("e", "emazing", &emazing, "do emazing things"); // no short flag!
    var bmazing = false;

    if (try args.subcommand("start", "...")) {
        try args.flag("b", "bmazing", &bmazing, "do bmazing things"); // no short flag!
    } else {
        // dont do this
        // args.printHelp();
    }

    if (!try args.parse()) {
        try args.printErrors(stdout_writer);
        return error.FailedToParse;
    }

    std.debug.print("verbose: {any}, emazing: {any}, bmazing: {any}\n", .{ verbose, emazing, bmazing });

    try testing.expectEqual(true, verbose);
    try testing.expectEqual(true, emazing);
    try testing.expectEqual(true, bmazing);
}
pub const SemVer = struct {
    const CustomT = enum { versioned, latest };
    const ChannelT = enum { stable, beta };
    t: CustomT,
    channel: ChannelT,
    pub fn default() SemVer {
        return .{};
    }
    pub fn init(string: []const u8) !SemVer {
        _ = string;

        return error.InvalidFormatting;
    }
};

const Config = union(enum) {
    update: struct {
        verbose: bool,
        custom_server_url: []const u8,
        version: SemVer,
        optional_value: ?u64,
    },
    start: struct {
        verbose: bool,
        custom_server_url: []const u8,
    },
};
fn howToUseConfig() !Config {
    var argsIterator = try std.process.ArgIterator.initWithAllocator(std.testing.allocator); // need to use different allocators
    defer argsIterator.deinit();

    const args = CliArgs.init(std.testing.allocator);

    // dont forget to deinit the internal temporary allocator
    // it is no longer needed when config is returned\
    // deinit can be called multiple times, the mememory could be cleaned before app is ran unline
    defer args.deinit();

    const stdout_writer = std.io.getStdOut().writer();

    // these are global and can be defined just once!
    var verbose = false;
    args.flag("", "verbose", &verbose, "print verbose information"); // no short flag!
    var custom_server_url: []const u8 = "https://myserver.com"; // default is here
    args.argument("s", "server", []const u8, &custom_server_url, "define custom server to use");

    if (args.subcommand("update", "updates the application from remote")) {
        var version = SemVer.default();
        args.argumentConverted(
            "v",
            "version",
            SemVer,
            SemVer.init,
            &version,
            "version to use",
        );

        var optional_value: ?u64 = null;
        args.argument("s", "", ?u64, &optional_value, "some optional value"); // use nullable type for optionals, can leave verbose to empty

        var file: []const u8 = undefined;
        args.argument("f", "file", []const u8, &file, "use local file instead");

        // custom checks are possible in this declarative approach
        if (file and optional_value) {
            args.addError(error.Duplicate, "cannot define both file and s", .{});
        }

        // how do i do multiple positional arguments
        // or how do i get a wildcard?
        var positional: []const u8 = undefined;
        args.positional(&positional, "last argument"); // will return an error if the positional argument is not present

        // const str = "hello world m8";
        // this returns an iterator
        // so things need to be iterated here
        // const it = std.mem.split(u8, str, " ");
        // for (it.next()) |value| {

        // }
        // these are one of the same
        // if help is triggered, then values are accumulated
        // errors are not recorded and therefore
        // maybe parse returns error here or false?
        if (!args.parse()) {
            try args.printErrors(stdout_writer);
            return error.FailedToParse;
        }

        // or return an iterator, after everything is done
        // errors here must be handled by the user.
        // i dont think i can make an array and pass it back
        // hmmmhmhmhmhmhmhmmhmhmmmm
        // the memory was allocated otherwise
        // so i can keep index in pre-allocated array and just keep it there
        // can this be returned in the config then?
        // or do I need to specify the maxsize? like:
        // args.positionalArray(50); // it will be ?[]const u8 values
        args.positionalIterator();

        // or the user will need to allocate things themselves
        // they will need an allocator for that

        // after parsing the positional arguments can be gotten
        // const positional = args.nextPositional();

        // // how do I validate this?
        // if (!positional) {
        //     return error.Hmmmm;
        // }

        // return the correct config
        // the args will be cleanup up via the defer!
        return Config{ .update = .{
            .verbose = verbose,
            .custom_server_url = custom_server_url,
            .version = version,
            .optional_value = optional_value,
        } };

        // or launch the app
        // args.deinit(); // DONT FORGET TO CLEAR THE MEMORY!
        // cleaning can be done automatically if defer args.init() is used, but its gonna exist during the entirety of lifetime of the application
        // try runUpdate(verbose, custom_server_url, version, optional_value);
    } else if (args.subscommand("start", "starts the app")) {

        //
        if (args.subcommand("server", "starts something")) {

            // more variables here

            if (args.parse()) {
                try args.printErrors(stdout_writer);
                return error.FailedToParse;
            }

            return Config{ .start = .{
                .verbose = verbose,
                .custom_server_url = custom_server_url,
            } };
        } else {
            // unknown command, print help
            args.printHelp(stdout_writer);
        }
    } else {
        // if nothing was matched, show the help menu.
        // nothing will be matched if -h or --help is passed
        // so -h and --help are reserved keywords
        // everything is accumulated by running the checks!
        try args.printHelp(stdout_writer);
    }
}
