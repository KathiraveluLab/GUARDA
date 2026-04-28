# GUARDA Tutorial: Federated Data Integration

Welcome to **GUARDA**, the high-performance federated data integration proxy. This tutorial walks you through the core use cases and how to leverage the system for distributed analytics.

## 1. Core Architecture

GUARDA acts as a unified middleware layer. Instead of moving all your data into a central data lake (ETL), you keep your data in its source systems (PostgreSQL, MySQL, MongoDB, REST APIs) and use GUARDA to query them in real-time.

### Key Concepts
- **Providers**: Isolated Erlang processes (Actors) that speak the native protocol of your backend databases.
- **ETS Caching**: In-memory security layer that validates API keys in micro-seconds.
- **Supervision**: A fault-tolerant hierarchy that ensures one slow query doesn't crash the entire gateway.

---

## 2. Use Case: Federated SQL Access

GUARDA allows you to treat multiple remote databases as a single integrated surface.

### Step 1: Configure Providers
In `config/runtime.exs`, define your backend connections:
```elixir
config :guarda, :providers, [
  %{id: :postgres_main, module: Guarda.Provider.Postgres, url: "postgres://..."},
  %{id: :mysql_legacy, module: Guarda.Provider.Mysql, url: "mysql://..."}
]
```

### Step 2: Querying through the Gateway
You can send a standardized JSON request to the GUARDA endpoint:
```bash
curl -X POST http://localhost:4000/api/query \
  -H "x-api-key: YOUR_SECRET_KEY" \
  -d '{"provider": "postgres_main", "query": "SELECT * FROM users LIMIT 10"}'
```

---

## 3. Use Case: Real-Time Analytics Dashboard

The **Command Center** (the dashboard you are currently viewing) provides a live view of the system health.

- **Active Data Providers**: Shows how many isolated connection processes are currently running.
- **API Security Perimeter**: Shows the number of authenticated researchers/apps currently cached in high-speed memory.

---

## 4. Use Case: Secure Institutional Access

If you are an institution providing data to external researchers:
1. **Issue a JWT or API Key**: Register the key in the GUARDA database.
2. **Isolation**: GUARDA will spawn a dedicated process for that researcher's session, ensuring they cannot impact other users' performance.
3. **Observability**: Monitor their query impact via the LiveView dashboard.

---

## 5. Development & Testing

To run the full integration suite and see federated queries in action:
```bash
# Start the mock backend containers
docker-compose up -d

# Run the integration tests
mix test test/guarda/integration/federation_test.exs
```

For more details, visit the [official repository](https://github.com/KathiraveluLab/GUARDA).
