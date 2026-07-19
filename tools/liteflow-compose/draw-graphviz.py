# Copyright (c) 2025, Xnerv Wang <xnervwang@gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

#!/usr/bin/env python3

import argparse
import yaml
import sys
import os
import re
import random
import subprocess
import secrets
from graphviz import Digraph

SUPPORTED_IMAGE_FORMATS = {"png", "svg", "pdf", "jpg", "jpeg", "bmp", "gif", "tiff"}

# ---------------- colors: full-random helpers ----------------

def _hex_to_rgb(hexstr: str):
    s = hexstr.strip().lstrip("#")
    return tuple(int(s[i:i+2], 16) for i in (0, 2, 4))

def _rgb_to_hex(rgb):
    return "#{:02X}{:02X}{:02X}".format(*rgb)

def rand_hex() -> str:
    """Uniformly random color over full RGB space."""
    return "#{:06X}".format(random.randint(0, 0xFFFFFF))

def _lighten(hex_color: str, ratio: float = 0.88) -> str:
    """Lighten color toward white (0..1)."""
    r, g, b = _hex_to_rgb(hex_color)
    nr = int(r + (255 - r) * ratio)
    ng = int(g + (255 - g) * ratio)
    nb = int(b + (255 - b) * ratio)
    return _rgb_to_hex((min(255, nr), min(255, ng), min(255, nb)))

def _text_on(bg_hex: str) -> str:
    """Choose black/white text for readability on given background."""
    r, g, b = _hex_to_rgb(bg_hex)
    brightness = (r * 299 + g * 587 + b * 114) / 1000  # perceptual
    return "#111827" if brightness >= 150 else "#FFFFFF"

def build_theme_random():
    """
    Pick random colors for each class.
    Edges:   link / tunnel / ssh
    Nodes:   gateway / proxy / client
    Same class uses same color within one run.
    """
    link_c   = rand_hex()
    tunnel_c = rand_hex()
    ssh_c    = rand_hex()

    gw_c   = rand_hex()
    prox_c = rand_hex()
    cli_c  = rand_hex()

    gw_fill   = _lighten(gw_c,   0.88)
    prox_fill = _lighten(prox_c, 0.90)
    cli_fill  = _lighten(cli_c,  0.92)

    theme = {
        "graph": dict(bgcolor="white", fontname="Helvetica", fontsize="10",
                      margin="0.2", pad="0.2", rankdir="LR"),

        # edges
        "edge_link":   dict(color=link_c,   penwidth="2.2", arrowsize="0.95",
                            fontname="Helvetica", fontsize="9", labelfontcolor=link_c),
        "edge_tunnel": dict(color=tunnel_c, fontcolor=tunnel_c, style="dashed",
                            penwidth="2.4", arrowsize="0.95", fontsize="9"),
        "edge_ssh":    dict(color=ssh_c,    fontcolor=ssh_c,    style="dotted",
                            penwidth="2.4", arrowsize="1.05", fontsize="9"),

        # nodes
        "node_gateway": dict(shape="box", style="rounded,filled",
                             color=gw_c, fillcolor=gw_fill,
                             fontname="Helvetica", fontcolor=_text_on(gw_fill), fontsize="10",
                             margin="0.12,0.08"),
        "node_proxy":   dict(shape="circle", style="filled",
                             color=prox_c, fillcolor=prox_fill,
                             fontname="Helvetica", fontcolor=_text_on(prox_fill), fontsize="10",
                             margin="0.08,0.08"),
        "node_client":  dict(shape="box", style="rounded,filled",
                             color=cli_c, fillcolor=cli_fill,
                             fontname="Helvetica", fontcolor=_text_on(cli_fill), fontsize="10",
                             margin="0.10,0.08"),
    }

    print(f"[colors] link={link_c}, tunnel={tunnel_c}, ssh={ssh_c}; "
      f"gateway={gw_c}, proxy={prox_c}, client={cli_c}")
    return theme

# ---------------- YAML IO ----------------

def load_yaml(file_path):
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f)
    except Exception as e:
        print(f"❌ Error loading YAML '{file_path}': {e}", file=sys.stderr)
        sys.exit(1)

def parse_nodes(nodes_data):
    nodes = {}
    for node_name, config in nodes_data.items():
        node_id = config["service"]["node_id"]
        listen_endpoint = config["service"].get("listen_endpoint")
        nodes[node_id] = {
            "name": node_name,
            "listen_endpoint": listen_endpoint,
            "connect_peers": config["service"].get("connect_peers", []),
        }
    return nodes

def parse_tunnels(tunnels_data):
    tunnels = {}
    for tunnel_name, config in tunnels_data.items():
        group = tunnels.setdefault(tunnel_name, [])
        ids = {}
        if "tcp_tunnel_id" in config:
            ids["tcp_tunnel_id"] = config["tcp_tunnel_id"]
        if "udp_tunnel_id" in config:
            ids["udp_tunnel_id"] = config["udp_tunnel_id"]
        if "ssh_tunnel_id" in config:   # 兼容可能存在的 ssh_tunnel_id
            ids["ssh_tunnel_id"] = config["ssh_tunnel_id"]
        group.append({
            "tunnel_id": ids,
            "entrances": config.get("entrances", []),
            "forwards": config.get("forwards", []),
        })
    return tunnels

