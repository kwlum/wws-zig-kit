# WWS kit in Zig
An experimental [WWS](https://github.com/vmware-labs/wasm-workers-server) kit written in zig.


### Features supported
- [x] Serialize/Deserialize Input and Output.
- [x] Access KV.
- [x] Access Env.


### Build and Run
Build the echo example, require zig-0.10.1 installed:

    zig build 

Run WWS inside workers directory, require WWS installed.

    wws www

Call the http endpoint with:

    curl -d "Hello World!" http://localhost:8080/echo
