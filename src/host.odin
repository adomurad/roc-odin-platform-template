package host

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"

// Host environment. Embeds RocEnv so the Roc runtime sees a pointer
// to a standard RocEnv while hosted functions can recover the full
// HostEnv via pointer arithmetic.
HostEnv :: struct {
    roc_env: RocEnv,
    tracking_allocator: mem.Tracking_Allocator,
    stdin_buffer: [4096]u8,
    stdin_pos: int,
    stdin_len: int,
}

// Private RocHost used by host helpers and exported runtime symbols.
g_roc_host: ^RocHost

// -----------------------------------------------------------------------------
// Entry point
// -----------------------------------------------------------------------------

when ODIN_OS == .Windows {
    @(export)
    __main :: proc "c" () {
        // Windows MinGW/MSVCRT compatibility stub.
    }
}

main :: proc() {
    env: HostEnv
    mem.tracking_allocator_init(&env.tracking_allocator, context.allocator)
    env.roc_env.allocator = mem.tracking_allocator(&env.tracking_allocator)
    env.roc_env.roc_io = roc_io_default()
    env.stdin_pos = 0
    env.stdin_len = 0

    roc_host := make_roc_host(&env.roc_env)
    g_roc_host = &roc_host

    args_list := build_args_list_from_os_args(&roc_host)

    exit_code := roc_main(args_list)

    // Check for memory leaks before returning.
    bad := tracking_allocator_check(&env.tracking_allocator)
    if bad {
        fmt.fprintln(os.stderr, "Memory leak detected!")
        os.exit(1)
    }

    os.exit(int(exit_code))
}

// -----------------------------------------------------------------------------
// Try helpers
// -----------------------------------------------------------------------------

stderr_line_ok :: proc() -> TryType0 {
    return TryType0{
        payload = TryType0Payload{ ok = struct {}{} },
        tag = .Ok,
    }
}

stderr_line_err :: proc(err: string, roc_host: ^RocHost) -> TryType0 {
    return TryType0{
        payload = TryType0Payload{ err = roc_str_from_slice(err, roc_host) },
        tag = .Err,
    }
}

stdin_line_ok :: proc(line: RocStr) -> TryType4 {
    return TryType4{
        payload = TryType4Payload{ ok = line },
        tag = .Ok,
    }
}

stdin_line_err :: proc(err: string, roc_host: ^RocHost) -> TryType4 {
    return TryType4{
        payload = TryType4Payload{ err = roc_str_from_slice(err, roc_host) },
        tag = .Err,
    }
}

stdout_line_ok :: proc() -> TryType6 {
    return TryType6{
        payload = TryType6Payload{ ok = struct {}{} },
        tag = .Ok,
    }
}

stdout_line_err :: proc(err: string, roc_host: ^RocHost) -> TryType6 {
    return TryType6{
        payload = TryType6Payload{ err = roc_str_from_slice(err, roc_host) },
        tag = .Err,
    }
}

// -----------------------------------------------------------------------------
// Hosted functions
// -----------------------------------------------------------------------------

@(export)
roc_stderr_line :: proc "c" (str: RocStr) -> TryType0 {
    context = runtime.default_context()
    roc_host := g_roc_host
    local_str := str
    defer roc_str_decref(local_str, roc_host)

    message := roc_str_as_slice(&local_str)
    _, err := os.write(os.stderr, transmute([]u8)message)
    if err != os.ERROR_NONE {
        return stderr_line_err("stderr write failed", roc_host)
    }
    _, err2 := os.write(os.stderr, []u8{ '\n' })
    if err2 != os.ERROR_NONE {
        return stderr_line_err("stderr write failed", roc_host)
    }
    return stderr_line_ok()
}

@(export)
roc_stdin_line :: proc "c" () -> TryType4 {
    context = runtime.default_context()
    roc_host := g_roc_host
    env := host_env_from_roc_host(roc_host)
    line, ok := buffered_read_line(env, roc_host)
    if !ok {
        return stdin_line_err("stdin read failed", roc_host)
    }
    return stdin_line_ok(line)
}