def extract_filename_and_extension(filepath, default_name="liteflow.png"):
    filename, ext = os.path.splitext(filepath)
    ext = ext.lstrip(".").lower()
    if not filename:
        filename, ext = os.path.splitext(default_name)
        ext = ext.lstrip(".")
    if ext not in SUPPORTED_IMAGE_FORMATS:
        raise ValueError(f"Unsupported image format: {ext}. "
                         f"Supported: {', '.join(SUPPORTED_IMAGE_FORMATS)}")
    return filename, ext

# ---------------- classification & helpers ----------------

def make_proxy_regex(port: int):
    return re.compile(rf":{port}\b")

def classify_inbounds(nodes_data, tunnels_data, proxy_port: int):
    """
    仅根据入边判断：
      inbound_link:   收到任意 link（实线）
      inbound_tunnel: 收到任意 tunnel（虚线）
      inbound_ssh:    收到任意 ssh（点线）
    """
    proxy_re = make_proxy_regex(proxy_port)
    name_to_id = {info["name"]: nid for nid, info in nodes_data.items()}
    inbound_link, inbound_tunnel, inbound_ssh = set(), set(), set()

    # link：来自 connect_peers
    for nid, data in nodes_data.items():
        for peer_name in data["connect_peers"]:
            pid = next((id_ for id_, info in nodes_data.items()
                        if info["name"] == peer_name), None)
            if pid is not None:
                inbound_link.add(pid)

    # tunnels：根据目标端点区分 tunnel 与 ssh
    for _, tlist in tunnels_data.items():
        for t in tlist:
            for f in t.get("forwards", []):
                dest = (f.get("destination_endpoint") or "")
                fid = name_to_id[f["node"]]
                if proxy_re.search(dest):
                    inbound_tunnel.add(fid)
                elif re.search(r":22\b", dest):
                    inbound_ssh.add(fid)

    return inbound_link, inbound_tunnel, inbound_ssh, name_to_id, proxy_re

def parse_margin(m):
    if isinstance(m, (tuple, list)):
        return float(m[0]), float(m[1])
    s = str(m).strip().strip('"').strip("'")
    if "," in s:
        x, y = s.split(",", 1)
        return float(x), float(y)
    return float(s), float(s)

def estimate_square_side(label: str, fontsize_pt: float, margin_xy):
    """
    估算让标签刚好放下所需的正方形边长（英寸）。
    平均字宽 ~ 0.6*fontsize_pt；行高 ~ 1.2*fontsize_pt；1in=72pt
    """
    mx, my = margin_xy
    lines = label.split("\n")
    max_chars = max((len(l) for l in lines), default=0)
    char_w_in = 0.6 * fontsize_pt / 72.0
    line_h_in = 1.2 * fontsize_pt / 72.0
    need_w = 2 * mx + max_chars * char_w_in
    need_h = 2 * my + len(lines) * line_h_in
    side = max(need_w, need_h) + 0.15
    return max(side, 1.0)

def simplify_tunnel_label(tid: dict, entrance_ep: str, dest_ep: str) -> str:
    """
    形如：
      [tcp:32011, udp:32012]  0.0.0.0:32010 → 127.0.0.1:8388
    """
    parts = []
    if "tcp_tunnel_id" in tid:
        parts.append(f"tcp:{tid['tcp_tunnel_id']}")
    if "udp_tunnel_id" in tid:
        parts.append(f"udp:{tid['udp_tunnel_id']}")
    ids = f"[{', '.join(parts)}]" if parts else ""
    left = entrance_ep or "unknown"
    right = dest_ep or "unknown"
    return f"{ids}  {left} \u2192 {right}".strip()

def simplify_ssh_label(tid: dict, entrance_ep: str) -> str:
    """
    SSH 标签：只显示入口端点，不显示目标端点。
    形如：
      [ssh: 31021]  0.0.0.0:31020
    优先取 ssh_tunnel_id，其次 tcp_tunnel_id，再次 udp_tunnel_id，最后用 '?'
    """
    ssh_id = None
    for k in ("ssh_tunnel_id", "tcp_tunnel_id", "udp_tunnel_id"):
        if k in tid:
            ssh_id = tid[k]
            break
    if ssh_id is None:
        ssh_id = "?"
    ep = entrance_ep or "unknown"
    return f"[ssh: {ssh_id}]  {ep}"

# ---------------- render ----------------

