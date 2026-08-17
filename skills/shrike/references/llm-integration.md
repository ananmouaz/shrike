# LLM / AI-SDK integration failure modes

For code that calls a model provider (Anthropic, Gemini, OpenAI) directly or through
a framework (Vercel AI SDK, LangChain, provider SDKs). Apply as seeds — a pattern
match is a question, not a finding.

## Request construction

- **Hardcoded `mime_type` / media type on a multimodal part.** Declaring
  `image/png` for a source set that includes JPEG (or vice versa). Providers trust
  the declared type for remote URIs (`gs://`, signed URLs) rather than sniffing, so
  the request fails or the image is misdecoded. Backward-slice to what the upload
  path actually accepts.
- **Model id or capability flag changed without checking the message-shape
  contract** it implies — extended thinking, structured output, cache-control
  blocks. Enabling a mode changes what a valid turn looks like.
- **Token or context budget computed from characters** rather than a tokenizer,
  used to decide truncation.

## Response handling and round-tripping

- **Reasoning / thinking blocks persisted without their signature or provider
  metadata.** Storing the text alone and replaying it as a prior turn fails
  validation or silently drops the block on the next request. Check what the
  persistence layer writes against what the provider requires on replay.
- Tool-call arguments assumed to be valid JSON of the declared schema without a
  parse/validate step — a model can emit a malformed or extra-field payload.
- Streaming: partial content committed to durable state before the stream
  completes, with no reconciliation when it aborts mid-way.
- **Framework error contract assumed rather than read.** Rethrowing from a repair
  or middleware hook does not always discard the call — the SDK may wrap it and
  still admit an `invalid: true` result downstream. Read the SDK's documented
  behavior for the specific hook; do not infer it from the name.

## Cancellation, retry, cost

- **`abortSignal` not threaded into every nested model call.** A repair, fallback,
  or summarize call that omits the signal keeps running after the user cancels —
  billed tokens and, worse, a write that lands after the user backed out.
- **Fallback that re-issues work after the primary already exhausted its retries.**
  Batch call fails after its own rate-limit backoff, then the fallback fans out
  per-item requests concurrently and unpaced, re-tripping the same limit.
- **Recovery/repair handler with an unguarded `await`.** Any rejection (timeout,
  abort, schema, provider) inside the handler converts a recoverable error into a
  failed request for the whole turn.
- **Hardcoded per-token pricing constants.** Wrong rates produce wrong cost
  reporting and wrong budget enforcement; a single flat table also silently
  misprices historical usage when rates change. Check the constant against the
  provider's current published rate, and whether the table is date-aware.

## Grounding and evaluation

- Prompt built by string concatenation of user-controlled text with no delimiter or
  instruction-injection defense, where the output drives a privileged action.
- An LLM verdict written to durable state without recording the prompt/rule version
  it was produced under, so a later rule change cannot be reconciled.
- Judge/extractor given a different rule text than the one the reviewer sees.
