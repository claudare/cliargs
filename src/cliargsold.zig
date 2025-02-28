const std = @import("std");
const debug = std.testing;
const assert = std.debug.assert;

const testing = std.testing;

// back to this
// if is_help is true, then types are captured as strings and presented that way
// i must check the ranges of the ints... u8 cannot accept the value of 257 or -1
// parsing at runtime needs to be done because i cant do a pointer to some randomass type such as u40
// as i will need to capture bits. but its pretty possible I think so...
// with variant 2 the issue of possible flags and possible arguments and possible positionals poses no difficulty...
// i really did not find a good parsing library

// what if all args are defined like a struct?
// ugh need to expriement
const ArgIterator = struct {
    const TokenStort = struct { name: u8, next_positional_idx: ?usize };
    const TokenLong = struct { name: []u8, next_positional_idx: ?usize };

    const Token0 = union(enum) {
        // conflict_positional_idx is set when its unclear weather the next coming
        short_noconflict: struct {
            name: u8,
        }, // position here is index of the original args, when multiple flags are together their indexes are the same
        short: struct { name: u8, next_positional_idx: ?usize }, // could be null if there is another argument after it
        long: struct { name: []u8, next_positional_idx: ?usize },
    };

    // this will return duplicates of (short_flag, short_arg) and (long_flag, long_arg) and (long_arg, positional)
    // const Token = union(enum) {
    //     // conflict_positional_idx is set when its unclear weather the next coming
    //     short_flag: struct { name: u8, conflict_positional_idx: ?usize }, // position here is index of the original args, when multiple flags are together their indexes are the same
    //     long_flag: struct { name: []u8, conflict_positional_idx: ?usize },
    //     short_arg: struct { name: u8, value: []u8 },
    //     long_arg: struct { name: []u8, value: []u8 },
    //     positional: struct { value: []u8 },
    // };

    // now it should have a value where applicable
    // like in tags there are no values. force = sign implementation
    const ArgType = union(enum) {
        flag: struct { name: []u8 },
        argument: struct { name: []u8, value: []u8 },
        positional: struct { value: []u8 },
        rest: []u8, // aka everything after "--"
    };

    const StoredPositional = struct {
        consumed: bool,
        name: []u8,
    };

    positional: std.ArrayList(StoredPositional), // all non tagged values
    short_map: std.AutoHashMap(u8, TokenStort),
    long_map: std.StringHashMap(TokenLong),
    unifiedMap: std.StringHashMap(TokenLong), // or use a single map to look things up, lookup short values (-u) and long values (--user)

    args: [][]u8,
    index: usize = 0,
    short_flag_group_index: usize = 0,

    // usually we skip the first value, should it be skipped outside?
    pub fn init(args: [][]u8) ArgIterator {
        return .{
            .args = args,
        };
    }

    pub fn parse(self: ArgIterator) !void {
        // parses the input internally, handles all short and long, non-tagged ones are noted!
        while (self.index < self.args.len) {
            const current = self.args[self.index];

            _ = current;
            // errors are added here too... fuckkk, so this is an implementation, this is the "main struct" of the cliargs
            // we add all of them depending on weather what they are
            // we always peek towards the next one
            // if this is a arg and next one is not a positional, we set index to 0
            // if next one is a positional, we add it and note the index in the unified map
            // this positional is then skipped
            //
            // when reading in the values, if the flag turns out to be an argument,
            // we mark the positional as consumed. It will be skipped when getting positional args
            // special case needs to be taken after --
            // accumulate all values and return them, but then I would need to allocate it
            // but that means the user is required to dupe it
            // same must be done when positionalSlice(allocator) is called!
            // I have figured all of this out
            // std.mem.join(std.testing.allocator, " ", self.args[5..]);
        }
    }

    // ugly but it works TM
    fn parseArg(value: []u8) !ArgType {
        // assert that the len is correct
        assert(value.len >= 2);

        if (value[0] == '-') {
            if (value.len >= 2) {
                if (value[1] == '-') {
                    if (value.len == 2) {
                        return .{ .split = {} };
                    }

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
            .positional = value,
        };
    }

    // this must return a token
    // but there could be two
    // so maybe one of them is [2]Token?
    pub fn next() ?[]u8 {
        const slice = std.ArrayList([]u8).init(std.testing.allocator);
        // const other = std.DoublyLinkedList([]u8);
        // other.append(list: *Self, new_node: *Node)
        // i append the value which was allocated before
        // so the string is still on the base allocator
        // this is an okay option for returning a slice [][]u8 for positionals
        slice.append(.{"lalala"});

        return null;
    }

    fn peak() ?[]u8 {
        //checks the next index
        // if out of bounds returns null!
        // otherwise returns the value
    }
};

pub const CliArgs = struct {
    allocator: std.heap.ArenaAllocator,
    deinited: bool = false,
    is_help: bool = false,

    // when pasing the input before the actual arguments are seen
    // need an array for subcommands
    // need an array for possible_flags
    // need an array for possible_arguments
    // need an array for possible_positionals
    //
    // possible is because there are ambiquities:
    // ./readfile -v build.zig // -v (--verbose) is a flag here
    // ./readfile -t binary build.zig // -t binary is an argument
    //
    // when flag "-v" is consumed, "build.zig" will be interpreted as a positional
    // when argument "-t" is consumed, "binary" will not be interpreted as a positional
    //
    // multiple flags such as "-xyz" are known to be only flags!

    pub fn init(temp_allocator: std.mem.Allocator) CliArgs {
        const alloc = std.heap.ArenaAllocator.init(temp_allocator);
        return .{
            .allocator = alloc,
        };
    }

    pub fn deinit(self: *CliArgs) void {
        if (self.deinited)
            return;
        self.allocator.deinit();
        self.deinited = true;
    }

    fn addError(self: *CliArgs, original_error: anyerror, comptime fmt: []const u8, args: anytype) !void {
        if (self.is_help)
            return;

        const msg = try std.fmt.allocPrint(self.allocator.child_allocator, fmt, args);

        _ = original_error;
        _ = msg;
    }

    pub fn subcommand(name: []const u8, description: []const u8) bool {
        _ = description;

        if (std.mem.eql(u8, name, "test"))
            return true;

        return false;
    }

    pub fn flag(short_name: []const u8, long_name: []const u8, description: []const u8) bool {
        _ = short_name;
        _ = long_name;
        _ = description;

        return true;
    }

    pub fn argument(short_name: []const u8, long_name: []const u8, T: type, default_value: T, description: []const u8) T {
        _ = short_name;
        _ = long_name;
        _ = description;

        return default_value;
    }

    /// custom conversion from strings
    pub fn argumentConverted(
        self: *CliArgs,
        short_name: []const u8,
        long_name: []const u8,
        T: type,
        default_value: T,
        convert_fn: fn (input: []const u8) anyerror!T,
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
            return converted_value;
        } catch |err| {
            self.addError(err, "failed to convert " ++ @typeName(T) ++ " from " ++ input); // example code
            return default_value;
        };
    }
    // get the positional by index, the subcommands are removed
    pub fn positionalByIndex(index: usize) ?[]const u8 {
        _ = index;
        return "lalaal";
    }

    pub fn nextPositional() ?[]const u8 {
        // gets next positional... would be nice to also provide an index?
        return null;
    }

    /// returns true if errors were encountered or if help was performed
    /// make sure to print diagnostics in this case
    /// and cleanup the allocator???
    pub fn parseError(self: CliArgs) bool {
        // instead

        const has_error = true;

        if (has_error) {
            // i cant deinit here
            self.deinit();
        }
        return has_error;
    }

    /// returns true if there is no errors and help was not triggered
    /// if should run, the temporary allocator will cleanup automatically
    /// calling deinit() again is fine
    pub fn shouldRun() bool {
        // instead
        return true;
    }

    /// this will print errors and/or help menu
    pub fn printErrors(out_writer: anytype) void {
        _ = out_writer;
        // out_writer.write("lalalal")
    }
    pub fn printHelp(out_writer: anytype) void {
        _ = out_writer;
        // out_writer.write("lalalal")
    }
};

fn runUpdate(verbose: bool, server_url: []const u8, version: []const u8) !void {
    // run the application here
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
    const args = CliArgs.init(std.testing.allocator);

    // dont forget to deinit the internal temporary allocator
    // it is no longer needed when config is returned
    defer args.deinit();

    const stdout_writer = std.io.getStdOut().writer();

    // these are global and can be defined just once!
    const verbose = args.flag("", "verbose", "print verbose information"); // no short flag!
    const custom_server_url = args.argument("s", "server", []const u8, "https://myserver.com", "define custom server to use");

    if (args.subcommand("update", "updates the application from remote")) {
        const version = args.argumentConverted(
            "v",
            "version",
            SemVer,
            SemVer.init("latest"),
            SemVer.init,
            "version to use",
        );
        const optional_value = args.argument("s", "swag", ?u64, null, "some optional value"); // use nullable type for optionals

        // these are one of the same
        // if help is triggered, then values are accumulated
        // errors are not recorded and therefore
        if (args.parseError()) {
            try args.printErrors(stdout_writer);
            return error.FailedToParse;
        }
        // launch the application here
        return Config{ .update = .{
            .verbose = verbose,
            .custom_server_url = custom_server_url,
            .version = version,
            .optional_value = optional_value,
        } };
    } else if (args.subscommand("start", "starts the app")) {

        //
        if (args.subcommand("server", "starts something")) {
            if (args.parseError()) {
                try args.printErrors(stdout_writer);
                return error.FailedToParse;
            }

            return Config{ .start = .{
                .verbose = verbose,
                .custom_server_url = custom_server_url,
            } };
        } else {
            // unknown command, print help
            args.printHelp();
        }
    } else {
        // if nothing was matched, show the help menu.
        // nothing will be matched if -h or --help is passed
        // so -h and --help are reserved keywords
        // everything is accumulated by running the checks!
        args.printHelp();
    }
}

/// this is example how to do this inline during main
/// but what if I wanted to do this as a return of the config instead?
fn howToUseMain() !void {
    const args = CliArgs.init(std.testing.allocator);
    const stdout_writer = std.io.getStdOut().writer();

    // these are global and can be defined just once!
    const verbose = args.flag("", "verbose", "print verbose information"); // no short flag!
    const custom_server_url = args.argument("s", "server", []const u8, "https://myserver.com", "define custom server to use");

    if (args.subcommand("update", "updates the application from remote")) {
        const version = args.argumentConverted(
            "v",
            "version",
            SemVer,
            SemVer.default(),
            SemVer.init,
            "version to use",
        );
        const optional_value = args.argument("s", "swag", ?u64, null, "some optional value"); // use nullable type for optionals

        _ = optional_value;

        // these are one of the same
        // if help is triggered, then values are accumulated
        // errors are not recorded and therefore
        if (args.parseError()) {
            return try args.printErrors(stdout_writer);
        }
        // launch the application here
        // cleanup memory right away as it will not be needed after parsing is complete
        // as all values are defined in variables above
        args.deinit();
        runUpdate(verbose, custom_server_url, version);
    } else if (args.subscommand("start", "starts the app")) {

        //
        if (args.subcommand("server", "starts server")) {
            // what if -h is called explicitly, like
            // start server -h or start server --help
            // the extraction of h flag was done before
            // so the errors were ignored and parse error will return true
            if (args.parseError()) {
                return try args.printErrors(stdout_writer);
            }

            // otherwise run the server
            // runServer(...args)
        } else if (args.subcommand("client", "starts client")) {
            //
        } else {
            // unknown command, print help
            // but how do i know that subcommand "update" was skipped?
            // upto this point these subcommands were checked:
            // "update" => false
            // "start" => true
            // "server" => false
            // "client" => false

            // therefore we are looking at start subcommand
            // help for "appName start"
            // [AVAILABLE SUBCOMMANDS]:
            //    "server", "starts server"
            //    "client", "starts client"

            args.printHelp(stdout_writer);
        }
    } else {
        // if nothing was matched, show the help menu for all options that were tried

        // do I need to explicitly tell this that the help menu is needed?
        // For example, what if the top-level arguments such as custom_server_url fails?
        // then an error will be triggered instead
        args.printHelp(stdout_writer);
    }
}

// maybe this?
