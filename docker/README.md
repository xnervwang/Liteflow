### Building Docker Images

#### Method 1: Build from Remote Git Repository (Using Default Repository and Branch)
Use case: Use the stable version directly from the author's repository
```
docker build --build-arg BRANCH=master -t liteflow:master .
```
- Code source: Automatically downloaded from `https://github.com/zhc105/Liteflow.git`
- Branch used: master (can specify other branches via BRANCH parameter)

#### Method 2: Build from Specified Remote Git Repository and Branch
Use case: Use code from other forked repositories or specific branches
```
docker build --build-arg SOURCE=https://github.com/zhc105/Liteflow.git --build-arg BRANCH=master -t liteflow:master .
```
- Code source: Downloaded from the specified Git repository URL
- Branch used: Specified via BRANCH parameter

#### Method 3: Build Using Local Current Directory Code (No Git Download)
Use case: Development and testing phase, using locally modified code (including uncommitted changes)
```
# option 1
docker build --build-arg SOURCE=local -t liteflow:local .
# option 2
docker build --build-arg SOURCE=. -t liteflow:local .
# option 3
docker build --build-arg SOURCE=./ -t liteflow:local .
```
- Code source: Use code files directly from the current directory
- No network connection required; can include uncommitted local modifications

### Starting Containers

#### Method 1: Dynamic Configuration Generation Using Environment Variables

Script example:
```bash
#!/bin/bash

entrance_rules=$(cat <<- EOM
EOM
)

forward_rules=$(cat <<- EOM
    {
        "tunnel_id": 100,                   // Tunnel ID corresponds to server-side entrance_rules
        "destination_addr": "127.0.0.1",    // Specify forwarding target address for this tunnel
        "destination_port": 1501            // Specify forwarding target port
    },
EOM
)

connect_peers=$(cat <<- EOM
    "1.2.3.4:1901",
EOM
)

docker run --network host --name liteflow-main -d --restart=always \
    --env tag="main" \
    --env max_incoming_peers="0" \
    --env connect_peers="$connect_peers" \
    --env node_id="1001" \
    --env password="your-password" \
    --env entrance_rules="$entrance_rules" \
    --env forward_rules="$forward_rules" \
    liteflow:master
```

#### Method 2: Using Pre-configured Configuration File

**Step 1**: Prepare configuration file
```bash
# Create configuration file, you can refer to examples in the examples/ directory
cat > /host/path/to/liteflow.conf << 'EOF'
{
    "service": {
        "max_incoming_peers": 0,
        "connect_peers": [
            "1.2.3.4:1901"
        ],
        "node_id": 1001,
        "listen_addr": "0.0.0.0",
        "listen_port": 0
    },
    "transport": {
        "password": "your-password"
    },
    "entrance_rules": [
    ],
    "forward_rules": [
        {
            "tunnel_id": 100,
            "destination_addr": "127.0.0.1",
            "destination_port": 1501
        }
    ]
}
EOF
```

**Step 2**: Start container and mount configuration file
```bash
docker run --network host --name liteflow-main -d --restart=always \
    -v /host/path/to/liteflow.conf:/app/config/liteflow.conf \
    --env confpath="/app/config/liteflow.conf" \
    liteflow:master
```

**Important Notes**:
- The container will check if the configuration file exists, and will fail to start if it doesn't exist
- When using a pre-configured file, all environment variable configuration parameters will be ignored
