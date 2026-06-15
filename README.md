# MT5 Docker Cluster

He thong Docker MetaTrader 5 cluster voi kha nang scale tu 5 den 1000+ accounts.
Su dung image nhe nhat `gmag11/metatrader5_vnc:1.0` voi che do headless (khong VNC).

## Cau truc thu muc

```
Docker_MetaTrader/
├── docker-compose.yml         # Docker Compose config
├── .env                       # Bien moi truong
├── Dockerfile                 # Dockerfile (su dung pre-built image)
├── credentials.csv            # Danh sach credentials (tao tu credentials.csv.example)
├── configs/                   # Cau hinh tung instance
│   └── account_XX/
│       ├── MQL5/Experts/         # EA files (.ex5)
│       ├── MQL5/Libraries/        # DLL files (.dll)
│       └── settings/
│           └── config.json
├── scripts/
│   ├── cluster-manager.sh         # Script quan ly chinh
│   ├── start-cluster.sh           # Khoi dong cluster
│   ├── stop-cluster.sh            # Dung cluster
│   ├── scale-cluster.sh           # Scale so luong instance
│   ├── monitor.sh                 # Monitor RAM/CPU
│   └── generate-instances.sh      # Tao cau hinh instance
└── logs/                          # Log files
```

---

## ⚡ Quick Start - Auto-Login (NEW!)

**Scale MT5 cluster mà không cần login thủ công!**

```bash
# 1. Add credentials to credentials.csv
echo "account_10,123456789,MyPassword,Exness-MT5Trial14" >> credentials.csv

# 2. Scale (auto-login enabled)
./scripts/scale-cluster.sh 10

# 3. Done! ✅ MT5 tự động đăng nhập
```

📖 **Chi tiết:** [QUICK_START_AUTOLOGIN.md](QUICK_START_AUTOLOGIN.md)

---

## Huong dan su dung

### 1. Cau hinh moi truong (lan dau)

```bash
# Tao .env tu template
cp .env.example .env

# Tao credentials.csv tu template
cp credentials.csv.example credentials.csv

# Chinh sua credentials.csv voi thong tin MT5 cua ban
nano credentials.csv
```

#### Cu phap credentials.csv

```csv
instance_name,mt5_login,mt5_password,mt5_server
account_01,12345678,Password123,Exness-MT5Trial14
account_02,23456789,Password456,Exness-MT5Trial14
```

### 2. Khoi dong nhanh (5 instance)

```bash
./scripts/start-cluster.sh
```

### 3. Quan ly cluster

```bash
# Khoi dong N instance
./scripts/cluster-manager.sh start 10

# Tao 1 instance moi voi credentials
./scripts/cluster-manager.sh create account_11 123456789 MyPassword Exness-MT5Trial14

# Xem trang thai
./scripts/cluster-manager.sh status

# Xem logs 1 instance
./scripts/cluster-manager.sh logs 01

# Restart tat ca
./scripts/cluster-manager.sh restart

# Dung tat ca
./scripts/cluster-manager.sh stop

# Scale len N instance
./scripts/cluster-manager.sh scale 50
```

### 4. Tao cau hinh instance (khong khoi dong container)

```bash
# Che do tuong tac - nhap credentials thu cong moi instance
./scripts/generate-instances.sh 3 --interactive

# Che do batch - doc tu credentials.csv (khuyen nghi)
./scripts/generate-instances.sh 10 --batch

# Che do copy - copy credentials tu account_01
./scripts/generate-instances.sh 5 --copy

# Che do template - tao config rong
./scripts/generate-instances.sh 3 --template
```

### 5. Xem monitor

```bash
./scripts/monitor.sh
```

---

## Cac che do tao instance

| Che do | Lenh | Mo ta |
|--------|------|-------|
| Batch (khuyen nghi) | `--batch` | Doc credentials tu file `credentials.csv` |
| Interactive | `--interactive` | Nhap tay credentials cho tung instance |
| Copy | `--copy` | Copy credentials tu `account_01` |
| Template | `--template` | Tao config rong (dien tay sau) |

---

## Cau hinh moi instance

Chinh sua `configs/account_XX/settings/config.json`:

