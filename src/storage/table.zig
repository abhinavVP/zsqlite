const std = @import("std");
const pager = @import("pager.zig");
const Allocator = std.mem.Allocator;
const Node = @import("../btree/node.zig");

pub const ROW_SIZE = @sizeOf(u32) + @sizeOf([32]u8) + @sizeOf([255]u8);
pub const PAGE_SIZE: u32 = 4096;
pub const TABLE_MAX_PAGES:u32 = 100;
pub const ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
pub const TABLE_MAX_ROWS = TABLE_MAX_PAGES * ROWS_PER_PAGE;

const ID_OFFEST = @offsetOf(Row, "id");
const UNAME_OFFSET = @offsetOf(Row, "username");
const EMAIL_OFFSET = @offsetOf(Row, "email");

const ID_SIZE = @sizeOf(u32);
const UNAME_SIZE = @sizeOf([32]u8);
const EMAIL_SIZE = @sizeOf([255]u8);

pub const Row = struct {
    id: u32,
    username: [32]u8,
    email: [255]u8,

    pub fn init() Row {
        return Row{};
    }

    pub fn serialize(self: *const Row, dest: []u8) void {
        @memcpy(dest[ID_OFFEST..ID_OFFEST+ID_SIZE], std.mem.asBytes(&self.id));
        @memcpy(dest[UNAME_OFFSET..UNAME_OFFSET+UNAME_SIZE], &self.username);
        @memcpy(dest[EMAIL_OFFSET..EMAIL_OFFSET+EMAIL_SIZE], &self.email);
    }

    pub fn deserialize(source: []u8, dest: *Row) void {
        @memcpy(std.mem.asBytes(&dest.id), source[0..ID_SIZE]);
        @memcpy(&dest.username, source[UNAME_OFFSET..UNAME_OFFSET + UNAME_SIZE]);
        @memcpy(&dest.email, source[EMAIL_OFFSET..EMAIL_OFFSET + EMAIL_SIZE]);
    }
};


pub const Table = struct {
    root_page_no: u32,
    pager: *pager.Pager,

    pub fn db_open(path: []const u8, io: std.Io, allocator: Allocator) !Table{
        const p = try pager.Pager.open(allocator, path, io);

        if (p.n_pages == 0){
            const node = try p.get_page(io, allocator, 0);
            Node.leaf_init(node);
            Node.set_node_is_root(node, true);
        }

        return Table {
            .root_page_no = 0,
            .pager = p
        };
    }

    pub fn db_close(self: *Table, io: std.Io, allocator: std.mem.Allocator) !void {
        const p = self.pager;

        var buf:[1024]u8 = undefined;
        var w = std.Io.File.stdout().writer(io, &buf);
        const stdout = &w.interface;

        for (0..p.*.n_pages) |pgno| {
            if (p.*.pages[pgno] == null) {
                continue;
            }

            p.*.flush(io, pgno) catch |err| switch (err) {
                error.NullPage => continue,
                else => {
                    try stdout.print("error: got a write error when trying to flush on page {d}\n", .{pgno});
                    try stdout.flush();
                }
            };
        }

        p.*.file.close(io);
        allocator.destroy(p);
    }
};

pub const Cursor = struct {
    table: *Table,
    page_no: u32,
    cell_no: u32,
    end_of_table: bool,

    pub fn table_start(t: *Table, pg_allocator: Allocator, crs_allocator: Allocator, io: std.Io) !*Cursor{
        var c = try table_find(t, 0, pg_allocator, crs_allocator, io);
        const node = try t.pager.get_page(io, pg_allocator, c.page_no);
        c.end_of_table = (Node.leaf_num_cells_read(node) == 0);

        return c;
    }

    pub fn value_at_position(self: *Cursor, io: std.Io, pgallocator: Allocator) ![]u8{
        const pgno = self.page_no;
        const page = try self.table.pager.get_page(io, pgallocator, pgno);
        
        return Node.leaf_cell_value(page, self.cell_no);
    }

    pub fn advance(self: *Cursor, io: std.Io, pgallocator: Allocator) !void {
        const node = try self.table.pager.get_page(io, pgallocator, self.page_no);
        self.cell_no += 1;

        if (self.cell_no >= Node.leaf_num_cells_read(node)){
            const next_page = Node.leaf_next_node_read(node);
            if (next_page == 0){
                self.end_of_table = true;     
            } else {
                self.cell_no = 0;
                self.page_no = next_page;
            }
        }
    }

    pub fn table_find(t: *Table, key: u32, pg_allocator: Allocator, crs_allocator: Allocator, io: std.Io) !*Cursor{
        const root_no = t.root_page_no;
        const root_node = try t.pager.get_page(io, pg_allocator, root_no);

        return switch (Node.get_node_type(root_node)) {
            .NODE_TYPE_INTERNAL => try Node.internal_find_key(t, root_no, key, pg_allocator, crs_allocator, io),
            .NODE_TYPE_LEAF => try Node.leaf_find_key(t, root_no, key, pg_allocator, crs_allocator, io)
        };
    }
};