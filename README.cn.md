**点击查看 [English Version](README.md)**

# Liteflow
UDP tunnel &amp; TCP/UDP Port forwarding

### 简介

Liteflow实现了一套简易的可靠UDP传输协议(LiteDT)，并基于这个协议开发了TCP/UDP端口转发工具。Liteflow的客户端和服务端都使用相同的二进制程序，区别只在于配置文件的不同。

你可以用这个工具：

1. 加速TCP协议在高延迟高丢包环境的传输速度，或者保障UDP包传输不丢包并且有序。
2. 通过反向连接将内网端口映射至外网服务器，实现内网端口可以穿越NAT被主动访问。


### 编译和使用手册
```
# clone repo并创建编译目录
git submodule update --init --recursive
mkdir build && cd build

# Option 1: 编译安装到指定目录（推荐）
cmake -DCMAKE_INSTALL_PREFIX=<install_folder> ..
make
make install

# Option 2：编译安装到系统目录（如果VM上只有一个liteflow进程）
cmake ..
make
sudo make install

# 进入安装目录
cd <install_folder>

# 帮助文档
./bin/liteflow --help

# 检查版本
./bin/liteflow --version

# 部署配置文件
# etc目录下有example配置文件，复制到etc/liteflow.conf并进行修改

# 测试配置文件是否合法
./bin/liteflow -t -c ./liteflow.conf

# 运行，默认读取当前目录下的配置文件，文件名为{二进制程序名}.conf。如程序名为liteflow，则配置文件名为liteflow.conf
./bin/liteflow

# 或者指定配置文件路径运行
./liteflow -c /path/to/config

# 重新加载配置(目前仅支持重新加载entrance_rules和forward_rules)
kill -SIGUSR1 $(liteflow_pid)
```

本工具提供了一套控制脚本，便于集成到crontab或systemd使用。如果是编译安装到指定目录，则每个命令都需要带`--local`参数，否则将以系统目录模式运行。
```
# 进入安装目录并启动
# 进程PID会记录在var/liteflow.pid中，用于后续命令操作
cd <install_folder>
./scripts/liteflow.sh start --local

# 检查当前进程是否存活，如果不存活则重启
./scripts/liteflow.sh revive --local

# 强制重新加载配置文件
./scripts/liteflow.sh reload --local

# 停止当前进程
./scripts/liteflow.sh stop --local

# 重启当前进程
./scripts/liteflow.sh restart --local

# 检查当前进程状态
./scripts/liteflow.sh status --local
```

#### 示例1： 服务端1.2.3.4开放TCP 1501端口，映射到客户端192.168.1.100:1501

部署方式：
```
                (Entrance Rule)                                     (Forward Rule)
+--------+            +-------------+     UDP Tunnel     +-------------+             +--------+
| Client |  --------> | Liteflow(C) |  --------------->  | Liteflow(S) |  ---------> | Server |
+--------+  TCP:1501  +-------------+      UDP:1901      +-------------+   TCP:1501  +--------+
                       192.168.1.100                         1.2.3.4
```

服务端(1.2.3.4)配置示例
```
{
    "service": {
        "debug_log": 0,
        "max_incoming_peers": 10,               // 允许同时被最多10个节点访问
        "node_id": 1002,                        // 指定此节点的Node ID
        "listen_addr": "0.0.0.0",               // 节点监听地址
        "listen_port": 1901,                    // 监听端口
    },
    "forward_rules": [
        {
            "tunnel_id": 100,                   // Tunnel ID需要和客户端entrance_rules对应
            "destination_addr": "127.0.0.1",    // 为此Tunnel指定转发目标地址
            "destination_port": 1501,           // 指定转发目标端口
            "protocol": "tcp",                  // 转发协议，不填时默认采用TCP，需要和entrance_rules监听协议一致
        },
    ]
}
```

客户端(192.168.1.100)配置示例
```
{
    "service": {
        "debug_log": 0,
        "connect_peers": [
            "1.2.3.4:1901",             // 节点启动后主动连接1.2.3.4:1901
        ],
        "node_id": 1001,                // 指定此节点的Node ID
    },
    "entrance_rules": [
        {
            "listen_addr": "0.0.0.0",   // 为此Tunnel指定监听地址
            "listen_port": 1501,        // 指定监听端口
            "tunnel_id": 100,           // Tunnel ID和服务端forward_rules对应
            "protocol": "tcp",          // 监听协议，不填时默认采用TCP，需要和forward_rules转发协议一致
        },
    ]
}
```