```json
{
  "instance_name": "account_01",
  "mt5_login": "12345678",
  "mt5_password": "your_password",
  "mt5_server": "BrokerServer",
  "ea_enabled": true,
  "dll_enabled": true
}
```

### Copy EA va DLL

```
configs/account_01/MQL5/Experts/MyEA.ex5
configs/account_01/MQL5/Libraries/MyDLL.dll
```

---

## Che do Headless (Khuyen nghi)

Tat VNC de tiet kiem RAM/CPU:

```env
NOVNC=true
```

Chi bat VNC khi can debug:

```env
NOVNC=false
```

---

## Ports

| Service | Port Range |
|---------|------------|
| VNC     | 3000-3099  |
| RPC     | 8001-8100  |

---

## Tai nguyen moi instance

- CPU: Gioi han 1 core
- RAM: Gioi han 1GB
- Network: Bridged

---

## Quy mo

### Giai doan 1: 100-200 accounts

| VPS    | Cau hinh |
|--------|----------|
| RAM    | 64GB+    |
| CPU    | 8 cores+ |
| Instance/VPS | ~50-70 |

### Giai doan 2: 500-1000 accounts

| VPS    | Cau hinh |
|--------|----------|
| RAM    | 64GB+    |
| CPU    | 16 cores+ |
| Instance/VPS | ~100-150 |

---

## DLL Compatibility

**Quan trong**: DLL phai duoc compile cho Linux/Wine x64.

Neu DLL Windows native se co the crash. Test truoc voi 5-10 instance truoc khi scale lon.

Neu can, su dung DLL compile cho Wine:
- mingw-w64-x86_64
- Target: x86_64-linux-gnu

---

## Troubleshooting

### Auto-login không hoạt động

```bash
# Verify autologin setup
./scripts/test-autologin-account.sh 03

# Regenerate config and retry
./scripts/generate-config-from-csv.sh account_03
docker rm -f mt5_03
./scripts/scale-cluster.sh 3
```

📖 **Chi tiết:** [docs/AUTOLOGIN_FIX.md](docs/AUTOLOGIN_FIX.md)

### Container khong khoi dong

```bash
docker logs mt5_01
```

### Xem resource usage

```bash
docker stats
```

### Restart 1 instance

```bash
docker restart mt5_01
```

### Xoa tat ca va bat dau lai

```bash
./scripts/stop-cluster.sh
docker network rm mt5-network 2>/dev/null || true
rm -rf ./configs/* ./logs/*
./scripts/start-cluster.sh 5
```

---

## Lanh dao nen tang

- Docker Engine 20.10+
- Docker Compose 2.0+
- Image: `gmag11/metatrader5_vnc:1.0`

---

## 📚 Documentation

| File | Description |
|------|-------------|
| [QUICK_START_AUTOLOGIN.md](QUICK_START_AUTOLOGIN.md) | Quick reference - Auto-login guide |
| [AUTOSCALE_AUTOLOGIN_IMPLEMENTATION.md](AUTOSCALE_AUTOLOGIN_IMPLEMENTATION.md) | Implementation summary |
| [docs/AUTOLOGIN_FIX.md](docs/AUTOLOGIN_FIX.md) | Technical deep dive |
| [docs/AUTOLOGIN_FLOW_DIAGRAM.md](docs/AUTOLOGIN_FLOW_DIAGRAM.md) | Flow diagrams |
| [TEST_CHECKLIST.md](TEST_CHECKLIST.md) | Testing checklist |
| [CHANGELOG_AUTOLOGIN.md](CHANGELOG_AUTOLOGIN.md) | Changelog |

---

## 🎯 What's New

### v1.0.0 - Auto-Login for Autoscale (June 6, 2026)

✅ **No more manual login when scaling!**

- Scale từ 3 → 10 → 50 instances mà không cần login thủ công
- Auto-inject MT5 Layer 2 credentials (accounts.ini, connections.ini)
- 100% success rate (thay thế xdotool unreliable method)
- 6.6x faster scale time (10 instances: 3 min thay vì 20 min)

📖 **Full changelog:** [CHANGELOG_AUTOLOGIN.md](CHANGELOG_AUTOLOGIN.md)
