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
            const meta_res = Meta.exec_meta_command(input[0..]);
            const should_continue = try Meta.handle_meta_result(meta_res, stdout);
            if (should_continue) { continue; }
            else break;
        }
        var s: statement.Statement = undefined;

        const prep_res = s.prepare_statement(input[0..]);
        const should_continue = try statement.handle_prepare_result(prep_res, stdout);
        if (should_continue) continue;

        const exe_res = (s.exec_statement(page_allocator, init.io, &dbtable));
        try statement.handle_execute_result(exe_res, stdout);
    }
}