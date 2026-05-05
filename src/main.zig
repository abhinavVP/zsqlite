const std = @import("std");
const Meta = @import("meta.zig");
const statement = @import("statement.zig");
const table = @import("table.zig");
pub fn main(init: std.process.Init) !void{
    var input_buffer: [1024]u8 = undefined;
    var reader = std.Io.File.stdin().reader(init.io, &input_buffer);
    const stdin = &reader.interface;

    var output_buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &output_buffer);
    const stdout = &writer.interface;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const page_allocator = arena.allocator();

    var dbtable = table.Table.init();
    
    while (true) {
        try stdout.print("zsql> ", .{});
        try stdout.flush();

        var rinput = try stdin.takeDelimiterInclusive('\n');
        var input  = std.mem.trimEnd(u8,rinput[0..], " \n");

        if (input[0] == '.'){
            switch (Meta.exec_meta_command(input[0..])) {
                Meta.MetaCommandResult.META_SUCCESS => continue,
                Meta.MetaCommandResult.META_EXIT => break,
                Meta.MetaCommandResult.META_UNRECOGNIZED => {
                    try stdout.print("error: unrecognized meta command : {s}\n", .{input});
                    continue;
                },
            }
        }
        var s: statement.Statement = undefined;

        switch (s.prepare_statement(input[0..])) {
            statement.PrepareResult.PREPARE_SUCCESS => {},
            statement.PrepareResult.PREPARE_INVALID_INPUT => {
                try stdout.print("error: invalid statement !\n", .{});
                try stdout.flush();
                continue;
            },
            statement.PrepareResult.PREPARE_SYNTAX_ERROR => {
                try stdout.print("error: invalid syntax !\n", .{});
                try stdout.flush();
                continue;
            },
        }

        switch (s.exec_statement(page_allocator, init.io, &dbtable)) {
            statement.ExecuteResult.EXECUTE_SUCCESS => {
                try stdout.print("done: statment ran successfully !\n", .{});
                try stdout.flush();
            },
            statement.ExecuteResult.EXECUTE_TABLE_EMPTY=> {
                try stdout.print("error: table is empty !\n", .{});
                try stdout.flush();
            },
            statement.ExecuteResult.EXECUTE_TABLE_FULL => {
                try stdout.print("error: database table is full, cant insert more !\n", .{});
                try stdout.flush();
            },
            else => {
                try stdout.print("error: out of program memory !\n", .{});
                try stdout.flush();
            }
        }
    }
}