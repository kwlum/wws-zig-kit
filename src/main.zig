const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const http = std.http;
const json = std.json;
const mem = std.mem;

pub const Input = struct {
    url: []const u8,
    method: http.Method,
    body: []const u8,
    headers: std.StringHashMap([]const u8),
    kv: std.StringHashMap([]const u8),
    arena: std.heap.ArenaAllocator,

    pub fn fromStdIn(inner_allocator: mem.Allocator, max_size: usize) !Input {
        var input: Input = .{
            .url = "",
            .method = http.Method.GET,
            .body = "",
            .headers = undefined,
            .kv = undefined,
            .arena = std.heap.ArenaAllocator.init(inner_allocator),
        };

        var allocator = input.arena.allocator();
        const stdin = std.io.getStdIn().reader();
        const input_string = try stdin.readAllAlloc(allocator, max_size);
        var json_parser = json.Parser.init(allocator, false);
        var json_tree = try json_parser.parse(input_string);

        input.url = json_tree.root.Object.get("url").?.String;
        input.body = json_tree.root.Object.get("body").?.String;
        input.headers = std.StringHashMap([]const u8).init(allocator);
        input.kv = std.StringHashMap([]const u8).init(allocator);

        const method_string = json_tree.root.Object.get("method").?.String;        
        if (ascii.eqlIgnoreCase(method_string, "head")) {
            input.method = http.Method.HEAD;
        } else if (ascii.eqlIgnoreCase(method_string, "post")) {
            input.method = http.Method.POST;
        } else if (ascii.eqlIgnoreCase(method_string, "put")) {
            input.method = http.Method.PUT;
        } else if (ascii.eqlIgnoreCase(method_string, "delete")) {
            input.method = http.Method.DELETE;
        } else if (ascii.eqlIgnoreCase(method_string, "connect")) {
            input.method = http.Method.CONNECT;
        } else if (ascii.eqlIgnoreCase(method_string, "options")) {
            input.method = http.Method.OPTIONS;
        } else if (ascii.eqlIgnoreCase(method_string, "trace")) {
            input.method = http.Method.TRACE;
        } else if (ascii.eqlIgnoreCase(method_string, "patch")) {
            input.method = http.Method.PATCH;
        }

        var tree_headers = json_tree.root.Object.get("headers").?.Object;
        var tree_headers_keys = tree_headers.keys();
        for (tree_headers_keys) |header_key| {
            try input.headers.put(header_key, tree_headers.get(header_key).?.String);
        }

        var tree_kv = json_tree.root.Object.get("kv").?.Object;
        var tree_kv_keys = tree_kv.keys();
        for (tree_kv_keys) |kv_key| {
            try input.kv.put(kv_key, tree_kv.get(kv_key).?.String);
        }

        return input;
    }

    pub fn deinit(self: *Input) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const Output = struct {
    data: []const u8 = "",
    headers: std.StringHashMap([]const u8),
    kv: std.StringHashMap([]const u8),
    status: http.Status = http.Status.ok,
    base64: bool = false,

    pub fn init(allocator: mem.Allocator, input: Input) !Output {        
        const kv = try input.kv.cloneWithAllocator(allocator);

        return .{
            .headers = std.StringHashMap([]const u8).init(allocator),
            .kv = kv,
        };
    }

    pub fn deinit(self: *Output) void {
        self.headers.deinit();
        self.kv.deinit();
        self.* = undefined;
    }

    pub fn toStdOut(self: Output) !void {
        const stdout_writer = std.io.getStdOut().writer();
        var buffered_writer = std.io.bufferedWriter(stdout_writer);
        const stdout = buffered_writer.writer();
        try stdout.print("{{\"status\":{},\"base64\":{},", .{ @enumToInt(self.status), self.base64 });

        const headers_len = self.headers.count();
        var i: usize = 0;
        var headers_entry_itr = self.headers.iterator();
        _ = try stdout.write("\"headers\":{");
        while (headers_entry_itr.next()) |entry| {
            try json.encodeJsonString(entry.key_ptr.*, .{}, stdout);
            _ = try stdout.write(":");
            try json.encodeJsonString(entry.value_ptr.*, .{}, stdout);

            if (i < headers_len - 1) {
                _ = try stdout.write(",");
            }

            i += 1;
        }
        _ = try stdout.write("},");

        const kv_len = self.kv.count();
        i = 0;
        var kv_entry_itr = self.kv.iterator();
        _ = try stdout.write("\"kv\":{");
        while (kv_entry_itr.next()) |entry| {
            try json.encodeJsonString(entry.key_ptr.*, .{}, stdout);
            _ = try stdout.write(":");
            try json.encodeJsonString(entry.value_ptr.*, .{}, stdout);

            if (i < kv_len - 1) {
                _ = try stdout.write(",");
            }

            i += 1;
        }
        _ = try stdout.write("},");

        _ = try stdout.write("\"data\":");
        try json.encodeJsonString(self.data, .{}, stdout);
        _ = try stdout.write("}");

        try buffered_writer.flush();
    }
};