@(export)
roc_stdout_line :: proc "c" (str: RocStr) -> TryType6 {
    context = runtime.default_context()
    roc_host := g_roc_host
    local_str := str
    defer roc_str_decref(local_str, roc_host)

    message := roc_str_as_slice(&local_str)
    _, err := os.write(os.stdout, transmute([]u8)message)
    if err != os.ERROR_NONE {
        return stdout_line_err("stdout write failed", roc_host)
    }
    _, err2 := os.write(os.stdout, []u8{ '\n' })
    if err2 != os.ERROR_NONE {
        return stdout_line_err("stdout write failed", roc_host)
    }
    return stdout_line_ok()
}

@(export)
roc_alloc :: proc "c" (length: uint, alignment: uint) -> rawptr {
    context = runtime.default_context()
    return default_roc_alloc(g_roc_host, length, alignment)
}

@(export)
roc_dealloc :: proc "c" (ptr: rawptr, alignment: uint) {
    context = runtime.default_context()
    default_roc_dealloc(g_roc_host, ptr, alignment)
}

@(export)
roc_realloc :: proc "c" (ptr: rawptr, new_length: uint, alignment: uint) -> rawptr {
    context = runtime.default_context()
    return default_roc_realloc(g_roc_host, ptr, new_length, alignment)
}

@(export)
roc_dbg :: proc "c" (bytes: [^]u8, len: uint) {
    context = runtime.default_context()
    default_roc_dbg(g_roc_host, bytes, len)
}

@(export)
roc_expect_failed :: proc "c" (bytes: [^]u8, len: uint) {
    context = runtime.default_context()
    default_roc_expect_failed(g_roc_host, bytes, len)
}

@(export)
roc_crashed :: proc "c" (bytes: [^]u8, len: uint) {
    context = runtime.default_context()
    default_roc_crashed(g_roc_host, bytes, len)
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

host_env_from_roc_host :: proc(roc_host: ^RocHost) -> ^HostEnv {
    roc_env := (^RocEnv)(roc_host.env)
    return (^HostEnv)(roc_env)
}

build_args_list_from_os_args :: proc(roc_host: ^RocHost) -> RocList(RocStr) {
    if len(os.args) == 0 {
        return roc_list_empty(RocStr)
    }

    list := roc_list_allocate(RocStr, true, uint(len(os.args)), roc_host)
    for i in 0..<len(os.args) {
        list.elements_ptr[i] = roc_str_from_slice(os.args[i], roc_host)
    }
    return list
}

buffered_read_line :: proc(env: ^HostEnv, roc_host: ^RocHost) -> (RocStr, bool) {
    buffer := &env.stdin_buffer
    pos := &env.stdin_pos
    buf_len := &env.stdin_len

    for {
        // Search for newline in the current buffer.
        for i in pos^..<buf_len^ {
            if buffer[i] == '\n' {
                start := pos^
                end := i
                if end > start && buffer[end - 1] == '\r' {
                    end -= 1
                }
                line := string(buffer[start:end])
                pos^ = i + 1
                return roc_str_from_slice(line, roc_host), true
            }
        }

        // No newline found. Move any remaining data to the front.
        if pos^ < buf_len^ {
            remaining := buf_len^ - pos^
            mem.copy(&buffer[0], &buffer[pos^], remaining)
            buf_len^ = remaining
            pos^ = 0
        } else {
            buf_len^ = 0
            pos^ = 0
        }

        if buf_len^ == len(buffer) {
            // Buffer is full and no newline found: discard the overlong line.
            discard: [4096]u8
            found := false
            for !found {
                n, err := os.read(os.stdin, discard[:])
                if err != os.ERROR_NONE {
                    return roc_str_empty(), false
                }
                if n == 0 {
                    return roc_str_empty(), true
                }
                for j in 0..<n {
                    if discard[j] == '\n' {
                        found = true
                        break
                    }
                }
            }
            buf_len^ = 0
            pos^ = 0
            continue
        }

        // Read more data.
        n, err := os.read(os.stdin, buffer[buf_len^:])
        if err != os.ERROR_NONE {
            return roc_str_empty(), false
        }
        if n == 0 {
            // EOF.
            if buf_len^ > pos^ {
                line := string(buffer[pos^:buf_len^])
                pos^ = buf_len^
                return roc_str_from_slice(line, roc_host), true
            }
            return roc_str_empty(), true
        }
        buf_len^ += n
    }
}

tracking_allocator_check :: proc(t: ^mem.Tracking_Allocator) -> bool {
    return len(t.allocation_map) != 0 || len(t.bad_free_array) != 0
}
