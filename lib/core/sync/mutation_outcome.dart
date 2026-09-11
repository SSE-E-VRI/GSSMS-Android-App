/// Where a write actually ended up.
///
/// Offline-capable repository writes fall back to the durable outbox on a
/// network failure. Callers must not report such a write as "saved" or
/// "completed" — it has only reached this device (SSOT §41: the client must
/// not mark a server-side operation complete until the server acknowledges it).
enum MutationOutcome {
  /// The server acknowledged the write.
  synced,

  /// Saved in the outbox on this device; replays when a connection returns.
  queued,
}
