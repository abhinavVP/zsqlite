const std = @import("std");
const table = @import("../storage/table.zig");
const Allocator = std.mem.Allocator;

pub const NODE_TYPE = enum {
    NODE_TYPE_LEAF,
    NODE_TYPE_INTERNAL
};

// common node header:
pub const NODE_TYPE_SIZE: u32 = @sizeOf(u8);
pub const NODE_TYPE_OFFSET: u32 = 0;
pub const IS_ROOT_SIZE: u32 = @sizeOf(u8);
pub const IS_ROOT_OFFSET = NODE_TYPE_SIZE;
pub const PARENT_POINTER_SIZE: u32 = @sizeOf(u32);
pub const PARENT_POINTER_OFFSET = IS_ROOT_OFFSET + IS_ROOT_SIZE;
pub const COMMON_NODE_HEADER_SIZE = NODE_TYPE_SIZE + IS_ROOT_SIZE + PARENT_POINTER_SIZE;

// additional header stuff for leaf node:
pub const LEAF_NODE_N_CELLS_SIZE: u32 = @sizeOf(u32);
pub const LEAF_NODE_N_CELLS_OFFSET = COMMON_NODE_HEADER_SIZE;
pub const LEAF_NODE_HEADER_SIZE = COMMON_NODE_HEADER_SIZE + LEAF_NODE_N_CELLS_SIZE;

// leaf node body:
pub const LEAF_NODE_KEY_SIZE:u32 = @sizeOf(u32);
pub const LEAF_NODE_KEY_OFFSET:u32 = 0;
pub const LEAF_NODE_VALUE_SIZE = table.ROW_SIZE;
pub const LEAF_NODE_VALUE_OFFSET = LEAF_NODE_KEY_OFFSET + LEAF_NODE_KEY_SIZE;
pub const LEAF_NODE_CELL_SIZE = LEAF_NODE_KEY_SIZE + LEAF_NODE_VALUE_SIZE;
pub const LEAF_NODE_SPACE_FOR_CELLS = table.PAGE_SIZE - LEAF_NODE_HEADER_SIZE;
pub const LEAF_NODE_MAX_CELLS = LEAF_NODE_SPACE_FOR_CELLS / LEAF_NODE_CELL_SIZE;

pub fn leaf_init(n: []u8) void{
    leaf_num_cells_write(n, 0);
    set_node_type(n, .NODE_TYPE_LEAF);
}

pub fn leaf_num_cells_read(node: []u8) u32 {
    return std.mem.readInt(u32, node[LEAF_NODE_N_CELLS_OFFSET..][0..LEAF_NODE_N_CELLS_SIZE], .little);
}

pub fn leaf_num_cells_write(node: []u8, val: u32) void {
    std.mem.writeInt(u32, node[LEAF_NODE_N_CELLS_OFFSET..][0..LEAF_NODE_N_CELLS_SIZE], val, .little);
}

fn leaf_cell(node: []u8, cell_no: u32) []u8 {
    const offset = LEAF_NODE_HEADER_SIZE + cell_no * LEAF_NODE_CELL_SIZE;
    return node[offset..offset + LEAF_NODE_CELL_SIZE];
}

pub fn leaf_cell_key_read(node: []u8, cell_no: u32) u32 {
    return std.mem.readInt(u32, 
        leaf_cell(node, cell_no)[LEAF_NODE_KEY_OFFSET..][0..LEAF_NODE_KEY_SIZE], 
        .little);
}

pub fn leaf_cell_key_write(node: []u8, cell_no: u32, key: u32) void {
    std.mem.writeInt(u32, 
        leaf_cell(node, cell_no)[LEAF_NODE_KEY_OFFSET..][0..LEAF_NODE_KEY_SIZE],
        key,
        .little);
}

pub fn leaf_cell_value(node: []u8, cell_no: u32) []u8 {
    return leaf_cell(node, cell_no)[LEAF_NODE_VALUE_OFFSET..][0..LEAF_NODE_VALUE_SIZE];
}

pub fn leaf_insert(c: *table.Cursor, key: u32, row: *const table.Row, io: std.Io, allocator: std.mem.Allocator) !void {
    const node = try c.db.pager.get_page(io, allocator, c.page_no);
    const n_cells = leaf_num_cells_read(node);
    
    if (n_cells >= LEAF_NODE_MAX_CELLS) {
        return error.NodeFull;
    }

    if (c.cell_no < n_cells){
        var i: u32 = n_cells;
        while (i > c.cell_no) : (i -= 1) {
            @memcpy(leaf_cell(node, i), leaf_cell(node, i-1));
        }
    }

    leaf_num_cells_write(node, n_cells + 1);
    leaf_cell_key_write(node, c.cell_no, key);

    row.serialize(leaf_cell_value(node, c.cell_no));
}

pub fn leaf_find(t: *table.Table, pg_no: u32, key:u32, pg_allocator: Allocator, crs_allocator: Allocator, io: std.Io) !*table.Cursor {
    const node = try t.pager.get_page(io, pg_allocator, t.root_page_no);

    var cursor = try crs_allocator.create(table.Cursor);
    cursor.db = t;
    cursor.page_no = pg_no;

    const index = leaf_binary_search_key(node, key);
    cursor.cell_no = index;

    return cursor;
}

fn leaf_binary_search_key(node: []u8 , key: u32) u32 {
    var low: u32 = 0;
    var high: u32 = leaf_num_cells_read(node);

    while (low < high) {
        const mid = (low+high)/2;
        const key_at_mid = leaf_cell_key_read(node, mid);

        if (key == key_at_mid){
            return mid;
        }
        else if(key < key_at_mid){
            high = mid;
        }
        else {
            low = mid+1;
        }
    }

    return low;
}

pub fn set_node_type(node: []u8, node_type: NODE_TYPE) void {
    node[NODE_TYPE_OFFSET] = @intFromEnum(node_type);
}

pub fn get_node_type(node: []u8) NODE_TYPE {
    return @enumFromInt(node[NODE_TYPE_OFFSET]);
}