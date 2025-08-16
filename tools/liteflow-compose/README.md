# liteflow-compose
A tool for convenient management and generation of configuration files for multiple liteflow instances within a cluster. By defining node instances and tunnel information through YAML files, this tool automatically generates JSON configuration files for each node, eliminating the need for manual maintenance and reducing the risk of human errors.

## Usage Instructions
First, prepare two YAML files: one file to define all node instances and information in the current cluster, and another file to define all tunnel information. For specific file formats, please refer to the examples provided in the example-regular directory.

Then run:
```
./liteflow-compose.py -n <nodes.yaml file path> -t <nodes.yaml file path> <output_dir>
```

In the specified `<output_dir>` output directory, you can find configuration files for all instances.

Upon completion, the tool will display information about other instances and ports connected to each instance, as well as all ports that instances listen on, to facilitate firewall rule configuration.

This tool includes an example; please run:
```
./liteflow-compose.py -n example-regular/nodes.yaml -t example-regular/tunnels.yaml example-regular/output
```

This tool will check whether the format and content of the provided YAML meet the requirements.

## Generating Topology Diagrams
This tool can generate Graphviz dot files and graphics (supports png, svg, pdf, jpg, jpeg, bmp, gif, tiff formats). Run:
```
./draw-graphviz.py -n <nodes.yaml file path> -t <nodes.yaml file path> -d <generated .dot file path> -i <generated image file path>
```

For example, the provided example will generate graphics like this:
```
./draw-graphviz.py -n example-regular/nodes.yaml -t example-regular/tunnels.yaml -d example-regular/output/liteflow.dot -i example-regular/output/liteflow.png
```
![liteflow.png](./example-regular/output/liteflow.png)

## Generating Firewall Rules
Used to generate inbound and outbound firewall rules for all liteflow nodes, as well as outbound firewall rules for clients. All rules are output as YAML files for reference when setting up firewalls. Each liteflow node or each client will generate a separate YAML file.

This tool includes an example; please run:
```
./generate-firewall-rules.py -n example-firewall-rules/nodes.yaml -t example-firewall-rules/tunnels.yaml -c example-firewall-rules/clients.yaml example-firewall-rules/output
```

## Advanced: Disaster Recovery Backup
In liteflow settings, `entrance_rule` can explicitly specify the `node_id` of the node at the other end of the tunnel, then this rule will only forward to that specified next-level node. For example:
```json
{
    "tunnel_id": 1011,
    "listen_addr": "0.0.0.0",
    "listen_port": 1010,
    "protocol": "tcp",
    "node_id": 1
}
```

If `entrance_rule` does not specify the next-level `node_id`, liteflow will only forward the tunnel data to any one of its peers. If this peer later disconnects, liteflow will choose to forward to the next peer. This is a disaster recovery backup to prevent a single forward node failure from making a tunnel completely unavailable. Please note that this cannot be used to implement load balancing.

Similarly, `forward_rule` has similar behavior. If `node_id` is specified in `forward_rule`, it can only accept user connections from that node. Otherwise, it can accept user connections from any peer. This is to prevent a single `entrance` node failure from making a tunnel completely unavailable.

> ⚠️ Please note that if `entrance_rule` does not specify `node_id`, this node will arbitrarily choose one from all connected peers to send to, even if that peer does not support that `tunnel_id`. This is because the two peers do not exchange `tunnel_id` lists when connecting, and neither side knows the `tunnel_id` information supported by the other.
>
> **Therefore, Liteflow is designed so that each process supports only a single-purpose tunnel. If multiple tunnels are needed, it is recommended to start separate Liteflow processes for each tunnel, each with its own configuration file.**

In liteflow-compose settings, this can be achieved by setting multiple `entrance` or `forward` under one rule, please refer to the example.

Under the same rule, if there are more than one `forward`, then its `entrance` can set `explicit` to `false` (default is `true`), and the generated `entrance_rule` will not set the `node_id` of the `forward` node.

Correspondingly, if there is only a single `entrance`, then its `forward` can set `explicit` to `true` (default is `false`), and the generated `forward_rule` will strictly specify the `node_id` of the `entrance` node.
