const std = @import("std");
const table = @import("../storage/table.zig");
const Allocator = std.mem.Allocator;

pub const NODE_TYPE = enum {
    NODE_TYPE_LEAF,
    NODE_TYPE_INTERNAL
};

// common node header:
const NODE_TYPE_SIZE: u32 = @sizeOf(u8);
const NODE_TYPE_OFFSET: u32 = 0;
const IS_ROOT_SIZE: u32 = @sizeOf(u8);
const IS_ROOT_OFFSET = NODE_TYPE_SIZE;
const PARENT_POINTER_SIZE: u32 = @sizeOf(u32);
const PARENT_POINTER_OFFSET = IS_ROOT_OFFSET + IS_ROOT_SIZE;
const COMMON_NODE_HEADER_SIZE = NODE_TYPE_SIZE + IS_ROOT_SIZE + PARENT_POINTER_SIZE;

// additional header stuff for leaf node:
const LEAF_NODE_N_CELLS_SIZE: u32 = @sizeOf(u32);
const LEAF_NODE_N_CELLS_OFFSET = COMMON_NODE_HEADER_SIZE;
const LEAF_NODE_NEXT_LEAF_SIZE: u32 = @sizeOf(u32);
const LEAF_NODE_NEXT_LEAF_OFFSET: u32 = LEAF_NODE_N_CELLS_OFFSET + LEAF_NODE_N_CELLS_SIZE;
const LEAF_NODE_HEADER_SIZE: u32 = COMMON_NODE_HEADER_SIZE + LEAF_NODE_N_CELLS_SIZE + LEAF_NODE_NEXT_LEAF_SIZE;

// leaf node body:
const LEAF_NODE_KEY_SIZE: u32 = @sizeOf(u32);
const LEAF_NODE_KEY_OFFSET: u32 = 0;
const LEAF_NODE_VALUE_SIZE: u32 = table.ROW_SIZE;
const LEAF_NODE_VALUE_OFFSET = LEAF_NODE_KEY_OFFSET + LEAF_NODE_KEY_SIZE;
const LEAF_NODE_CELL_SIZE = LEAF_NODE_KEY_SIZE + LEAF_NODE_VALUE_SIZE;
const LEAF_NODE_SPACE_FOR_CELLS = table.PAGE_SIZE - LEAF_NODE_HEADER_SIZE;
const LEAF_NODE_MAX_CELLS = LEAF_NODE_SPACE_FOR_CELLS / LEAF_NODE_CELL_SIZE;

// internal node header stuff:
const INTERNAL_NODE_NUM_KEYS_SIZE: u32 = @sizeOf(u32);
const INTERNAL_NODE_NUM_KEYS_OFFSET: u32 = COMMON_NODE_HEADER_SIZE;
const INTERNAL_NODE_RIGHT_CHILD_SIZE: u32 = @sizeOf(u32);
const INTERNAL_NODE_RIGHT_CHILD_OFFSET: u32 = INTERNAL_NODE_NUM_KEYS_OFFSET + INTERNAL_NODE_NUM_KEYS_SIZE;
const INTERNAL_NODE_HEADER_SIZE: u32 = COMMON_NODE_HEADER_SIZE + INTERNAL_NODE_NUM_KEYS_SIZE + INTERNAL_NODE_RIGHT_CHILD_SIZE;

// internal node body:
const INTERNAL_NODE_KEY_SIZE: u32 = @sizeOf(u32);
const INTERNAL_NODE_CHILD_SIZE: u32 = @sizeOf(u32);
const INTERNAL_NODE_CELL_SIZE: u32 = INTERNAL_NODE_CHILD_SIZE + INTERNAL_NODE_KEY_SIZE;

// extra
const LEAF_NODE_RIGHT_SPLIT_COUNT: u32 = (LEAF_NODE_MAX_CELLS + 1) / 2;
const LEAF_NODE_LEFT_SPLIT_COUNT = (LEAF_NODE_MAX_CELLS + 1) - LEAF_NODE_RIGHT_SPLIT_COUNT;

pub fn set_node_type(node: []u8, node_type: NODE_TYPE) void {
    node[NODE_TYPE_OFFSET] = @intFromEnum(node_type);
}

pub fn get_node_type(node: []u8) NODE_TYPE {
    return @enumFromInt(node[NODE_TYPE_OFFSET]);
}

pub fn set_node_is_root(node: []u8, is_root: bool) void {
    node[IS_ROOT_OFFSET] = @as(u8, @intFromBool(is_root));
}

