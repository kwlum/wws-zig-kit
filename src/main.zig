const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const http = std.http;
const json = std.json;
const mem = std.mem;

pub const Cache = std.StringHashMap([]const u8);
pub const Headers = std.StringHashMap([]const u8);
pub const Params = std.StringHashMap([]const u8);

pub const Request = struct {
    method: http.Method,
    headers: Headers,
    params: Params,
    path: []const u8,
    query: []const u8,
    body: []const u8,
};

pub const Response = struct {
    status: http.Status,
    headers: Headers,
    body: std.ArrayList(u8).Writer,
};

pub fn run(comptime T: type, ctx: T, allocator: std.mem.Allocator, max_request_size: usize, handler: anytype) !void {
    const handler_type_info = @typeInfo(@TypeOf(handler));

    if (handler_type_info != .Fn) @compileError("handler is not a function.");

    const handler_fn = handler_type_info.Fn;

    if (handler_fn.args.len != 4) @compileError("handler requires 4 arguments.");

    if (handler_fn.args[0].arg_type orelse void != T)
        @compileError("handler first argument is not T.");

    if (handler_fn.args[1].arg_type orelse void != Request)
        @compileError("handler second argument is not Request.");

    if (handler_fn.args[2].arg_type orelse void != *Response)
        @compileError("handler third argument is not *Response.");

    if (handler_fn.args[3].arg_type orelse void != *Cache)
        @compileError("handler fourth argument is not *Cache.");

    const r = handler_fn.return_type.?;
    const r_info = @typeInfo(r);
    if (r != void and (r_info != .ErrorUnion or r_info.ErrorUnion.payload != void))
        @compileError("handle return type is not !void");

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Initialize Input and Output.
    var input: Input = undefined;
    var output: Output = undefined;
    try Input.fromStdIn(arena.allocator(), &input, max_request_size);
    try Output.init(arena.allocator(), &output);

    @call(.{}, handler, .{ ctx, input.request, &output.response, &input.cache }) catch |err| {
        output.response.status = http.Status.internal_server_error;

        output.response.headers.clearAndFree();
        try output.response.headers.put("content-type", "text/plain");

        output.data.clearAndFree();
        var writer = output.data.writer();
        try writer.writeAll("Internal Server Error! ");
        try writer.print("Error: {}", .{err});
    };

    // Write output to stdout.
    try output.toStdOut(&input.cache);
}

const Input = struct {
    request: Request,
    cache: Cache,

    fn fromStdIn(allocator: mem.Allocator, input: *Input, max_size: usize) !void {
        // Parse Input json string from stdin.
        const stdin = std.io.getStdIn().reader();
        const input_string = try stdin.readAllAlloc(allocator, max_size);
        var json_parser = json.Parser.init(allocator, false);
        const json_tree = try json_parser.parse(input_string);

        // Populate cache.
        input.cache = Cache.init(allocator);
        const tree_kv = json_tree.root.Object.get("kv").?.Object;
        const tree_kv_keys = tree_kv.keys();
        for (tree_kv_keys) |kv_key| {
            try input.cache.put(kv_key, tree_kv.get(kv_key).?.String);
        }

        // Construct Request.
        const request_path = if (json_tree.root.Object.get("url")) |a| a.String else "/";
        const request_body = if (json_tree.root.Object.get("body")) |a| a.String else "";
        input.request = .{
            .method = http.Method.GET,
            .headers = Headers.init(allocator),
            .params = Params.init(allocator),
            .path = request_path,
            .query = "",
            .body = request_body,
        };

        // Populate request params.
        if (json_tree.root.Object.get("params")) |a| {
            const params_tree = a.Object;
            const params_tree_keys = params_tree.keys();
            for (params_tree_keys) |key| {
                try input.request.params.put(key, params_tree.get(key).?.String);
            }
        }

        // Populate Request Headers.
        const tree_headers = json_tree.root.Object.get("headers").?.Object;
        const tree_headers_keys = tree_headers.keys();
        for (tree_headers_keys) |header_key| {
            try input.request.headers.put(header_key, tree_headers.get(header_key).?.String);
        }

        // Determine Request Method.
        var method_buffer: [16]u8 = undefined;
        const method_string = if (json_tree.root.Object.get("method")) |a|
            ascii.lowerString(&method_buffer, a.String)
        else
            "get";

        if (mem.eql(u8, method_string, "get")) {
            input.request.method = http.Method.GET;
        } else if (mem.eql(u8, method_string, "head")) {
            input.request.method = http.Method.HEAD;
        } else if (mem.eql(u8, method_string, "post")) {
            input.request.method = http.Method.POST;
        } else if (mem.eql(u8, method_string, "put")) {
            input.request.method = http.Method.PUT;
        } else if (mem.eql(u8, method_string, "delete")) {
            input.request.method = http.Method.DELETE;
        } else if (mem.eql(u8, method_string, "connect")) {
            input.request.method = http.Method.CONNECT;
        } else if (mem.eql(u8, method_string, "options")) {
            input.request.method = http.Method.OPTIONS;
        } else if (mem.eql(u8, method_string, "trace")) {
            input.request.method = http.Method.TRACE;
        } else if (mem.eql(u8, method_string, "patch")) {
            input.request.method = http.Method.PATCH;
        }
    }
};

const Output = struct {
    data: std.ArrayList(u8),
    response: Response,
    base64: bool = false,

    fn init(allocator: mem.Allocator, output: *Output) !void {
        output.base64 = false;
        output.data = std.ArrayList(u8).init(allocator);

        output.response.status = http.Status.ok;
        output.response.headers = Headers.init(allocator);
        output.response.body = output.data.writer();
    }

    fn toStdOut(self: *Output, cache: *const Cache) !void {
        const stdout_writer = std.io.getStdOut().writer();
        var buffered_writer = std.io.bufferedWriter(stdout_writer);
        const stdout = buffered_writer.writer();

        // Write base64 and status.
        try stdout.print("{{\"status\":{d},\"base64\":{},", .{ @enumToInt(self.response.status), self.base64 });

        // Write headers.
        const headers_len = self.response.headers.count();
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
        var cache_entry_itr = cache.iterator();
        _ = try stdout.write("\"kv\":{");
        while (cache_entry_itr.next()) |entry| {
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

        try buffered_writer.flush();
    }
};
