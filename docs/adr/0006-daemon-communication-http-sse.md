# Daemon exposes JSON-RPC 2.0 over HTTP; diagnosis streams over SSE

The Analysis Daemon exposes two interfaces on localhost:

1. **JSON-RPC 2.0 over HTTP** (port 9101) — control plane: start/stop session, configure provider, query KB, fetch session history.
2. **SSE endpoint** (`GET /diagnoses/stream`) — data plane: streams `Diagnosis` objects as newline-delimited JSON as they are produced, enabling progressive rendering in the DevTools extension.

The DevTools extension (Flutter web iframe) communicates with the daemon over these two channels. CORS middleware on the daemon is the only requirement — `127.0.0.1` is a W3C Secure Context, so there is no mixed-content blocking.

## Why JSON-RPC 2.0 and not REST

JSON-RPC 2.0 gives a typed method dispatch protocol with built-in error codes, request IDs for correlation, and a well-known spec that community contributors can implement clients for in any language. REST would require designing a URL scheme for what are fundamentally RPC operations (startSession, stopSession, configureLlm).

## Why SSE and not WebSocket

SSE is unidirectional (server → client) which is all the data plane needs — the daemon pushes diagnoses, the extension renders them. SSE is simpler to implement, does not require a WebSocket upgrade handshake, and works correctly through the DevTools iframe context. WebSocket would add bidirectionality that is not needed and creates a more complex reconnect story.

## Port

Port 9101 is chosen to avoid collision with common dev ports (3000, 4000, 5000, 8080, 8888). It is configurable via `jankdoc.yaml`. If the port is taken, the daemon increments until it finds a free port and reports the actual port to the extension on startup.
