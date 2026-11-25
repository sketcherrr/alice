# Cardputer-Adv × Arch Linux：第一轮 SSH 测试

这一轮把 Cardputer-Adv 做成 Alice 的随身小屏客户端：设备负责画面和按键，Arch 主机运行已有 Rust 核心与 SQLite 存档。两端通过 SSH exec 通道交换 JSON 行，不需要 Flutter、浏览器、HTTP 服务或 OpenAI Key。

固件是本仓库的 PlatformIO 工程，不必先安装第三方 SSH 终端固件。它显示一个轻量的鲸鱼帽小头像，有呼吸、眨眼、睡眠、点心和泡泡效果；不是桌面版的完整角色精灵动画。首轮界面使用英文，避免小屏中文字库和输入法成为联调阻碍。

## 先把网络接对

**Cardputer-Adv 的 ESP32-S3 只支持 2.4 GHz Wi-Fi，无法连接仅有 5 GHz 的热点。** Arch 主机可以接有线或 5 GHz，只要两端在互通的局域网。建议使用路由器的 2.4 GHz WPA2-Personal 网络；关闭该网络的访客/AP 隔离。不要给路由器增加公网端口转发。

此前树莓派 5 的 5 GHz 计划仍然成立，这个限制属于 Cardputer 的无线硬件。参考 [M5Stack Cardputer-Adv 规格](https://docs.m5stack.com/en/core/Cardputer-Adv) 和 [Espressif ESP32-S3 数据手册](https://documentation.espressif.com/esp32-s3_datasheet_en.pdf)。

## 1. 在 Arch 主机编译并先跑一遍

以下命令均从项目根目录执行。Arch 用完整升级安装依赖，避免部分升级：

```bash
sudo pacman -Syu --needed base-devel rust sqlite openssh python python-pip
bash scripts/build-cardputer-host.sh
python scripts/test-cardputer.py
python scripts/cardputer-console.py
```

如果已有 rustup 管理的 Rust，保留它，安装依赖时省略 `rust`。本地控制台输入 `p1` 回车选性格，然后 `f`、`b`、`s`、`w`、`g`、`1`；`q` 退出。再次启动可验证存档恢复。每种普通互动有 30 秒冷却；睡着后需要先 `w` 唤醒。

本地控制台默认存档为 `~/.local/share/alice-cardputer/companion.sqlite3`，与桌面版分开。可加 `--data-dir /某个测试目录`。真正部署后的设备存档在下面的专用账号目录，两者也分开。

## 2. 安装专用 SSH 测试入口

查看主机地址：

```bash
ip -4 -brief address
```

找到连接家庭路由器的网卡地址，例如 `192.168.1.100`。以下示例地址必须替换为你的实际地址，建议在路由器上做 DHCP 地址保留：

```bash
sudo bash scripts/install-cardputer-host.sh 192.168.1.100
sudo passwd alice-card
sudo systemctl enable --now alice-card-sshd.service
sudo systemctl status alice-card-sshd.service
```

安装脚本会创建 `alice-card` 普通权限专用账号、独立 Ed25519 主机密钥、端口 **2222** 的独立 sshd 服务，并且只监听你指定的局域网地址。它不改 `/etc/ssh/sshd_config`，不启动原有 SSH 服务。账号的登录程序和 `ForceCommand` 都指向 Alice 接口；账号没有通用 shell，禁用转发和 PTY。设备使用刚设置的**专用账号密码**。

安装结束会输出 `SHA256:...` 主机指纹。把这整段复制到设备配置的 `host_fingerprint`，不要复制前面的 `256` 或后面的账号注释。重新查看：

```bash
sudo ssh-keygen -lf /etc/ssh/alice_card_ed25519_key.pub -E sha256
```

先用电脑验证真实 SSH 链路：

```bash
python scripts/cardputer-console.py --host 192.168.1.100
```

首次 SSH 连接时核对显示的指纹与安装输出一致，再接受并输入 `alice-card` 密码。不要用 `StrictHostKeyChecking=no`。如果运行了防火墙，只为家庭局域网放行 TCP 2222；脚本不会替你修改防火墙。

部署后存档：`/var/lib/alice-card/save/companion.sqlite3`。SQLite 每次动作提交事务，SSH 退出不会清空存档。不要用主机管理员账号给小设备登录。

## 3. PlatformIO 编译和上传

已有 VS Code PlatformIO 的话，在它的 Terminal 执行 `pio` 命令即可。也可以建立独立 Python 环境：

```bash
python -m venv .venv
.venv/bin/pip install platformio==6.1.19
.venv/bin/pio run -d firmware/cardputer
.venv/bin/pio device list
```

首次会下载 ESP32 工具链、Arduino 框架、M5Cardputer、M5Unified、M5GFX、ArduinoJson 和 **LibSSH-ESP32**；SSH 库也是必要依赖。需要访问 PlatformIO 包仓库。工程按 StampS3 / ESP32-S3、8 MB Flash、无 PSRAM 配置，并使用支持 Adv 键盘的 M5Cardputer 1.1.1。

使用 USB 数据线连接。若无法进入上传模式，按 [M5Stack 官方方法](https://docs.m5stack.com/en/core/Cardputer-Adv)：侧面电源拨到 OFF，按住 G0，再插入 USB，设备上电后释放 G0。串口以 `pio device list` 的实际结果为准：

```bash
.venv/bin/pio run -d firmware/cardputer -t upload --upload-port /dev/ttyACM0
```

上传后重新上电，屏幕应出现 `USB setup`。如果仍在下载模式，断开 USB、释放 G0 后重新连接，电源拨到 ON。串口无访问权限时按 [PlatformIO udev 指南](https://docs.platformio.org/en/latest/core/installation/udev-rules.html) 设置权限，不要用 sudo 运行整个 PlatformIO 构建。

## 4. 通过 USB 填写连接信息

不用 microSD，也不用把密码编译进固件：

```bash
cp firmware/cardputer/alice.example.json firmware/cardputer/alice.local.json
chmod 600 firmware/cardputer/alice.local.json
```

用编辑器填写 `alice.local.json`：

| 字段 | 填什么 |
| --- | --- |
| `wifi_ssid` | 可用的 2.4 GHz Wi-Fi 名称 |
| `wifi_password` | 该 Wi-Fi 的密码 |
| `ssh_host` | Arch 主机局域网 IPv4 地址 |
| `ssh_port` | `2222` |
| `ssh_user` | `alice-card` |
| `ssh_password` | `sudo passwd alice-card` 设置的密码 |
| `host_fingerprint` | 主机输出的完整 `SHA256:...` |

关闭 PlatformIO 串口监视器，再发送：

```bash
.venv/bin/python scripts/configure-cardputer.py \
  --port /dev/ttyACM0 \
  --config firmware/cardputer/alice.local.json
```

工具只发送配置，不打印密码。设备存入 NVS 后自动重启并连接。`*.local.json`、`.venv/` 和 `.pio/` 已加入忽略规则。原型的 NVS **未加密**，配置文件也包含明文密码，因此请用专用账号，不要复用主账号密码；固件镜像不含你的凭据。长按 G0 约 1.5 秒重新进入配置模式。擦除整个 Flash 会清掉设备配置，主机宠物存档不受影响。

设备在发送账号密码前校验主机公钥指纹。指纹不同或认证失败时停止自动重试；修改配置或重启后重试。换主机/重新生成主机密钥后，应在可信的主机控制台取得新指纹再配置，不能直接忽略提示。

## 5. 上机验收

连接成功后右上角显示 `SSH OK`，首次按 `1`、`2` 或 `3` 选择性格：温柔但有主见、聪明略带俏皮、慢热细腻克制。输入是单键，不需要回车。

| 按键 | 功能 |
| --- | --- |
| F / B | 喂食 / 洗澡 |
| S / W | 睡觉 / 唤醒 |
| H / T | 摸头 / 喝茶 |
| G，随后 1 / 2 / 3 | 找珍珠 |
| P，随后 1 / 2 / 3 | 切换性格，保留存档 |
| R | 重新读取主机状态 |
| 长按 G0 | 重新配置 Wi-Fi / SSH |

建议按这个顺序测试：

1. 选择性格，按 F、B、H，看饱腹、清洁和心情变化；连续按 H 应有冷却提示。
2. 按 S 进入睡眠，喂食应被拒绝；按 W 恢复。睡眠恢复能量按经过的真实时间结算。
3. G 开局，1/2/3 选贝壳。再开一局需等 30 秒。
4. 设备断电再开，性格、睡眠和养成值应恢复。
5. 暂停 `sudo systemctl stop alice-card-sshd`，设备应显示断线，按键不继续改状态。再 `sudo systemctl start alice-card-sshd`，等它重连。
6. 如果在按键发送时断线，操作可能已提交。客户端不会自动重发，重连后以主机状态为准。

公网断开、局域网和主机仍在时，以上互动继续可用。**离开 Wi-Fi 或主机关闭时，这版 Cardputer 只能显示最后收到的状态，没有独立养成存档或离线小游戏。** 完全独立的本地游玩、中文聊天、OpenAI 函数调用、语音/音乐、蓝牙和 IMU 摸头是下一轮工作；SSH 也不会自动把主机音频传到设备扬声器。

## 排错与停用

```bash
sudo journalctl -u alice-card-sshd.service -n 60 --no-pager
sudo ss -ltnp 'sport = :2222'
sudo /usr/bin/sshd -t -f /etc/ssh/sshd_config_alice_card
```

- Wi-Fi 一直等待：检查 2.4 GHz、密码和路由器访客隔离。第一轮优先用 WPA2-Personal；企业认证、网页登录热点不在此配置范围。
- SSH unavailable：确认实际主机地址、2222 端口、服务和防火墙；DHCP 地址改变后重新运行安装脚本并重启该服务，更新设备配置。
- Host key mismatch：核对独立服务的 Ed25519 指纹；不是系统原有 sshd 的另一把密钥。
- SSH login failed：核对专用账号密码，查看 PAM/账号日志；不要降低全局加密算法要求。
- No valid reply：确认独立服务使用仓库提供的登录程序，不向 stdout 写欢迎横幅；检查主机存档权限。
- 重新构建更新主机：再次运行构建和安装脚本，再 `sudo systemctl restart alice-card-sshd`；已有存档与主机密钥保留。
- 停用测试入口：`sudo systemctl disable --now alice-card-sshd.service`。如还需禁用专用账号密码，执行 `sudo passwd -l alice-card`。不删除存档。

## 协议与检查

请求与响应均为单行 UTF-8 JSON，结尾 `\n`，协议版本 `v:1`，请求 `id` 为无符号 32 位整数。SSH 不申请 PTY，只请求固定的 `alice-card-v1` exec 通道；服务器固定执行桥接程序。

```json
{"v":1,"id":1,"op":"snapshot"}
{"v":1,"id":2,"op":"persona","choice":1}
{"v":1,"id":3,"op":"action","action":"feed"}
{"v":1,"id":4,"op":"action","action":"guess","guess":0}
```

响应含 `ok`、`message` 和精简 `state`；错误含稳定的英文 `code`。不下发聊天历史、长期记忆内容或藏珍珠答案；错误动作不提交。单请求最多 1024 字节，设备单响应最多 1024 字节，不支持批量指令、shell 命令或任意文件操作。设备一次只发一个请求，15 秒读取状态保活；超时后关闭通道，重新连接读取状态，不重放未知结果的动作。

```bash
cargo test --locked
bash scripts/build-cardputer-host.sh
python scripts/test-cardputer.py
pio run -d firmware/cardputer
```

GitHub Actions 的 `Cardputer SSH prototype` 工作流检查主机测试和固件交叉编译。交叉编译通过也不能代替真机上的内存、无线、按键与 SSH 联调。测试结果会随本轮完成情况更新。

依赖与配置参考：[M5Cardputer](https://github.com/m5stack/M5Cardputer)、[LibSSH-ESP32](https://github.com/ewpa/LibSSH-ESP32)、[PlatformIO StampS3](https://docs.platformio.org/en/stable/boards/espressif32/m5stack-stamps3.html)、[OpenSSH sshd_config](https://man.openbsd.org/sshd_config)。固件链接 SSH 库时需遵守其 LGPL 等上游许可；仓库保留源码与构建配置，分发固件时应一起提供对应源码和许可材料。
