# Lucky Town — Networking Readiness (Phase 5)

The brief's hardest requirement: **online multiplayer must be addable later
without rewriting the core.** This document shows that the seam exists today,
how it works, and exactly what remains to turn the offline game into an online
one. Nothing here is active during normal offline play.

---

## 1. Why this is even possible

Three decisions made in Phase 1 do the heavy lifting:

1. **Everything is a plain-data fact on the `EventBus`.** Systems never call
   each other directly; they publish (`money_changed`, `slot_spun`,
   `auction_sold`, …) carrying only ints/strings/dictionaries. A stream of such
   facts is *already* a network protocol.
2. **All state funnels through two singletons** — `Economy` (money) and
   `GameState` (entities). To make a remote client authoritative you mutate
   those two, not a hundred scattered fields.
3. **Model / view split.** A `Citizen` is data; its decisions come from an
   `AiBrain`, its body from a `CitizenAgent`. Swapping the decision source is a
   field change, not a refactor.

---

## 2. What ships now

```
src/net/
├── net_message.gd        envelope { type, payload, origin, seq } + JSON codec
├── net_transport.gd      abstract transport (send / poll / message_received)
└── loopback_transport.gd in-process transport (tests, host-and-play)

src/autoload/net_sync.gd  the seam: mirrors EventBus facts ⇄ transport
```

`NetSync` is an autoload that is **disabled by default**. While disabled it
connects nothing, polls nothing, and allocates nothing per frame — the offline
game is byte-for-byte unchanged (this is asserted by keeping `set_process(false)`
and making `enable()` the only thing that wires signals).

When enabled it:
- **Outbound:** subscribes to a curated list of authoritative `EventBus` signals
  and forwards each as a `NetMessage` to the transport.
- **Inbound:** re-emits received messages on the local `EventBus`, guarded by an
  `_applying` flag so an applied event is never re-broadcast (no echo storms)
  and by `origin == peer_id` so a peer ignores its own messages.

```
        local play                              remote peer
   Economy ──money_changed──▶ EventBus ──▶ NetSync ──send──▶ Transport ═══╗
                                                                          ║
   EventBus ◀──re-emit── NetSync ◀──message_received── Transport ◀════════╝
      │
      └──▶ HUD / spectator view / telemetry
```

Today inbound events drive **observers** (HUD, spectator views, telemetry,
host-and-play loopback). That alone is useful and exercises the entire path.

### Remote-controlled citizens

`Citizen.control_mode ∈ { AI, LOCAL, REMOTE }`. `WorldDirector._tick_citizen`
skips `REMOTE` citizens — their decisions are expected to arrive over the wire
instead of from the local `AiBrain`. This is the concrete line that lets a
remote player **inhabit an existing AI citizen**: flip its `control_mode`, feed
its actions in via `NetSync`, and every other system treats it identically.

---

## 3. Turning the relay into authoritative sync

The remaining work is additive and localised:

1. **Apply-handlers.** For each mirrored fact, add a handler that mutates state
   instead of (or in addition to) re-emitting. Because money lives only in
   `Economy` and entities only in `GameState`, these handlers are small and
   centralised — e.g. an inbound `property_purchased` calls the same ownership
   transfer the local path uses.
2. **A real transport.** Implement `NetTransport` over Godot's high-level
   multiplayer (ENet) or WebSocket. `NetSync` needs no change.
3. **Authority model.** Run the `domain` + `core` layers server-side (they have
   no scene dependency) as the source of truth; clients send intents and render
   applied facts.
4. **Determinism.** Seed `RngService` from the server so shared slots and
   jackpots are provably fair across peers (the named-stream design already
   makes outcomes reproducible from a seed).
5. **Persistence.** Swap `SaveBackend` for a network/cloud backend; `SaveManager`
   is unchanged.

None of steps 1–5 require a Phase 1–4 system to change its public shape — which
is the whole claim, now demonstrable.

---

## 4. Host-and-play loopback (try it)

`LoopbackTransport` can echo a peer's own messages (`set_loopback_self(true)`)
or accept injected ones (`inject()`), so a single process can run the full
NetSync path. Sketch:

```gdscript
var transport := LoopbackTransport.new()
NetSync.enable(transport, "host")
# ... a "remote" decision arrives:
transport.inject(NetMessage.new("citizen_action_finished", {"args": ["cit_42", "gamble"]}, "guest", 1))
# NetSync re-emits it locally; observers react exactly as for a local event.
```

Unit tests cover the message round-trip and the loopback delivery
(`tests/run_tests.gd`).

---

## 5. Non-goals (deliberately)

- No matchmaking, lobbies, accounts or anti-cheat yet — those sit above this
  seam and don't affect it.
- No partial-state interest management (sending only nearby entities) — a
  performance concern for later, not an architectural blocker.
