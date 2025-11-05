

# 🧩 Tic-Tac-Toe Backend (Nakama + CockroachDB)

A simple **multiplayer Tic-Tac-Toe** backend built using **[Nakama](https://heroiclabs.com/docs/)** and **CockroachDB**.
This project provides full **server-authoritative match logic**, **real-time updates**, and **turn handling** for two-player gameplay.

---

## 🚀 Features

* ✅ Two-player matchmaking (manual or auto)
* 🎮 Real-time, turn-based gameplay
* ⏱️ 15-second turn timer
* 🔄 Rematch / Restart support
* ⚡ Rejoin grace period for disconnects
* 🧠 Server-side win and draw validation
* 🗄️ Persistent storage using CockroachDB
* 🧩 Modular Lua scripts for clean separation (logic + RPCs)

---

## ⚙️ Tech Stack

| Component          | Description                                                      |
| ------------------ | ---------------------------------------------------------------- |
| **Nakama**         | Game-server framework handling matches, sessions, RPCs           |
| **Lua**            | For match logic (`tiktaktoe.lua`) and RPCs (`tiktaktoe_rpc.lua`) |
| **CockroachDB**    | Distributed SQL database for persistence                         |
| **Docker Compose** | For local orchestration of both services                         |

---

## 📂 Repository Structure

```
TTT-backend/
│
├── tiktaktoe.lua          # Core match logic
├── tiktaktoe_rpc.lua      # RPCs for match creation and pairing
├── docker-compose.yml     # Service orchestration
├── Dockerfile             # Optional build for Nakama extensions
└── README.md              # This file
```

---

## 🧱 Prerequisites

* [Docker](https://www.docker.com/)
* [Docker Compose](https://docs.docker.com/compose/)
* Git Bash (Windows) or any terminal with Docker access

---

## 🧰 Setup Instructions

### 1️⃣ Clone the Repository

```bash
git clone https://github.com/sanah-saleem/TTT-backend.git
cd TTT-backend
```

---

### 2️⃣ Start CockroachDB First

Run the following command to start **only CockroachDB** first (it will run in the background):

```bash
docker compose up -d cockroach
```

---

### 3️⃣ Create the Nakama Database

After CockroachDB starts, create the `nakama` database inside it.

For **Windows Git Bash**, run:

```bash
MSYS_NO_PATHCONV=1 docker exec -it cockroach /cockroach/cockroach sql --insecure --host=cockroach -e "CREATE DATABASE IF NOT EXISTS nakama;"
```

For **Linux/macOS**, simply run:

```bash
docker exec -it cockroach /cockroach/cockroach sql --insecure --host=cockroach -e "CREATE DATABASE IF NOT EXISTS nakama;"
```

---

### 4️⃣ Start Nakama Server

Once the database is created, bring up Nakama:

```bash
docker compose up -d nakama
```

Now both services are live:

* **Nakama HTTP Console:** [http://localhost:7351](http://localhost:7351)
* **CockroachDB Console:** [http://localhost:8080](http://localhost:8080)

---

## ▶️ Game Flow Overview

| Step | Description                        |
| ---- | ---------------------------------- |
| 1️⃣  | Player 1 creates or joins a match  |
| 2️⃣  | Player 2 joins — game starts       |
| 3️⃣  | Players take turns (15 s limit)    |
| 4️⃣  | Server checks for win/draw         |
| 5️⃣  | Clients receive live state updates |
| 6️⃣  | Players can request a rematch      |

---

## 🧩 Opcodes Used

| Opcode | Purpose              |
| ------ | -------------------- |
| `1`    | Player Move          |
| `2`    | Broadcast Game State |
| `3`    | Error Message        |
| `4`    | Restart Game         |

---

## 🧠 Game Rules

* 15 seconds per turn (`TURN_MS = 15000`)
* 20 seconds rejoin grace (`REJOIN_GRACE_MS = 20000`)
* Auto-termination after inactivity
* Match restarts only when both players agree

---

## 🧪 RPCs Registered

| RPC Name           | Description                           |
| ------------------ | ------------------------------------- |
| `create_match`     | Creates a new Tic-Tac-Toe match       |
| `rpc_auto_pairing` | Auto-pairs players through matchmaker |

---

## 🧾 Docker Compose Summary

Your `docker-compose.yml` spins up:

* **CockroachDB** at `localhost:26257`
* **Nakama** at `localhost:7350 (gRPC)` and `localhost:7351 (HTTP)`
* Automatically mounts your Lua modules from `./modules` → `/nakama/modules`

---

## 🧩 Stopping Containers

```bash
docker compose down
```

To remove all data (including match history and DB data):

```bash
docker compose down -v
```

---

## 📜 License

MIT — free to use, modify, and learn from.

