### 编译Docker镜像

#### 方式1: 从远程Git仓库构建（使用默认仓库和分支）
适用场景：直接使用作者仓库的稳定版本
```
docker build --build-arg BRANCH=master -t liteflow:master .
```
- 代码来源：从 `https://github.com/zhc105/Liteflow.git` 自动下载
- 使用分支：master（可通过BRANCH参数指定其他分支）

#### 方式2: 从指定的远程Git仓库和分支构建
适用场景：使用其他fork仓库或特定分支的代码
```
docker build --build-arg SOURCE=https://github.com/zhc105/Liteflow.git --build-arg BRANCH=master -t liteflow:master .
```
- 代码来源：从指定的Git仓库URL下载
- 使用分支：通过BRANCH参数指定

#### 方式3: 使用本地当前目录代码构建（不从Git下载）
适用场景：开发测试阶段，使用本地修改过的代码（包括未提交的更改）
```
# option 1
docker build --build-arg SOURCE=local -t liteflow:local .
# option 2
docker build --build-arg SOURCE=. -t liteflow:local .
# option 3
docker build --build-arg SOURCE=./ -t liteflow:local .
```
- 代码来源：直接使用当前目录的代码文件
- 无需网络连接，可以包含本地未提交的修改

### 启动容器

#### 方式1: 使用环境变量动态生成配置

脚本示例：
```bash
#!/bin/bash

entrance_rules=$(cat <<- EOM
EOM
)

forward_rules=$(cat <<- EOM
    {
        "tunnel_id": 100,                   // Tunnel ID和服务端entrance_rules对应
        "destination_addr": "127.0.0.1",    // 为此Tunnel指定转发目标地址
        "destination_port": 1501            // 指定转发目标端口
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

#### 方式2: 使用预置配置文件

**步骤1**: 准备配置文件
```bash
# 创建配置文件，可以参考 examples/ 目录下的示例
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

**步骤2**: 启动容器并挂载配置文件
```bash
docker run --network host --name liteflow-main -d --restart=always \
    -v /host/path/to/liteflow.conf:/app/config/liteflow.conf \
    --env confpath="/app/config/liteflow.conf" \
    liteflow:master
```

**注意事项**：
- 容器会检查配置文件是否存在，不存在则启动失败
- 使用预置配置文件时，所有环境变量配置参数都会被忽略
