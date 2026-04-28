# GUARDA: Gateway for Uniform Access to Remote Data and Analytics

**GUARDA** is a high-performance federated data integration proxy built on **Elixir** and the Erlang VM (BEAM). It is engineered to perform as a resilient middleware gateway, providing a unified standard REST access layer across diverse, distributed backend data systems (e.g., PostgreSQL warehouses, HTTP institutional datasets) without relying on massive centralized data lakes.


## Core Features

- **Actor Model Concurrency**: Powered natively by Elixir `GenServer` actors, every single federated query runs in a strictly isolated functional memory space. A long-running analytical query against a legacy remote API will never bottleneck the primary gateway router.
- **Fail-Safe Supervision**: Managed by a fault-tolerant `DynamicSupervisor`, any backend query timeout or corrupted health system socket simply crashes that specific, isolated query actor. The proxy instantly auto-heals without bringing down concurrent traffic.
- **Micro-Second Auth Caching**: Zero-latency overhead for API key validation. Leveraging native Erlang Term Storage (`ETS`) tables configured with `:read_concurrency`, cryptographic proxy checks occur entirely in-memory and execute in micro-seconds.
- **Real-Time LiveView Dashboard**: Built-in Phoenix LiveView administrative Command Center operating over WebSockets. Monitors the exact state of remote worker pools and active keys without utilizing complex SPA Javascript frameworks.

## Quick Start

### 1. Prerequisites & Setup

- **Required**: Elixir ~> 1.16 (built on Erlang/OTP 26+)
- Ensure standard build tools are available.

The easiest way to install Elixir 1.16, update build tools, and fetch dependencies is to use the provided `setup.sh` script:

```bash
chmod +x setup.sh
./setup.sh
```

This script handles:
- Installing Erlang/OTP 26 and Elixir 1.16.3.
- Updating `hex` and `rebar` archives.
- Cleaning and fetching all project dependencies.

For developers using [asdf](https://asdf-vm.com/), you can manually run:
```bash
asdf install elixir 1.16.3-otp-26
mix local.hex --force && mix local.rebar --force
mix deps.get
```

### 2. Deployment

After running the setup script, you can boot the gateway:

```bash
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
- `lib/guarda/provider/mysql.ex`: Native MySQL/MariaDB binding proxying through `MyXQL`.
- `lib/guarda/provider/mongo.ex`: Native document store binding proxying through `mongodb_driver`.

## Security Identity

The gateway proxy routes are entirely protected by a consolidated native pipeline (`lib/guarda_web/plugs/auth_plug.ex`):
1. Uses API Key (`x-api-key`) validation mapped directly against the underlying ETS security tables.
2. Uses standard OAuth Bearer JSON Web Tokens (`JWT`). Signatures and expirations are strictly validated natively using `Phoenix.Token` (backed safely by `Plug.Crypto` cryptography) to ensure only verified Institutional Researchers or registered AI Agents have access.

## Integration Testing

GUARDA ships with a full end-to-end integration suite that fires real queries at live Docker containers for each supported provider.

### 1. Docker Setup (one-time)

Ensure Docker is installed and your user has socket access:

```bash
sudo usermod -aG docker $USER
newgrp docker   # applies group without requiring logout
```

> **Note:** `newgrp docker` activates the change in your current shell session only.
> On next login the group membership is applied automatically.

### 2. Start the Test Containers

Use the `docker-compose` v1 standalone binary (not `docker compose`):

```bash
docker-compose up -d
```

This boots three isolated containers:
| Container | Image | Port | Provider |
|---|---|---|---|
| `guarda_postgres` | `postgres:15` | `5432` | `Guarda.Provider.Postgres` |
| `guarda_mysql` | `mysql:8.0` | `3306` | `Guarda.Provider.Mysql` |
| `guarda_mongo` | `mongo:4.4` | `27018` | `Guarda.Provider.Mongo` |

Wait ~20 seconds for MySQL and Postgres to finish their first-run initialization.

### 3. Run the Integration Suite

```bash
mix test test/guarda/integration/federation_test.exs
```

Each test spawns a live `GenServer` provider actor via `Guarda.ProviderSupervisor`, sends a real query over the wire, and validates the returned data.

### 4. Tear Down

```bash
docker-compose down
```

---

*This framework has been built to eliminate the massive middleware blocking and concurrency limitations previously flagged within monolithic federated structures.*
