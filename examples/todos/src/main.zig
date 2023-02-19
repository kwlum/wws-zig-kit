const std = @import("std");
const fmt = std.fmt;
const http = std.http;
const io = std.io;
const json = std.json;
const mem = std.mem;

const kit = @import("wws-zig-kit");

const Todo = struct {
    text: []const u8,
    id: u32,
    completed: bool,

    fn writeJson(self: Todo, writer: io.Writer) !void {
        try json.stringify(self, .{}, writer);
    }
};

const NewTodoBody = struct {
    text: []const u8,

    fn fromJsonString(allocator: mem.Allocator, json_string: []const u8) !NewTodoBody {
        var todos_token_stream = json.TokenStream.init(json_string);
        return try json.parse(NewTodoBody, &todos_token_stream, .{ .allocator = allocator });
    }
};

const UpdateTodoBody = struct {
    id: u32,
    text: []const u8,
    completed: bool,

    fn fromJsonString(allocator: mem.Allocator, json_string: []const u8) !UpdateTodoBody {
        var todos_token_stream = json.TokenStream.init(json_string);
        return try json.parse(UpdateTodoBody, &todos_token_stream, .{ .allocator = allocator });
    }
};

const DeleteTodoBody = struct {
    id: u32,

    fn fromJsonString(allocator: mem.Allocator, json_string: []const u8) !DeleteTodoBody {
        var todos_token_stream = json.TokenStream.init(json_string);
        return try json.parse(DeleteTodoBody, &todos_token_stream, .{ .allocator = allocator });
    }
};

fn getTodosFromKV(allocator: mem.Allocator, input: kit.Input) ![]Todo {
    const todos_json_string = input.kv.get("todos") orelse "[]";
    var todos_token_stream = json.TokenStream.init(todos_json_string);
    return try json.parse([]Todo, &todos_token_stream, .{ .allocator = allocator });
}

fn updateTodos(allocator: mem.Allocator, output: *kit.Output, todos: []Todo) !void {
    var buffer = std.ArrayList(u8).init(allocator);
    try json.stringify(todos, .{}, buffer.writer());
    try output.kv.put("todos", buffer.toOwnedSlice());
}

fn genNextId(allocator: mem.Allocator, input: kit.Input, output: *kit.Output) !u32 {
    const next_id: u32 =
        if (input.kv.get("next_id")) |a|
        fmt.parseInt(u32, a, 10) catch 1
    else
        1;

    const next_id_string = try fmt.allocPrint(allocator, "{d}", .{next_id + 1});
    try output.kv.put("next_id", next_id_string);

    return next_id;
}

fn handle(allocator: mem.Allocator, input: kit.Input, output: *kit.Output) !void {
    switch (input.method) {
        .GET => {
            // Get a list of todos.
            const todos = try getTodosFromKV(allocator, input);
            var data_buffer = std.ArrayList(u8).init(allocator);
            try json.stringify(todos, .{}, data_buffer.writer());
            output.data = data_buffer.toOwnedSlice();
            try output.toStdOut();
        },
        .POST => {
            // Create new todo.
            const kv_todos = try getTodosFromKV(allocator, input);
            const new_todo = try NewTodoBody.fromJsonString(allocator, input.body);
            const new_id = try genNextId(allocator, input, output);

            // Append new todo into Output.KV.
            var todos = try allocator.alloc(Todo, kv_todos.len + 1);
            mem.copy(Todo, todos, kv_todos);
            todos[todos.len - 1] = Todo{
                .id = new_id,
                .text = new_todo.text,
                .completed = false,
            };
            try updateTodos(allocator, output, todos);

            // Write new todo to Output.
            var data_buffer = std.ArrayList(u8).init(allocator);
            try json.stringify(todos[todos.len - 1], .{}, data_buffer.writer());
            output.data = data_buffer.toOwnedSlice();
            output.status = http.Status.created;
            try output.toStdOut();
        },
        .PUT => {
            // Update a todo.
            const update_todo = try UpdateTodoBody.fromJsonString(allocator, input.body);
            var kv_todos = try getTodosFromKV(allocator, input);
            for (kv_todos) |*a| {
                if (a.id == update_todo.id) {
                    a.text = update_todo.text;
                    a.completed = update_todo.completed;
                    break;
                }
            }

            try updateTodos(allocator, output, kv_todos);
            try output.toStdOut();
        },
        .DELETE => {
            // Delete a todo.
            const delete_todo = try DeleteTodoBody.fromJsonString(allocator, input.body);
            const kv_todos = try getTodosFromKV(allocator, input);            

            var todos = try allocator.alloc(Todo, kv_todos.len);
            var i: u32 = 0;
            for (kv_todos) |a| {
                if (a.id != delete_todo.id) {
                    todos[i] = a;
                    i += 1;
                }
            }
            
            try updateTodos(allocator, output, todos[0..i]);
            try output.toStdOut();
        },
        else => {
            output.status = http.Status.bad_request;
            output.data = "Bad Request";
            try output.toStdOut();
        },
    }    
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var allocator = arena.allocator();

    // Initialize Input and Output.
    var input = try kit.Input.fromStdIn(allocator, 65536);
    var output = try kit.Output.init(allocator, input);

    handle(allocator, input, &output) catch |err| {
        output.status = http.Status.internal_server_error;
        output.data = fmt.allocPrint(allocator, "<html><h1>Internal Server Error!</h1><span>Error: {}</span></html>", .{err}) catch "Internal Server Error!";
        try output.toStdOut();
    };
}
