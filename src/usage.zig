const std = @import("std");
const debug = std.debug;
// I cant store args_iterator
// any() is available for writer
// but not for the arg_iterator...

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var arg_iterator = try std.process.ArgIterator.initWithAllocator(allocator);
    defer arg_iterator.deinit();

    if (!arg_iterator.skip()) {
        @panic("???");
    }

    // Give and a writer for error and help output and temporary allocator, which can be cleaned up after parse (its done automatically actually!)
    const cliArgs = Clargs(arg_iterator, std.io.getStdOut()).init(allocator);
    defer cliArgs.deinit(); // its safe to double call the deinit(). This is useful when something unexpected happens

    // global flags can be defined here
    // whatever path the code takes, the current scope will be available
    // it is a pointer, initialized to the default value
    // after parse() is called, the value will be set
    const urlFlagPtr = cliArgs.argument([]const u8, "u", "url", "http://default.example.com", "url of the remote server to");

    var version: *std.SemanticVersion = undefined;
    // put semantic version example here
    // convertFn is std.SemanticVersion.parse
    // where
    // argumentFn(
    //     self: *CliArgs,
    //     T: type,
    //     default_value: T,
    //     convert_fn: fn (input: []const u8) anyerror!T,
    //     short_name: []const u8,
    //     long_name: []const u8,
    //     description: []const u8,
    // ) *T

    // flags could use the same function as an argument, but we have to enforce that default is false
    // so maybe its better to just use another function
    const dryRun = cliArgs.flag("d", "dry-run", "dont apply any changes and just log it");

    if (cliArgs.subcommand("get", "gets something")) |sc| {
        const no_cache = cliArgs.flag("n", "no-cache", "do not cache the result");

        // nesting example
        if (cliArgs.subcommand("latest")) {
            if (cliArgs.parse()) {
                // parsing was okay
                // I dont see "bool" for fmt... https://zig.guide/standard-library/formatting-specifiers/
                debug.print("getting the latest version from {s}... skipping cache?? {any}\n", urlFlagPtr.*, no_cache.*);
                return;
            } else {
                // custom error handling
                cliArgs.printError();
                cliArgs.printHelp("");
            }
        }

        debug.print("getting version {any} from {s}... skipping cache?? {any}\n", version, urlFlagPtr.*, no_cache.*);
    } else if (cliArgs.subcommand("set", "sets something")) |sc| {

        // another example with

        // no short option defined
        const valuePtr = cliArgs.argument(u32, "", "value", "value to set");
    } else {
        cliArgs.printHelp(
            \\extra help message does in here
            \\I think i need to split the help messages into parts
            \\so that it can be formatted as needed
            \\since all of the subcommands did not return true, we have actually collected all available options
        );
        std.process.exit(1);
    }
}
// testing helpers also present
// const testing = std.testing;
// fn testit() !void {}
