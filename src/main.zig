const std = @import("std");
const Meta = @import("meta.zig");
const statement = @import("statement.zig");
pub fn main(init: std.process.Init) !void{
    var input_buffer: [1024]u8 = undefined;
    var reader = std.Io.File.stdin().reader(init.io, &input_buffer);
    const stdin = &reader.interface;

    var output_buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &output_buffer);
    const stdout = &writer.interface;

    while (true) {
        try stdout.print("zsql> ", .{});
        try stdout.flush();

        var rinput = try stdin.takeDelimiterInclusive('\n');
        var input  = std.mem.trimEnd(u8,rinput[0..], "\n");

        if (input[0] == '.'){
            switch (Meta.exec_meta_command(input[0..])) {
                Meta.MetaCommandResult.META_SUCCESS => continue,
                Meta.MetaCommandResult.META_EXIT => break,
                Meta.MetaCommandResult.META_UNRECOGNIZED => {
                    try stdout.print("unrecognized meta command : {s}\n", .{input});
                    continue;
                },
            }
        }

        var s: statement.Statement = undefined;
        switch (s.prepare_statement(input[0..])) {
            statement.PrepareResult.PREPARE_SUCCESS => try s.exec_statement(stdout),
            statement.PrepareResult.PREPARE_INVALID_INPUT => {
                try stdout.print("invalid statement !\n", .{});
                try stdout.flush();
            },
            statement.PrepareResult.PREPARE_SYNTAX_ERROR => {
                try stdout.print("invalid syntax !\n", .{});
                try stdout.flush();
            }
        }
    }
}