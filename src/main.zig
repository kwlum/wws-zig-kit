const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const http = std.http;
const json = std.json;
const mem = std.mem;

pub const Params = std.StringHashMap([]const u8);

pub fn Route(comptime Context: type) type {
    return struct {
        allocator: mem.Allocator,
        max_request_size: usize,

        const Self = @This();
        const HandleFn = fn (Context, Request, *Response, *Cache) anyerror!void;

        const HandlerType = enum {
            all,
            specific,
        };

        const Handler = struct {
            handle_fn: HandleFn,
            method: http.Method,
            handler_type: HandlerType,
        };

        pub fn init(allocator: mem.Allocator, max_request_size: usize) Self {
            return .{
                .allocator = allocator,
                .max_request_size = max_request_size,
            };
        }

        pub fn run(self: *const Self, ctx: Context, handlers: anytype) !void {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();

            // Initialize Input and Output.
            var input: Input = undefined;
            var output: Output = undefined;
            try Input.fromStdIn(arena.allocator(), &input, self.max_request_size);
            try Output.init(arena.allocator(), &output);

            // Match the request method and invoke specific handler.
            // Lookup the type all handler.
            var not_found = true;
            comptime var type_all_handler: ?Handler = null;
            inline for (handlers) |handler| {
                switch (handler.handler_type) {
                    .specific => {
                        if (handler.method == input.request.method) {
                            not_found = false;
                            @call(.{}, handler.handle_fn, .{ ctx, input.request, &output.response, &input.cache }) catch |err| {
                                try renderErrorResponse(&output, err);
                            };
                        }
                    },
                    .all => type_all_handler = handler,
                }
            }

            // Invoke the type all handler or render default not found response.
            if (not_found) {
                if (type_all_handler) |handler| {
                    @call(.{}, handler.handle_fn, .{ ctx, input.request, &output.response, &input.cache }) catch |err| {
                        try renderErrorResponse(&output, err);
                    };
                } else {
                    try renderNotFoundResponse(&output);
                }
            }

            // Write output to stdout.
            try output.toStdOut(&input.cache);
        }

        pub fn all(comptime handle_fn: HandleFn) Handler {
            return .{
                .handle_fn = handle_fn,
                .method = http.Method.GET,
                .handler_type = .all,
            };
        }

        pub fn onMethod(comptime method: http.Method, comptime handle_fn: HandleFn) Handler {
            return .{
                .handle_fn = handle_fn,
                .method = method,
                .handler_type = .specific,
            };
        }

        pub fn get(comptime handle_fn: HandleFn) Handler {
            return onMethod(http.Method.GET, handle_fn);
        }

        pub fn post(comptime handle_fn: HandleFn) Handler {
            return onMethod(http.Method.POST, handle_fn);
        }

        pub fn put(comptime handle_fn: HandleFn) Handler {
            return onMethod(http.Method.PUT, handle_fn);
        }

        pub fn delete(comptime handle_fn: HandleFn) Handler {
            return onMethod(http.Method.DELETE, handle_fn);
        }

        pub fn head(comptime handle_fn: HandleFn) Handler {
            return onMethod(http.Method.HEAD, handle_fn);
        }

        pub fn patch(comptime handle_fn: HandleFn) Handler {
            return onMethod(http.Method.PATCH, handle_fn);
        }

        pub fn connect(comptime handle_fn: HandleFn) Handler {
            return onMethod(http.Method.CONNECT, handle_fn);
        }

        pub fn options(comptime handle_fn: HandleFn) Handler {
            return onMethod(http.Method.OPTIONS, handle_fn);
        }

        pub fn trace(comptime handle_fn: HandleFn) Handler {
            return onMethod(http.Method.TRACE, handle_fn);
        }

        fn renderErrorResponse(output: *Output, err: anyerror) !void {
            output.response.status = http.Status.internal_server_error;

            output.response.headers.store.clearAndFree();
            try output.response.headers.put("content-type", "text/plain");

            output.data.clearAndFree();
            var writer = output.data.writer();
            try writer.writeAll("500 - Internal Server Error. ");
            try writer.print("Error: {}", .{err});
        }

        fn renderNotFoundResponse(output: *Output) !void {
            output.response.status = http.Status.not_found;

            output.response.headers.store.clearAndFree();
            try output.response.headers.store.put("content-type", "text/html");

            output.data.clearAndFree();
            try output.response.body.writeAll("<html><h1>404 - Not Found.</h1></html>");
        }
    };
}

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
    allocator: mem.Allocator,
};

pub const Cache = struct {
    store: std.StringHashMap([]const u8),
    allocator: mem.Allocator,

    fn init(allocator: mem.Allocator) Cache {
        return .{
            .allocator = allocator,
            .store = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn get(self: *const Cache, name: []const u8) ?[]const u8 {
        return self.store.get(name);
    }

    /// name and value are copied.
    pub fn put(self: *Cache, name: []const u8, value: []const u8) !void {
        const n = try self.allocator.dupe(u8, name);
        const v = try self.allocator.dupe(u8, value);
        try self.store.put(n, v);
    }
};

pub const Headers = struct {
    store: std.StringHashMap([]const u8),
    allocator: mem.Allocator,

    fn init(allocator: mem.Allocator) Headers {
        return .{
            .allocator = allocator,
            .store = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn get(self: *const Headers, name: []const u8) ?[]const u8 {
        return self.store.get(name);
    }

    /// name and value are copied.
    pub fn put(self: *Headers, name: []const u8, value: []const u8) !void {
        const n = try self.allocator.dupe(u8, name);
        const v = try self.allocator.dupe(u8, value);
        try self.store.put(n, v);
    }
};

// Internal IO structures.
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
            try input.cache.store.put(kv_key, tree_kv.get(kv_key).?.String);
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
            try input.request.headers.store.put(header_key, tree_headers.get(header_key).?.String);
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
        output.response.allocator = allocator;
    }

    fn toStdOut(self: *Output, cache: *const Cache) !void {
        const stdout_writer = std.io.getStdOut().writer();
        var buffered_writer = std.io.bufferedWriter(stdout_writer);
        const stdout = buffered_writer.writer();

        // Write base64 and status.
        try stdout.print("{{\"status\":{d},\"base64\":{},", .{ @enumToInt(self.response.status), self.base64 });

        // Write headers.
        const headers_len = self.response.headers.store.count();
        var i: usize = 0;
        var headers_entry_itr = self.response.headers.store.iterator();
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
        const cache_len = cache.store.count();
        var cache_entry_itr = cache.store.iterator();
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