def generate_dot(nodes_data, tunnels_data, proxy_port: int,
                 dot_filename="liteflow.dot", image_filename="liteflow.png"):
    theme = build_theme_random()

    dot = Digraph("Network")
    dot.attr(**theme["graph"])
    dot.attr("edge", **theme["edge_link"])

    inbound_link, inbound_tunnel, inbound_ssh, name_to_id, proxy_re = \
        classify_inbounds(nodes_data, tunnels_data, proxy_port)

    # nodes
    for nid, data in nodes_data.items():
        label = f"{data['name']} ({nid})"
        if data["listen_endpoint"]:
            label += f"\n{data['listen_endpoint']}"

        if nid in inbound_link:
            # gateway（有公网 IP）→ 圆角“正方形”
            attrs = theme["node_gateway"].copy()
            mx, my = parse_margin(attrs.get("margin", "0.10,0.06"))
            side = estimate_square_side(label, float(attrs.get("fontsize", 10)), (mx, my))
            attrs["fixedsize"] = "true"
            attrs["width"] = f"{side:.2f}"
            attrs["height"] = f"{side:.2f}"
        elif (nid in inbound_tunnel) or (nid in inbound_ssh):
            # proxy（无公网，但被隧道/SSH 指向）→ 圆
            attrs = theme["node_proxy"].copy()
        else:
            # client（完全无入边）→ 矩形
            attrs = theme["node_client"].copy()

        dot.node(str(nid), label, **attrs)

    # link edges（实线）
    for nid, data in nodes_data.items():
        for peer_name in data["connect_peers"]:
            pid = next((id_ for id_, info in nodes_data.items()
                        if info["name"] == peer_name), None)
            if pid is not None:
                dot.edge(str(nid), str(pid), **theme["edge_link"])

    # tunnel & ssh edges
    for _, tlist in tunnels_data.items():
        for t in tlist:
            tunnel_id = t.get("tunnel_id", {})
            for e in t.get("entrances", []):
                src = str(name_to_id[e["node"]])
                entrance_ep = e.get("listen_endpoint", "unknown")
                for f in t.get("forwards", []):
                    dst = str(name_to_id[f["node"]])
                    dest_ep = f.get("destination_endpoint", "unknown")

                    if proxy_re.search(dest_ep):
                        style = theme["edge_tunnel"]
                        label = simplify_tunnel_label(tunnel_id, entrance_ep, dest_ep)
                    elif re.search(r":22\b", dest_ep or ""):
                        style = theme["edge_ssh"]
                        label = simplify_ssh_label(tunnel_id, entrance_ep)
                    else:
                        style = theme["edge_link"]
                        label = ""

                    attrs = dict(style)
                    attrs.pop("label", None)  # 防重
                    attrs.setdefault("fontcolor", attrs.get("color", "#333333"))
                    if label:
                        dot.edge(src, dst, label=label, **attrs)
                    else:
                        dot.edge(src, dst, **attrs)

    # output
    dot.save(dot_filename)
    img_base, img_ext = extract_filename_and_extension(image_filename)
    if img_ext != "svg":
        dot.attr(dpi="300")
    dot.render(img_base, format=img_ext, cleanup=True)

if __name__ == "__main__":
    current_dir = os.path.dirname(os.path.abspath(__file__))

    parser = argparse.ArgumentParser(description="Generate Graphviz .dot file and image from YAML files.")
    parser.add_argument("-n", "--nodes_yaml_file", type=str,
        default=os.path.join(current_dir, "example-regular", "nodes.yaml"),
        help="Path to the nodes YAML file.")
    parser.add_argument("-t", "--tunnels_yaml_file", type=str,
        default=os.path.join(current_dir, "example-regular", "tunnels.yaml"),
        help="Path to the tunnels YAML file.")
    parser.add_argument("-d", "--dot_file", type=str,
        default=os.path.join(current_dir, "example-regular", "output", "liteflow.dot"),
        help="Output DOT file name.")
    parser.add_argument("-i", "--image_file", type=str,
        default=os.path.join(current_dir, "example-regular", "output", "liteflow.svg"),
        help="Output image file name.")
    parser.add_argument("--proxy_port", type=int, default=8388,
        help="Destination port that indicates a tunnel edge.")
    parser.add_argument("--color_schema_seed", type=int, default=None,
        help="Seed for color schema selection (set to reproduce the same colors).")

    args = parser.parse_args()
    # 统一确定并打印本次使用的种子
    if args.color_schema_seed is None:
        args.color_schema_seed = secrets.randbits(64)
        print(f"[color-schema] color_schema_seed={args.color_schema_seed} (auto-generated)")
    else:
        print(f"[color-schema] color_schema_seed={args.color_schema_seed}")

    random.seed(args.color_schema_seed)  # 用该种子固定颜色方案

    validate_script = os.path.join(current_dir, "validate-yamls.py")
    validate_args = ["--nodes_yaml_file", args.nodes_yaml_file, "--tunnels_yaml_file", args.tunnels_yaml_file]
    result = subprocess.run(["python", validate_script] + validate_args, stdout=sys.stdout, stderr=sys.stderr)
    if result.returncode != 0:
        sys.exit(result.returncode)

    nodes_yaml = load_yaml(args.nodes_yaml_file)
    tunnels_yaml = load_yaml(args.tunnels_yaml_file)

    nodes_data = parse_nodes(nodes_yaml)
    tunnels_data = parse_tunnels(tunnels_yaml)

    generate_dot(nodes_data, tunnels_data, args.proxy_port, args.dot_file, args.image_file)
    print(f"✅ Generated dot file {args.dot_file} and image {args.image_file} successfully.")
