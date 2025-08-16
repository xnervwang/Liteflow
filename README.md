**This README is also available in [简体中文](README.cn.md).**

# Liteflow
UDP tunnel & TCP/UDP Port forwarding

### Introduction

Liteflow implements a simple and reliable UDP transport protocol (LiteDT), and based on this protocol, develops a TCP/UDP port forwarding tool. Both the client and the server use the same binary, with the only difference being the configuration file.

You can use this tool to:

1. Accelerate TCP transmission speed in high-latency and high-packet-loss environments, or ensure UDP packets are delivered reliably and in order.
2. Map internal network ports to public servers through reverse connections, enabling internal ports to be actively accessed across NAT.

### Build and Usage Guide
```
# Clone the repo and create build directory
git submodule update --init --recursive
mkdir build && cd build

# Option 1: Build and install to a specified directory (recommended)
cmake -DCMAKE_INSTALL_PREFIX=<install_folder> ..
make
make install

# Option 2: Build and install to system directory (if there's only one liteflow process on the VM)
cmake ..
make
sudo make install

# Enter the installation directory
cd <install_folder>

# Help
./bin/liteflow --help

# Check version
./bin/liteflow --version

# Deploy configuration file
# Example configs are in the etc folder, copy to etc/liteflow.conf and modify accordingly

# Test whether the configuration file is valid
./bin/liteflow -t -c ./liteflow.conf

# Run; it reads the config file named {binary_name}.conf in the current directory by default. For example, if the binary is liteflow, config file should be liteflow.conf
./bin/liteflow

# Or specify config file path
./liteflow -c /path/to/config

# Reload config (currently only supports reloading entrance_rules and forward_rules)
kill -SIGUSR1 $(liteflow_pid)
```

A set of control scripts is provided to make integration with crontab or systemd easier. If installed to a custom directory, each command must use the `--local` flag; otherwise, it operates in system mode.
```
# Enter installation directory and start
# Process PID will be recorded in var/liteflow.pid for later operations
cd <install_folder>
./scripts/liteflow.sh start --local

# Check if process is alive, restart if not
./scripts/liteflow.sh revive --local

# Force reload configuration
./scripts/liteflow.sh reload --local

# Stop the current process
./scripts/liteflow.sh stop --local

# Restart the process
./scripts/liteflow.sh restart --local

# Check current process status
./scripts/liteflow.sh status --local
```

#### Example 1: Server 1.2.3.4 exposes TCP port 1501, mapped to client 192.168.1.100:1501

Deployment:
```
                (Entrance Rule)                                     (Forward Rule)
+--------+            +-------------+     UDP Tunnel     +-------------+             +--------+
| Client |  --------> | Liteflow(C) |  --------------->  | Liteflow(S) |  ---------> | Server |
+--------+  TCP:1501  +-------------+      UDP:1901      +-------------+   TCP:1501  +--------+
                       192.168.1.100                         1.2.3.4
```

Server (1.2.3.4) config example:
```
{
    "service": {
        "debug_log": 0,
        "max_incoming_peers": 10,
        "node_id": 1002,
        "listen_addr": "0.0.0.0",
        "listen_port": 1901
    },
    "forward_rules": [
        {
            "tunnel_id": 100,
            "destination_addr": "127.0.0.1",
            "destination_port": 1501,
            "protocol": "tcp"
        }
    ]
}
```

Client (192.168.1.100) config example:
```
{
    "service": {
        "debug_log": 0,
        "connect_peers": [
            "1.2.3.4:1901"
        ],
        "node_id": 1001
    },
    "entrance_rules": [
        {
            "listen_addr": "0.0.0.0",
            "listen_port": 1501,
            "tunnel_id": 100,
            "protocol": "tcp"
        }
    ]
}
```

#### Example 2: Client 192.168.1.100 exposes TCP port 1501, mapped to server 1.2.3.4:1501 via reverse connection

Deployment:
```
                (Entrance Rule)                                     (Forward Rule)
+--------+            +-------------+     UDP Tunnel     +-------------+             +--------+
| Client |  --------> | Liteflow(S) |  <---------------  | Liteflow(C) |  ---------> | Server |
+--------+  TCP:1501  +-------------+      UDP:1901      +-------------+   TCP:1501  +--------+
                          1.2.3.4                         192.168.1.100
```

Server (1.2.3.4) config example:
```
{
    "service": {
        "debug_log": 0,
        "max_incoming_peers": 10,
        "node_id": 1002,
        "listen_addr": "0.0.0.0",
        "listen_port": 1901
    },
    "entrance_rules": [
        {
            "listen_addr": "0.0.0.0",
            "listen_port": 1501,
            "tunnel_id": 100,
            "node_id": 1001
        }
    ]
}
```

Client (192.168.1.100) config example:
```
{
    "service": {
        "debug_log": 0,
        "connect_peers": [
            "1.2.3.4:1901"
        ],
        "node_id": 1001
    },
    "forward_rules": [
        {
            "tunnel_id": 100,
            "destination_addr": "127.0.0.1",
            "destination_port": 1501
        }
    ]
}
```

#### `node_id` in `entrance_rule`
⚠️ Note: If `entrance_rule` does not specify a node_id, the current node will arbitrarily select one of the connected peers to send the data to — even if that peer does not support the specified `tunnel_id`. This happens because peers do not exchange their supported `tunnel_id` lists during the connection process, so neither side is aware of the other's `tunnel_id` capabilities.

**Liteflow is designed so that each process supports only a single-purpose tunnel. If multiple tunnels are needed, it is recommended to run separate Liteflow processes, each with its own configuration file.**

### Building Windows Version via Cygwin
Liteflow supports building a Windows version using Cygwin.

Cygwin must have the following packages installed:
* git
* gcc-core
* gcc-g++
* make
* automake
* cmake
* autoconf
* libtool
* libargp-devl

The remaining compilation steps follow the standard procedure. After compilation, copy the following files to the Windows machine where you want to run Liteflow. Prepare the corresponding configuration files, then run liteflow.exe directly.
* cygwin1.dll
* cygargp-0.dll
* liteflow.exe

⚠️ Note: The default DNS server configuration on Cygwin appears to be problematic. Please specify a working DNS server in the `service` section of the configuration file, for example: `"dns_server": "8.8.8.8",`.

#### How to Run liteflow in the Background at Startup
Since liteflow is a command-line program, it’s recommended to use cmder to automatically launch it when Windows starts and minimize it to the system tray.
1. Download cmder. In `Settings...` → `General` → `Task bar`, check the option `Auto minimize to TSA`.
2. Create a shortcut to Cmder.exe. Right-click the shortcut, and in the `Target` field, add the following suffix:
    ```bash
    /TASK "liteflow" /x -MinTSA
    ```
    The final result should look something like:
    ```bash
    "C:\tools\cmder\Cmder.exe" /TASK "liteflow" /x -MinTSA
    ```
3. In File Explorer, type `shell:startup` and press Enter to open the Startup folder. Move the shortcut into this folder to enable auto-start.