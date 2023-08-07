# Code Server

This library can be used for remote code execution over CAN-bus. The result of the code is sent back to the sender and a timeout can also be specified. This library requires firmware 6.05 or later.

## Functions

### start-code-server

```clj
(start-code-server)
```

Start code server on local device. Note that a CAN-device can be a client and a server at the same time.

### rcode-run

```clj
(rcode-run id tout code)
```

Run code on CAN-device with id. A timeout in seconds can be specified, which makes this function return the symbol timeout if the CAN-device does not respond. Note that start-code-server has to be used on the CAN-device for it to respond. Also note that the symbol eerror is returned if the code results in an error on the server.

### rcode-run-noret

```clj
(rcode-run-noret id code)
```

Same as above, but does not wait for a response (fire and forget).

## Example

### Server

```clj
(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

(start-code-server)
```

### Client

```clj
(import "pkg@://vesc_packages/lib_code_server/code_server.vescpkg" 'code-server)
(read-eval-program code-server)

; Assume server has CAN-ID 26
(print (list "Input Voltage" (rcode-run 26 0.5 '(get-vin))))
```