pub fn get_node_is_root(node: []u8) bool {
    return node[IS_ROOT_OFFSET] == 1;
}

pub fn get_node_max_key(node: []u8) u32 {
    switch (get_node_type(node)) {
        .NODE_TYPE_INTERNAL => return internal_key_read(node, internal_num_keys_read(node)-1),
        .NODE_TYPE_LEAF => return leaf_cell_key_read(node, leaf_num_cells_read(node)-1)
    }
}

// LEAF NODE FUNCTIONS
pub fn leaf_init(node: []u8) void{
    @memset(node, 0);
    leaf_num_cells_write(node, 0);
    set_node_type(node, .NODE_TYPE_LEAF);
    set_node_is_root(node, false);
    leaf_next_node_write(node, 0);
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

pub fn leaf_next_node_read(node: []u8) u32 {
    return std.mem.readInt(u32, node[LEAF_NODE_NEXT_LEAF_OFFSET..][0..LEAF_NODE_NEXT_LEAF_SIZE], .little);
}

pub fn leaf_next_node_write(node: []u8, sibling: u32) void {
    std.mem.writeInt(u32, node[LEAF_NODE_NEXT_LEAF_OFFSET..][0..LEAF_NODE_NEXT_LEAF_SIZE], sibling, .little);
}

pub fn leaf_insert(c: *table.Cursor, key: u32, row: *const table.Row, io: std.Io, allocator: std.mem.Allocator) !void {
    const node = try c.table.pager.get_page(io, allocator, c.page_no);
    const n_cells = leaf_num_cells_read(node);
    
    if (n_cells >= LEAF_NODE_MAX_CELLS) {
        try leaf_split_and_insert(c, node, row, allocator, io);
        return;
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

pub fn leaf_find_key(t: *table.Table, pg_no: u32, key:u32, pg_allocator: Allocator, crs_allocator: Allocator, io: std.Io) !*table.Cursor {
    const node = try t.pager.get_page(io, pg_allocator, t.root_page_no);
    const index = leaf_search_cell_no(node, key);

    var cursor = try crs_allocator.create(table.Cursor);
    cursor.table = t;
    cursor.page_no = pg_no;
    cursor.cell_no = index;

    return cursor;
}

fn leaf_search_cell_no(node: []u8 , key: u32) u32 {
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

pub fn leaf_split_and_insert(c: *table.Cursor, old_node: []u8, row: *const table.Row, pg_allocator: Allocator, io: std.Io) !void {
    const old_pgno = c.page_no;
    const new_pgno = c.table.pager.get_unused_page_no();
    const new_node = try c.table.pager.get_page(io, pg_allocator, new_pgno);
    leaf_init(new_node);

    var i: u32 = LEAF_NODE_MAX_CELLS;
    while (i>=0) : (i-=1) {
        var dest: []u8 = undefined;

        if (i >= LEAF_NODE_LEFT_SPLIT_COUNT){
            dest = new_node;
        } else {
            dest = old_node;
        }

        const index = @as(u32, i) % LEAF_NODE_LEFT_SPLIT_COUNT;

        if (i == c.cell_no){
            row.serialize(leaf_cell_value(dest, index)[0..]);
        } else if (i > c.cell_no){
            @memcpy(leaf_cell(dest, index)[0..], leaf_cell(old_node, i-1));
        } else if (i  >= LEAF_NODE_LEFT_SPLIT_COUNT){
            @memcpy(leaf_cell(dest, index)[0..], leaf_cell(old_node, i));
        }

        if (i==0) break;
    }

    leaf_num_cells_write(new_node, LEAF_NODE_RIGHT_SPLIT_COUNT);
    leaf_num_cells_write(old_node, LEAF_NODE_LEFT_SPLIT_COUNT);
    leaf_next_node_write(new_node, old_pgno);
    leaf_next_node_write(old_node, new_pgno);

    if (get_node_is_root(old_node)){
        try create_new_root(c.table, new_pgno, io, pg_allocator);
    } else {
        return error.ParentUpdateNotImplemented;
    }
}

// INTERNAL NODE FUNCTIONS
pub fn internal_init(node: []u8) void {
    @memset(node, 0);
    set_node_type(node, .NODE_TYPE_INTERNAL);
    set_node_is_root(node, false);
    internal_num_keys_write(node, 0);
}

pub fn internal_num_keys_read(node: []u8) u32 {
    return std.mem.readInt(u32, node[INTERNAL_NODE_NUM_KEYS_OFFSET..][0..INTERNAL_NODE_NUM_KEYS_SIZE], .little);
}

pub fn internal_num_keys_write(node: []u8, value: u32) void {
    std.mem.writeInt(u32, node[INTERNAL_NODE_NUM_KEYS_OFFSET..][0..INTERNAL_NODE_NUM_KEYS_SIZE], value, .little);
}

pub fn internal_right_child_read(node: []u8) u32 {
    return std.mem.readInt(u32, node[INTERNAL_NODE_RIGHT_CHILD_OFFSET..][0..INTERNAL_NODE_RIGHT_CHILD_SIZE], .little);
}

pub fn internal_right_child_write(node: []u8, value: u32) void {
    std.mem.writeInt(u32, node[INTERNAL_NODE_RIGHT_CHILD_OFFSET..][0..INTERNAL_NODE_RIGHT_CHILD_SIZE], value, .little);
}

pub fn internal_keyed_child_read(node: []u8, cell_no: u32) u32 {
    const offset = INTERNAL_NODE_HEADER_SIZE + (cell_no*INTERNAL_NODE_CELL_SIZE);
    return std.mem.readInt(u32, node[offset..][0..INTERNAL_NODE_CHILD_SIZE], .little);
}

pub fn internal_keyed_child_write(node: []u8, cell_no:u32, value: u32) void {
    const offset = INTERNAL_NODE_HEADER_SIZE + (cell_no*INTERNAL_NODE_CELL_SIZE);
    std.mem.writeInt(u32, node[offset..][0..INTERNAL_NODE_CHILD_SIZE], value, .little);
}

pub fn internal_key_read(node: []u8, cell_no: u32) u32 {
    const offset = INTERNAL_NODE_HEADER_SIZE + (cell_no*INTERNAL_NODE_CELL_SIZE) + INTERNAL_NODE_CHILD_SIZE;
    return std.mem.readInt(u32, node[offset..][0..INTERNAL_NODE_KEY_SIZE], .little);
}

pub fn internal_key_write(node: []u8, cell_no: u32, value: u32) void {
    const offset = INTERNAL_NODE_HEADER_SIZE + (cell_no*INTERNAL_NODE_CELL_SIZE) + INTERNAL_NODE_CHILD_SIZE;
    std.mem.writeInt(u32, node[offset..][0..INTERNAL_NODE_KEY_SIZE], value, .little);
}

pub fn internal_node_child(node: []u8, child_no: u32) !u32 {
    const nkeys = internal_num_keys_read(node);

    if (child_no > nkeys or child_no < 0){
        return error.InvalidKey;
    }
    if (child_no == nkeys){
        return internal_right_child_read(node);
    }
    else {
        return internal_keyed_child_read(node, child_no);
    }
}

pub fn internal_find_key(t: *table.Table, pgno: u32, key: u32, pg_allocator: Allocator, crs_allocator: Allocator, io: std.Io) anyerror!*table.Cursor {
    const node = try t.pager.get_page(io, pg_allocator, pgno);
    const child_index = internal_search_index(node, key);
    const child_no = try internal_node_child(node, child_index);
    const child = try t.pager.get_page(io, pg_allocator, child_no);

    return switch (get_node_type(child)) {
        .NODE_TYPE_INTERNAL => try internal_find_key(t, child_no, key, pg_allocator, crs_allocator, io),
        .NODE_TYPE_LEAF => try leaf_find_key(t, child_no, key, pg_allocator, crs_allocator, io)
    };
}

fn internal_search_index(node: []u8, key: u32) u32{
    var low:u32 = 0;
    var high = internal_num_keys_read(node);

    while (low < high) {
        const mid = (low+high)/2;
        const key_at_mid = internal_key_read(node, mid);

        if (key_at_mid >= key){
            high = mid;
        }
        else {
            low = mid+1;
        }
    }

    return low;
}

// commmon operations

pub fn create_new_root(t: *table.Table, right_pgno: u32, io: std.Io, pg_allocator: Allocator) !void {
    const root = try t.pager.get_page(io, pg_allocator, t.root_page_no);
    const left_pgno = t.pager.get_unused_page_no();
    const left = try t.pager.get_page(io, pg_allocator, left_pgno);

    @memcpy(left, root);
    set_node_is_root(left, false);

    internal_init(root);
    set_node_is_root(root, true);
    internal_num_keys_write(root, 1);
    internal_keyed_child_write(root, 0, left_pgno);
    internal_key_write(root, 0, get_node_max_key(left));
    internal_right_child_write(root, right_pgno);
}