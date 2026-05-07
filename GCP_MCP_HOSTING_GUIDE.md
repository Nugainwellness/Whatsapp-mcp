# Hosting an MCP Server on Google Cloud with a Public HTTPS Endpoint

This guide covers everything needed to take any MCP server and host it on a GCE instance with a permanent HTTPS endpoint that Claude.ai can connect to via custom connectors.

---

## Architecture Overview

```
Claude.ai (connector)
    │
    ▼
ngrok HTTPS endpoint (permanent static domain)
    │
    ▼
GCE Instance — MCP Server (streamable-http on a local port)
    │
    ▼
Backend service (WhatsApp bridge / Google API / etc.)
```

---

## Part 1: GCE Instance Setup

### 1.1 Create the Instance

```bash
gcloud compute instances create <instance-name> \
  --project=<project-id> \
  --zone=asia-south1-c \
  --machine-type=e2-medium \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=20GB
```

### 1.2 Add Firewall Rules

Add a rule for each port your MCP server will listen on:

```bash
gcloud compute firewall-rules create allow-<port> \
  --project=<project-id> \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:<port> \
  --source-ranges=0.0.0.0/0
```

### 1.3 SSH into the Instance

```bash
gcloud compute ssh admin@<instance-name> --project=<project-id> --zone=asia-south1-c
```

---

## Part 2: Install Dependencies

### 2.1 Node.js (for Node/TypeScript MCPs)

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
node --version   # should print v20.x.x
```

### 2.2 Python + uv (for Python MCPs)

```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc
uv --version
```

### 2.3 Go (for Go-based services)

```bash
# Check go.mod for required version, then install
curl -sL https://go.dev/dl/go1.25.0.linux-amd64.tar.gz -o /tmp/go.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf /tmp/go.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc
go version
```

### 2.4 Install ngrok

```bash
curl -sL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo 'deb https://ngrok-agent.s3.amazonaws.com buster main' | sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt-get update && sudo apt-get install -y ngrok
```

---

## Part 3: Deploying the MCP Server

### 3.1 Copy Files to Instance

From your local machine:

```bash
gcloud compute scp --recurse /path/to/your-mcp admin@<instance-name>:/home/admin/ \
  --project=<project-id> --zone=asia-south1-c
```

### 3.2 Modify the MCP Server to Use HTTP Transport

Claude.ai connectors require **streamable HTTP transport** (MCP spec 2025-03-26). The default for most MCPs is stdio — you need to change this.

#### For Python (FastMCP)

**Install/upgrade MCP library:**
```bash
cd ~/your-mcp-server
uv add 'mcp[cli]' --upgrade
```

**In `main.py`, change the FastMCP constructor and run call:**

```python
# Before
mcp = FastMCP("your-server-name")
...
mcp.run(transport='stdio')

# After
mcp = FastMCP("your-server-name", host="0.0.0.0", port=<PORT>)
...
mcp.run(transport='streamable-http')
```

Install deps:
```bash
uv sync
```

#### For Node.js / TypeScript

**In `src/index.ts`, replace the stdio transport:**

```typescript
// Remove this import:
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

// Add this import:
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import express from "express";

// Replace the main() function:
async function main() {
  const app = express();
  app.use(express.json());

  app.all("/mcp", async (req, res) => {
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
    res.on("close", () => transport.close());
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  });

  const port = parseInt(process.env.PORT || "<PORT>");
  app.listen(port, "0.0.0.0", () => {
    console.error(`MCP server running on http://0.0.0.0:${port}/mcp`);
  });
}
```

Rebuild:
```bash
npm install && npm run build
```

---

## Part 4: Create Systemd Services

### 4.1 MCP Server Service

Create `/etc/systemd/system/<your-mcp>.service`:

**For Python:**
```ini
[Unit]
Description=Your MCP Server
After=network.target

[Service]
Type=simple
User=admin
WorkingDirectory=/home/admin/your-mcp-server
ExecStart=/home/admin/.local/bin/uv run python main.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=your-mcp

[Install]
WantedBy=multi-user.target
```

**For Node.js:**
```ini
[Unit]
Description=Your MCP Server
After=network.target

[Service]
Type=simple
User=admin
WorkingDirectory=/home/admin/your-mcp
ExecStart=/usr/bin/node dist/index.js
Environment=PORT=<PORT>
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=your-mcp

[Install]
WantedBy=multi-user.target
```

**For Go:**
```ini
[Unit]
Description=Your Go Service
After=network.target

[Service]
Type=simple
User=admin
WorkingDirectory=/home/admin/your-go-service
ExecStart=/usr/local/go/bin/go run main.go
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=your-go-service

[Install]
WantedBy=multi-user.target
```

### 4.2 ngrok Tunnel Service

Each MCP needs its own ngrok account (free tier = 1 static domain per account).

**Configure ngrok with a separate config file per account:**
```bash
ngrok config add-authtoken <NGROK_AUTH_TOKEN> --config ~/.config/ngrok/ngrok-<name>.yml
```

Create `/etc/systemd/system/ngrok-<name>.service`:
```ini
[Unit]
Description=ngrok Tunnel for Your MCP
After=network-online.target <your-mcp>.service
Wants=network-online.target

[Service]
Type=simple
User=admin
ExecStart=/usr/local/bin/ngrok http --url=<your-static-domain>.ngrok-free.dev --config /home/admin/.config/ngrok/ngrok-<name>.yml <PORT>
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ngrok-<name>

[Install]
WantedBy=multi-user.target
```

### 4.3 Enable and Start Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable <your-mcp> ngrok-<name>
sudo systemctl start <your-mcp> ngrok-<name>
```

---

## Part 5: Connect to Claude.ai

1. Go to **Claude.ai → Settings → Integrations → Add custom connector**
2. Enter the URL:
   ```
   https://<your-static-domain>.ngrok-free.dev/mcp
   ```
3. Click **Add** → **Connect**

---

## Part 6: Useful Commands

```bash
# Check status of all services
sudo systemctl status <your-mcp> ngrok-<name>

# Restart services
sudo systemctl restart <your-mcp> ngrok-<name>

# View live logs
sudo journalctl -u <your-mcp> -f
sudo journalctl -u ngrok-<name> -f

# Check what's running on a port
ss -tlnp | grep <PORT>

# Kill a process on a port (if port already in use on restart)
fuser -k <PORT>/tcp
```

---

## Part 7: Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| Service crashes with `address already in use` | Old process still holding the port | `fuser -k <PORT>/tcp` then restart service |
| `status=200/CHDIR` | Wrong `WorkingDirectory` in service file | Fix the path in the `.service` file |
| Claude.ai shows "Connect" but nothing happens | Server using old SSE transport, not streamable-http | Upgrade MCP lib and change transport |
| `go.mod: invalid go version` | Go on instance is older than required | Install the correct Go version |
| ngrok tunnel URL keeps changing | Using anonymous tunnel | Use named tunnel with `--url=` and static domain |
| Port 8080/8081 not reachable externally | Missing GCP firewall rule | Add firewall rule via `gcloud compute firewall-rules create` |

---

## Current Services on This Instance

| Service | Port | URL | Description |
|---|---|---|---|
| `whatsapp-bridge` | 8080 | — | Go bridge, WhatsApp REST API |
| `whatsapp-mcp-server` | 8081 | `https://condition-line-regress.ngrok-free.dev/mcp` | WhatsApp MCP |
| `google-workspace-mcp` | 8082 | `https://hummus-finance-aggregate.ngrok-free.dev/mcp` | Google Workspace MCP |

When adding a new MCP, use the next available port (8083, 8084, ...) and a new ngrok account.
