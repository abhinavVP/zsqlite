const std = @import("std");
const table = @import("../storage/table.zig");
const Node = @import("../btree/node.zig");
const Allocator = std.mem.Allocator;

pub const StatementType = enum {
    STATEMENT_INSERT,
    STATEMENT_SELECT
};

pub const PrepareResult = enum {
    PREPARE_SUCCESS,
    PREPARE_INVALID_INPUT,
    PREPARE_SYNTAX_ERROR,
    PREPARE_STRING_TOO_LONG,
    PREPARE_INVALID_INPUT_FOR_INT,
};

pub const ExecuteResult = enum {
    EXECUTE_SUCCESS,
    EXECUTE_FAILURE,
    EXECUTE_TABLE_FULL,
    EXECUTE_TABLE_EMPTY,
    EXECUTE_DUPLICATE_KEY
};

pub const Statement = struct {
    type: StatementType,
    row_to_insert: table.Row,

    pub fn prepare_statement(self: *Statement, input: []const u8) PrepareResult{
        if (input.len > 6 and std.mem.eql(u8, input[0..7], "insert ")){
            return self.parse_insert_statement(input[7..]);
        }

        if (input.len == 6 and std.mem.eql(u8, input[0..6], "select")){
            self.type = StatementType.STATEMENT_SELECT;
            return PrepareResult.PREPARE_SUCCESS;
        }

        return PrepareResult.PREPARE_INVALID_INPUT;
    }

    pub fn exec_statement(self: *Statement, io: std.Io, pg_allocator: Allocator,crs_allocator: Allocator, t: *table.Table) ExecuteResult{
        switch (self.type){
            StatementType.STATEMENT_INSERT => return self.exec_insert(io, pg_allocator, crs_allocator, t),
            StatementType.STATEMENT_SELECT => return exec_select(io, pg_allocator, crs_allocator, t),
        }
    }

    pub fn exec_insert(self: *Statement, io: std.Io, pg_allocator: Allocator, crs_allocator: Allocator, t: *table.Table) ExecuteResult {
        const node = t.pager.get_page(io, pg_allocator, t.root_page_no) catch return .EXECUTE_FAILURE;
        const n_cells = Node.leaf_num_cells_read(node);
        if (n_cells >=  Node.LEAF_NODE_MAX_CELLS){
            return .EXECUTE_TABLE_FULL;
        }

        const row = self.row_to_insert;
        const key_to_insert = row.id;
        const cursor = table.Cursor.table_find(t, key_to_insert, pg_allocator, crs_allocator, io) catch return .EXECUTE_FAILURE;

        if (cursor.cell_no < n_cells){
            const key_at_index = Node.leaf_cell_key_read(node, cursor.cell_no);
            if (key_at_index == key_to_insert)
                return .EXECUTE_DUPLICATE_KEY;
        }

        Node.leaf_insert(cursor, row.id, &row, io, pg_allocator) catch |err| switch (err) {
            error.NodeFull => return .EXECUTE_TABLE_FULL,
            else => return .EXECUTE_FAILURE
        };
        
        crs_allocator.destroy(cursor);
        return .EXECUTE_SUCCESS;
    }

    pub fn exec_select(io: std.Io, pg_allocator: Allocator, crs_allocator: Allocator, t: *table.Table) ExecuteResult {
        var output_buffer: [1024]u8 = undefined;
        var writer = std.Io.File.stdout().writer(io, &output_buffer);
        const stdout = &writer.interface;

        // if (t.n_rows == 0) return .EXECUTE_TABLE_EMPTY;

        var cursor = table.Cursor.table_start(t, crs_allocator, pg_allocator, io) catch return .EXECUTE_FAILURE;

        var row: table.Row = undefined;
        while (!(cursor.end_of_table)){
            var row_raw = cursor.value_at_position(io, pg_allocator) catch return .EXECUTE_FAILURE;
            table.Row.deserialize(row_raw[0..], &row);
            print_row(row, stdout) catch return .EXECUTE_FAILURE;
            cursor.advance(io, pg_allocator) catch {};
        }

        crs_allocator.destroy(cursor);

        return .EXECUTE_SUCCESS;
    }

    fn print_row(row: table.Row, writer: *std.Io.Writer) !void {
        try writer.print("({d}, {s}, {s})\n", .{row.id, std.mem.sliceTo(&row.username, 0), std.mem.sliceTo(&row.email, 0)});
        try writer.flush();
    }
    
    pub fn parse_insert_statement(self: *Statement, input: []const u8) PrepareResult{
        @memset(&self.row_to_insert.username, 0);
        @memset(&self.row_to_insert.email, 0);

        self.type = StatementType.STATEMENT_INSERT;
        var it = std.mem.splitScalar(u8, input, ' ');

        const id = it.next() orelse return .PREPARE_SYNTAX_ERROR;
        const idu32 = std.fmt.parseInt(u32, id, 10) catch return .PREPARE_INVALID_INPUT_FOR_INT;
        if (idu32 < 0) return .PREPARE_INVALID_INPUT_FOR_INT;
        self.row_to_insert.id = idu32;

        const uname = it.next() orelse return .PREPARE_SYNTAX_ERROR;
        if (uname.len > 32) return .PREPARE_STRING_TOO_LONG;
        @memmove(self.row_to_insert.username[0..uname.len], uname);

        const email = it.next() orelse return .PREPARE_SYNTAX_ERROR;
        if (email.len > 255) return .PREPARE_STRING_TOO_LONG;
        @memmove(self.row_to_insert.email[0..email.len], email);

        return .PREPARE_SUCCESS;   
    }
};

pub fn handle_prepare_result(result: PrepareResult, stdout: *std.Io.Writer) !bool{
    switch (result) {
        .PREPARE_SUCCESS => return false,
        .PREPARE_INVALID_INPUT => {
            try stdout.print("error: invalid statement !\n", .{});
            try stdout.flush();
            return true;
        },
        .PREPARE_SYNTAX_ERROR => {
            try stdout.print("error: invalid syntax !\n", .{});
            try stdout.flush();
            return true;
        },
        .PREPARE_INVALID_INPUT_FOR_INT => {
            try stdout.print("error: invalid input for integer type !\n", .{});
            try stdout.flush();
            return true;
        },
        .PREPARE_STRING_TOO_LONG => {
            try stdout.print("error: string too long !\n", .{});
            try stdout.flush();
            return true;
        }
    }
}

pub fn handle_execute_result(result: ExecuteResult, stdout: *std.Io.Writer) !void {
    switch (result) {
        .EXECUTE_SUCCESS => {
            try stdout.print("done: statment ran successfully !\n", .{});
            try stdout.flush();
        },
        .EXECUTE_TABLE_EMPTY=> {
            try stdout.print("error: table is empty !\n", .{});
            try stdout.flush();
        },
        .EXECUTE_TABLE_FULL => {
            try stdout.print("error: database table is full, cant insert more !\n", .{});
            try stdout.flush();
        },
        else => {
            try stdout.print("error: out of program memory !\n", .{});
            try stdout.flush();
        }
    }
}
