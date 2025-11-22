# Architecture Improvements (Tested Version)

## Goal
Guarantee per-object sequential processing while allowing cross-object parallelism. Fix the race that let two batches for the same object run in parallel in Scribe, and capture the lessons from the flaky test investigation.

## What Failed and Why (Chronology)
- **Original issue**: Same-object batches occasionally ran in parallel. We saw two “Processing … for object X” logs with different start times, and Pong from a later batch beat Ping from an earlier batch.
- **Initial gate (active/buffer)**: Tracked `active` and `buffer` separately. A second `handle_events/3` call could arrive before the first marked the object active, so two batches emitted.
- **Queue-only gate v1**: Moved to a single map of queues but still allowed a second batch to emit when the object appeared idle in a separate `handle_events/3`.
- **Busy flag + queue (final)**: Single map `%{object => {:busy, queue}}`; only emit when transitioning idle→busy; otherwise enqueue. Release exactly one batch per ack. This blocked concurrent emits for the same object.
- **Test flake root cause**: The sequential test sent two events to the same object but asserted on only two messages, so Pong from the second event could arrive before Ping from the first. Distinguishing events (`:ping`, `:pong`) for sequential/concurrent tests fixed the misattribution; `:check` remains only for the registration-order test.

## Final Envoy (ProducerConsumer) – Per-Object Gate
- **State**: `%{object_id => {:busy, queue}}`, where `queue` is a `:queue` of batches (each batch is a list of events for that object).
- **handle_events/3**
  - Group incoming events by `event.object`.
  - For each `{object, batch}`:
    - If no entry exists (idle):
      - Enqueue: `queue = :queue.in(batch, :queue.new())`.
      - Pop head: `{{:value, head}, queue_tail} = :queue.out(queue)`.
      - Emit `[{object, head}]`.
      - Store `state[object] = {:busy, queue_tail}` (object marked busy; tail queued).
    - If entry is `{:busy, queue}` (busy):
      - Enqueue: `queue = :queue.in(batch, queue)`.
      - Do **not** emit; keep `{:busy, queue}`.
  - Return `{:noreply, Enum.reverse(to_emit), state}`.
- **handle_info({:ack, object})**
  - `Map.pop(state, object)`:
    - `nil` → no-op.
    - `{:busy, queue}`:
      - `:queue.out(queue)`:
        - `{:empty, _}` → remove entry (object idle), emit nothing.
        - `{{:value, next_batch}, queue_tail}` → emit `[{object, next_batch}]`, store `{:busy, queue_tail}`.
- **Invariant**: Only one batch per object is ever emitted at a time. Next batch flows only on ack. Busy remains until queue is empty and ack is received.

## Scribe (ConsumerSupervisor) – Worker
- Worker processes `{object, events}` and **always** sends `{:ack, object}` back to Envoy in an `after` block, even on crash, to avoid deadlocks.
- Scribe subscription can remain `min_demand: 0, max_demand: N`; gating is enforced by Envoy.

## Herald Wiring
- Herald starts an Envoy per partition (subscribed to Herald).
- Scribe subscribes to Envoy (not Herald).
- Partition hashing unchanged: objects route deterministically to a partition; Envoy enforces per-object serialization within the partition.

## Testing Lessons
- Sequential test must not mix multiple events unless it consumes all corresponding messages. Use distinct events (`:ping`, `:pong`) for sequential/concurrent tests; keep `:check` only for the registration-order test.
- Flakiness can stem from test sampling order, not just concurrency bugs. Ensure asserts consume the full set of expected messages per send.

## Key Takeaways
- Treat an object as busy from the moment you emit its first batch until an ack drains the queue; even an empty queue with a busy flag prevents a second emit.
+- Checking only “active” without guarding queued arrivals allows a second `handle_events/3` to emit another batch; busy+queue closes this race.
- Workers must always ack, even on crash, or objects may stay locked.
- Tests that send multiple events must disambiguate messages or consume all of them to avoid false failures.*** End Patch
