---
status: accepted
---

# Share IPC wire types through DenIPCProtocol

The bundled CLI and app must agree on request and response shapes while remaining separate targets. Put their Foundation-only wire DTOs in `DenIPCProtocol`; keeping transport and command policy in the consumers lets each retain its own runtime dependencies.
