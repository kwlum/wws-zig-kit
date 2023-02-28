# WWS kit in Zig
An experimental [WWS](https://github.com/vmware-labs/wasm-workers-server) kit written in zig.


## Features supported
- [x] Serialize/Deserialize Input and Output.
- [x] Access KV.
- [x] Access Env.


## Build and Run
Build the echo example, require zig-0.10.1 installed:

    zig build 

Run WWS inside workers directory, require WWS installed.

    wws www

Call the http endpoint with:

    curl -d "Hello World!" http://localhost:8080/echo

# Usage Examples

## Hello World
```zig
const std = @import("std");
const kit = @import("wws-zig-kit");

const App = kit.App(void);
const Route = App.Route;

fn handle(_: *void, request: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    try response.headers.put("content-type", "text/plain");
    try response.body.writeAll("Hello World!");
    response.status = std.http.Status.ok;
}

pub fn main() !void {
    const routes = [_]Route{Route.post(handle)};
    var no_context = {};
    try App.run(std.heap.c_allocator, 65535, &no_context, null, &routes);
}
```


## Cache (Key/Value Store)
ex: [counter](examples/counter/src/main.zig)
```zig
fn handle(_: *void, request: kit.Request, response: *kit.Response, cache: *kit.Cache) !void {
    const name = cache.get("name") orelse "kit";
    try response.headers.put("content-type", "text/plain");
    try response.body.print("Hello {s}!", .{name});
    response.status = std.http.Status.ok;
}
```


## Dynamic routes
Obtains the route parameters from [`kit.Request.params`](src/main.zig#L207).

ex: [dynamic-routes](examples/dynamic-routes/src/main.zig)
```zig
fn handle(_: *void, request: kit.Request, response: *kit.Response, _: *kit.Cache) !void {    
    try response.headers.put("content-type", "text/plain");
    if (request.params.get("id")) |id| {
        try response.body.print("Product Id: {s}", .{id});
    } else {
        try response.body.writeAll("Product not found.");
    }
    response.status = http.Status.ok;
}
```


## Environment variables

## Context