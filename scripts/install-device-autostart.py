#!/usr/bin/env python3
"""Opt-in per-user desktop autostart. Does not change login, Wi-Fi or privileges."""
import argparse
import os
from pathlib import Path
import shutil

parser = argparse.ArgumentParser(description="为当前用户安装或移除 Alice 设备模式自启动")
parser.add_argument("bundle", nargs="?", type=Path, help="包含 alice_companion 的完整 bundle 目录")
parser.add_argument("--remove", action="store_true")
args = parser.parse_args()
config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "alice-launcher"
entry = config / "autostart/alice-device.desktop"
if args.remove:
    entry.unlink(missing_ok=True)
    (data / "device-supervisor.py").unlink(missing_ok=True)
    print("已移除 Alice 自启动，宠物存档和音乐保留。")
else:
    if args.bundle is None:
        parser.error("请提供 bundle 目录")
    binary = args.bundle.resolve() / "alice_companion"
    if not binary.is_file() or not os.access(binary, os.X_OK):
        parser.error("目录中没有可执行的 alice_companion")
    data.mkdir(parents=True, exist_ok=True)
    launcher = data / "device-supervisor.py"
    shutil.copyfile(Path(__file__).with_name("device-supervisor.py"), launcher)
    def quote(path):
        value = str(path)
        if "\n" in value or "\r" in value:
            parser.error("路径不能包含换行")
        for char in ["\\", '"', "`", "$"]:
            value = value.replace(char, "\\" + char)
        return '"' + value.replace("%", "%%") + '"'
    entry.parent.mkdir(parents=True, exist_ok=True)
    entry.write_text("[Desktop Entry]\nType=Application\nName=Alice\nComment=小小鲸屿\n"
                     + f"Exec=/usr/bin/python3 {quote(launcher)} {quote(binary)}\n"
                     + "Terminal=false\nStartupNotify=false\n", encoding="utf-8")
    print(f"已安装：{entry}\n下次进入图形桌面时启动 Alice。系统自动登录请在树莓派设置中开启。")
