const std = @import("std");

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

        var input = try stdin.takeDelimiterInclusive('\n');

        if (std.mem.eql(u8, std.mem.trimEnd(u8, input[0..], "\n"), ".exit")){
            break;
        }

        try stdout.print("invalid query : {s}", .{input});
        try stdout.flush();
    }
}