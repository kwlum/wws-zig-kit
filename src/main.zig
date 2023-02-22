const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const http = std.http;
const json = std.json;
const mem = std.mem;

pub const Request = struct {
    method: http.Method,
    headers: std.StringHashMap([]const u8),
    path: []const u8,
    query: []const u8,
    body: []const u8,
};

pub const Response = struct {
    status: http.Status = http.Status.ok,
    headers: std.StringHashMap([]const u8),
    body: std.ArrayList(u8).Writer,
    allocator: mem.Allocator,

    fn header(self: *Response, name: []const u8, value: []const u8) !void {
        const header_name = try self.allocator.dupe(name);
        const header_value = try self.allocator.dupe(value);
        try self.headers.put(header_name, header_value);
    }

    fn deinit(self: *Response) void {
        var entry_itr = self.headers.iterator();
        while (entry_itr.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        self.* = undefined;
    }
};

pub const Input = struct {
    request: *Request,
    kv: std.StringHashMap([]const u8),
    arena: *std.heap.ArenaAllocator,

    pub fn fromStdIn(child_allocator: mem.Allocator, max_size: usize) !Input {
        const arena = try child_allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(child_allocator);
        const allocator = arena.allocator();

        // Parse Input json string from stdin.
        const stdin = std.io.getStdIn().reader();
        const input_string = try stdin.readAllAlloc(allocator, max_size);
        var json_parser = json.Parser.init(allocator, false);
        const json_tree = try json_parser.parse(input_string);

        // Populate KV.
        const kv = try allocator.create(std.StringHashMap([]const u8));
        kv.* = std.StringHashMap([]const u8).init(allocator);
        const tree_kv = json_tree.root.Object.get("kv").?.Object;
        const tree_kv_keys = tree_kv.keys();
        std.debug.print("in kv len: '{d}''\n", .{tree_kv_keys.len});
        for (tree_kv_keys) |kv_key| {
            std.debug.print("in kv: '{s}''\n", .{kv_key});
            try kv.put(kv_key, tree_kv.get(kv_key).?.String);
        }

        // Construct Request.
        const request = try allocator.create(Request);
        const request_path = if (json_tree.root.Object.get("url")) |a| a.String else "/";
        const request_body = if (json_tree.root.Object.get("body")) |a| a.String else "";
        request.* = .{
            .method = http.Method.GET,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .path = request_path,
            .query = "",
            .body = request_body,
        };

        std.debug.print("input body: '{s}'\n", .{request.body});

        // Populate Request Headers.
        const tree_headers = json_tree.root.Object.get("headers").?.Object;
        const tree_headers_keys = tree_headers.keys();
        for (tree_headers_keys) |header_key| {
            try request.headers.put(header_key, tree_headers.get(header_key).?.String);
        }

        // Determine Request Method.
        var method_buffer: [16]u8 = undefined;
        const method_string = if (json_tree.root.Object.get("method")) |a|
            ascii.lowerString(&method_buffer, a.String)
        else
            "get";

        if (mem.eql(u8, method_string, "get")) {
            request.method = http.Method.GET;
        } else if (mem.eql(u8, method_string, "head")) {
            request.method = http.Method.HEAD;
        } else if (mem.eql(u8, method_string, "post")) {
            request.method = http.Method.POST;
        } else if (mem.eql(u8, method_string, "put")) {
            request.method = http.Method.PUT;
        } else if (mem.eql(u8, method_string, "delete")) {
            request.method = http.Method.DELETE;
        } else if (mem.eql(u8, method_string, "connect")) {
            request.method = http.Method.CONNECT;
        } else if (mem.eql(u8, method_string, "options")) {
            request.method = http.Method.OPTIONS;
        } else if (mem.eql(u8, method_string, "trace")) {
            request.method = http.Method.TRACE;
        } else if (mem.eql(u8, method_string, "patch")) {
            request.method = http.Method.PATCH;
        }

        return .{
            .request = request,
            .kv = kv,
            .arena = arena,
        };
    }

    pub fn deinit(self: *Input) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const Output = struct {
    data: *std.ArrayList(u8),
    base64: bool = false,
    response: *Response,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator) !Output {
        const data = try allocator.create(std.ArrayList(u8));
        data.* = std.ArrayList(u8).init(allocator);

        const response = try allocator.create(Response);
        response.* = .{
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = data.writer(),
            .allocator = allocator,
        };

        return .{
            .data = data,
            .response = response,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Output) void {
        self.response.deinit();
        self.data.deinit();
        self.allocator.destroy(self.response);
        self.allocator.destroy(self.data);
        self.* = undefined;
    }

    pub fn toStdOut(self: *Output, cache: *const std.StringHashMap([]const u8)) !void {
        const stdout_writer = std.io.getStdOut().writer();
        var buffered_writer = std.io.bufferedWriter(stdout_writer);
        const stdout = buffered_writer.writer();

        // Write base64 and status.
        try stdout.print("{{\"status\":{d},\"base64\":{},", .{ @enumToInt(self.response.status), self.base64 });

        // Write headers.
        const headers_len = self.response.headers.count();
        std.debug.print("header len: {d}\n", .{headers_len});
        var i: usize = 0;
        var headers_entry_itr = self.response.headers.iterator();
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

        // Write KV.
        i = 0;
        const cache_len = cache.count();
        std.debug.print("out cache: {}\n", .{cache_len});
        var cache_entry_itr = cache.iterator();
        _ = try stdout.write("\"kv\":{");
        while (cache_entry_itr.next()) |entry| {
            std.debug.print("out kv: '{s}' '{s}'\n", .{entry.key_ptr.*, entry.value_ptr.*});
            try json.encodeJsonString(entry.key_ptr.*, .{}, stdout);
            _ = try stdout.write(":");
            try json.encodeJsonString(entry.value_ptr.*, .{}, stdout);

            if (i < cache_len - 1) {
                _ = try stdout.write(",");
            }

            i += 1;
        }
        _ = try stdout.write("},");

        // Write data.
        _ = try stdout.write("\"data\":");
        try json.encodeJsonString(self.data.items, .{}, stdout);
        _ = try stdout.write("}");

        std.debug.print("out body: '{s}'\n", .{self.data.items});

        try buffered_writer.flush();
    }
};
