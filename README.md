# GUARDA: Gateway for Uniform Access to Remote Data and Analytics

**GUARDA** is a high-performance federated data integration proxy built on **Elixir** and the Erlang VM (BEAM). It is engineered to perform as a resilient middleware gateway, providing a unified standard REST access layer across diverse, distributed backend data systems (e.g., PostgreSQL warehouses, HTTP institutional datasets) without relying on massive centralized data lakes.


## Core Features

- **Actor Model Concurrency**: Powered natively by Elixir `GenServer` actors, every single federated query runs in a strictly isolated functional memory space. A long-running analytical query against a legacy remote API will never bottleneck the primary gateway router.
- **Fail-Safe Supervision**: Managed by a fault-tolerant `DynamicSupervisor`, any backend query timeout or corrupted health system socket simply crashes that specific, isolated query actor. The proxy instantly auto-heals without bringing down concurrent traffic.
- **Micro-Second Auth Caching**: Zero-latency overhead for API key validation. Leveraging native Erlang Term Storage (`ETS`) tables configured with `:read_concurrency`, cryptographic proxy checks occur entirely in-memory and execute in micro-seconds.
- **Real-Time LiveView Dashboard**: Built-in Phoenix LiveView administrative Command Center operating over WebSockets. Monitors the exact state of remote worker pools and active keys without utilizing complex SPA Javascript frameworks.

## Quick Start

### 1. Prerequisites
- **Elixir ~> 1.15** (built on Erlang/OTP 25+)
- Ensure standard build tools are available.

### 2. Deployment

```bash
# Fetch and fully compile the Hex dependencies
mix deps.get

# (Optional) Verify the cryptographic formatting and test suite
mix precommit

# Boot the Live Gateway Router and Web Console
mix phx.server
```

Once running, navigate immediately to the Live Command Center at [`http://localhost:4000`](http://localhost:4000).

## Provider Architecture

New federated databases or APIs can be hooked into the proxy interface dynamically using the `Guarda.Provider` behaviour contract:
- `lib/guarda/provider/http.ex`: Native remote REST binding proxying through `Req`.
- `lib/guarda/provider/postgres.ex`: Native deep socket database integration proxying through `Postgrex`.

## Security Identity

The gateway proxy routes are entirely protected by a consolidated native pipeline (`lib/guarda_web/plugs/auth_plug.ex`):
1. Uses API Key (`x-api-key`) validation mapped directly against the underlying ETS security tables.
2. Uses standard OAuth Bearer JSON Web Tokens (`JWT`). Signatures and expirations are strictly validated natively using `Phoenix.Token` (backed safely by `Plug.Crypto` cryptography) to ensure only verified Institutional Researchers or registered AI Agents have access.

---

*This framework has been built to eliminate the massive middleware blocking and concurrency limitations previously flagged within monolithic federated structures.*
