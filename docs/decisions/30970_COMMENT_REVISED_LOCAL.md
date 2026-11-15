Thanks for the work on `--slot-attach`. Following the Nov 12 thread here about a
possible libllama capability query such as `llama_memory_can_share_cells()`:

Would a memory-level query be the right generic way to replace the
architecture-name exclusion? I am asking about the capability boundary only —
not proposing that this PR grow a client-facing fork API.

One reason a single predicate may not be enough: the condition the server is
really testing is not one capability. Plain KV shares cells; hybrid and
recurrent memory attach at a checkpoint; sliding-window memory can neither share
a cell nor attach at a checkpoint, while still supporting other copy/shift
operations. So a boolean `can_share_cells` would leave the checkpoint path
unexpressed, and the name list would keep drifting each time a memory type lands
(DeepSeek V4 was the recent example in this thread).

There is existing precedent for a per-memory predicate of this shape:
`llama_memory_can_shift()` in `include/llama.h`, dispatched through the memory
object (`return mem->get_can_shift();` in `src/llama-context.cpp`), with each
memory module answering for itself — for instance `llama_kv_cache_iswa` combines
the base and sliding-window answers in `src/llama-kv-cache-iswa.cpp`. Following
that pattern, something like `can_share_cells` plus `can_attach_at_checkpoint`
would describe the operation rather than a broad "KV attach" capability.

The question is narrow: is a capability query at that level the preferred
direction for the follow-up, or should this stay a server-side list until the
memory modules settle and move into libllama only then?