#### 示例2： 客户端192.168.1.100开放TCP 1501端口，通过反向连接映射到服务端1.2.3.4:1501

部署方式：
```
                (Entrance Rule)                                     (Forward Rule)
+--------+            +-------------+     UDP Tunnel     +-------------+             +--------+
| Client |  --------> | Liteflow(S) |  <---------------  | Liteflow(C) |  ---------> | Server |
+--------+  TCP:1501  +-------------+      UDP:1901      +-------------+   TCP:1501  +--------+
                          1.2.3.4                         192.168.1.100
```

服务端(1.2.3.4)配置示例
```
{
    "service": {
        "debug_log": 0,
        "max_incoming_peers": 10,       // 允许同时被最多10个节点访问
        "node_id": 1002,                // 指定此节点的Node ID
        "listen_addr": "0.0.0.0",       // 节点监听地址
        "listen_port": 1901,            // 监听端口
    },
    "entrance_rules": [
        {
            "listen_addr": "0.0.0.0",   // 为此Tunnel指定监听地址
            "listen_port": 1501,        // 指定监听端口
            "tunnel_id": 100,           // Tunnel ID需要和客户端forward_rules对应
            "node_id": 1001,            // 限制此入口仅转发至Node 1001
        },
    ]
}
```

客户端(192.168.1.100)配置示例
```
{
    "service": {
        "debug_log": 0,
        "connect_peers": [
            "1.2.3.4:1901",
        ],
        "node_id": 1001,                        // 指定此节点的Node ID
    },
    "forward_rules": [
        {
            "tunnel_id": 100,                   // Tunnel ID和服务端entrance_rules对应
            "destination_addr": "127.0.0.1",    // 为此Tunnel指定转发目标地址
            "destination_port": 1501,           // 指定转发目标端口
        },
    ]
}
```

#### `entrance_rule`的`node_id`
⚠️ 请注意，如果`entrance_rule`不指定`node_id`，则本节点会从所有连接的peers中任意选择一个发送，即使该peer并不支持该`tunnel_id`。两个peer在连接时并不会交换`tunnel_id`列表，双方并不知晓对方所支持的`tunnel_id`信息。

**因此，Liteflow 被设计为每个进程仅支持一个用途单一的隧道。若需使用多个隧道，建议为每个隧道分别启动独立的 Liteflow 进程，并配以各自的配置文件。**

### Cygwin编译Windows版本
Liteflow支持通过Cygwin编译提供Windows可用版本。

Cygwin必须至少安装以下Packages：
* git
* gcc-core
* gcc-g++
* make
* automake
* cmake
* autoconf
* libtool
* libargp-devel

其它编译步骤与正常流程相同。编译完成后，将以下文件复制到需要运行Liteflow的Windows机器上，准备好相应的配置文件并直接运行`liteflow.exe`。
* cygwin1.dll
* cygargp-0.dll
* liteflow.exe

⚠️ 注意Cygwin上的默认DNS服务器配置似乎有问题，请在配置文件的`service`一节中设置可用的DNS服务器，例如`"dns_server": "8.8.8.8",`。

#### 如何开机后台运行liteflow
由于liteflow为命令行程序，建议使用cmder，在Windows登录后自动启动liteflow，并自动最小化到系统托盘。
1. 下载cmder，在`Settings...` -> `General` -> `Task bar`里选中`Auto minimize to TSA`。
2. 创建cmder.exe的快捷方式，右键点击该快捷方式，在"目标"里添加后缀参数
    ```bash
    /TASK "liteflow" /x -MinTSA
    ```
    最终的结果看起来像例如
    ```bash
    C:\tools\cmder\Cmder.exe /TASK "liteflow" /x -MinTSA`
    ```
3. 在文件浏览器中粘贴`shell:startup`并回车，打开自动启动目录。将该快捷方式移入该目录。
