# ParkLink Copilot: OpenCode runtime and consent

## How to open it

Double-tap the authenticated application's content, or use the visible sparkle button in the app bar. The shortcut observes pointer events without claiming map gestures. Multi-touch, drags and taps while the keyboard is open are ignored. With accessible navigation enabled, double-tap is reserved for the screen reader; use the labelled button instead.

Choose an interval in Lima time before asking to reserve. Examples: “Busca el estacionamiento más cercano”, “Busca el más barato”, “Reserva el lugar más barato”, “Muéstrame mis reservas”. Results are real Discovery queries. The backend ranks the whole geographic query by price or distance, not just an arbitrary client-side sample. “Nearest” means nearest to the supplied map centre, not a claim of device GPS accuracy.

## What runs in the background

`opencode-runtime` is a real OpenCode 1.19.5 server in an independent container. The conversational service uses the official `@opencode-ai/sdk/v2`, creates an ephemeral session, supplies `domain/personality.ts`, requests a strict intent schema and deletes the session after the turn. The persona is warm, concise, professional and explicit about uncertainty; it is not a coding assistant inside this product.

The runtime has no host filesystem mounts, personal OpenCode settings, personal authentication files, Docker socket, PostgreSQL credentials or application JWTs. It runs non-root with dropped capabilities, a read-only filesystem and bounded writable tmpfs directories. Its HTTP API is private and password-protected; it is not exposed as a public API. The application does not modify your personal OpenCode installation or this coding session's configuration.

Each session denies all built-in tools, with only the internal structured-output tool permitted. Shell, file access, browsing, delegation and editing are explicitly disabled. Permissions alone are not treated as a sandbox; the independent container provides the execution boundary. OpenCode interprets intent; authenticated deterministic handlers, not the model, invoke ParkLink APIs and commands.

## Free-only inference

Before any model prompt, the adapter checks the isolated runtime's `opencode` model metadata. Input, output and cache prices must all be advertised as zero. It tries at most three verified free models, each in its own isolated session with an eight-second prompt timeout and no structured-output retries. Only the latest three turns are supplied as history. No paid provider or personal credentials are used. If all candidates fail, inference is refused rather than silently choosing a paid provider.

The supplied runtime previously timed out during live inference. **Generative output is not claimed as verified.** OpenCode is required for chat: if inference is unavailable, the request returns an error and no guided interpretation or action is performed.

The Compose service enables inference. `COPILOT_ENABLED=false` disables the feature without affecting visual booking. `node scripts/copilot-smoke.mjs` tests the real default model path; a passing mocked SDK test does not prove live inference works.

## Actions and financial authority

| Action | Before confirmation | After explicit confirmation |
|---|---|---|
| Search/list | Authorized read only | No mutation needed |
| Reserve via chat | Server selects candidate and quotes exact interval/price/revision | One command creates the hold and initiates sandbox payment atomically; confirmation follows the payment event |
| Explicit hold | Server quotes exact interval/price/revision | Durable hold command; no payment yet |
| Pay | Server reads the authenticated driver's current reservation and amount | Authorization command; Reservation must later confirm |
| Cancel | Server quotes the applicable refund and policy | Cancellation command and separate refund saga |

Tokens are actor-bound, one-use/idempotent and expire after five minutes. They bind action, resource, price, offer/reservation version and cancellation refund as applicable. Price changes or stale versions fail closed. Model output cannot set user identity, charge amount, payment result, refund amount, endpoints or SQL. The chat's “yes” text does not consume a token: a dedicated confirmation button is required.

Messages have request IDs and payload hashes; replay returns the persisted response instead of generating another proposal. Conversation ownership is checked on every request. Twelve messages per actor per minute are allowed, input/history are bounded, and the conversation store expires after at most 24 hours of inactivity. No JWTs or provider secrets are stored with conversation history. A cancelled reservation is not described as an already credited refund.

## Known limits

- Chat requires the free provider to be available.
- Paid providers are deliberately not enabled by this implementation.
- Voice recognition, extensions and owner publication tools are not part of the current allowlist.
- The user must provide exact reservation times; the assistant must not invent them from vague phrases.
- A deployment should add network egress restrictions, provider retention review and a secrets manager before production approval.
