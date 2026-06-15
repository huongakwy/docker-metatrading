#!/bin/bash
# ============================================================================
# MT5 EA Auto-Attach - Copy AutoTrading profile to Default
# ============================================================================

CONTAINER="${1:-mt5_01}"
MT5_BASE="/config/.wine/drive_c/Program Files/MetaTrader 5"
PROFILES="$MT5_BASE/MQL5/Profiles/Charts"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   MT5 EA Auto-Attach${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

# ─── Step 1: Stop MT5 ───────────────────────────────────────────────────
echo -e "${YELLOW}[1]${NC} Stopping MT5..."
docker exec "$CONTAINER" pkill -9 -f terminal64.exe 2>/dev/null || true
sleep 2
echo -e "${GREEN}✓${NC} Stopped"
echo ""

# ─── Step 2: Copy AutoTrading profile → Default ─────────────────────────
echo -e "${YELLOW}[2]${NC} Loading AutoTrading profile..."
docker exec "$CONTAINER" python3 -c "
import shutil, os

src = '$PROFILES/AutoTrading/chart01.chr'
dst = '$PROFILES/Default/chart01.chr'

if not os.path.exists(src):
    print('ERROR: AutoTrading profile not found:', src)
    exit(1)

os.makedirs(os.path.dirname(dst), exist_ok=True)
shutil.copy2(src, dst)
print('OK - AutoTrading profile copied to Default')
"
echo ""

# ─── Step 3: Start MT5 ──────────────────────────────────────────────────
echo -e "${YELLOW}[3]${NC} Starting MT5..."
docker exec -d -u abc "$CONTAINER" bash -c \
    "DISPLAY=:1 wine '$MT5_BASE/terminal64.exe' &" 2>/dev/null

for i in {1..30}; do
    docker exec "$CONTAINER" pgrep -f terminal64.exe >/dev/null 2>&1 && break
    sleep 1
done
echo -e "${GREEN}✓${NC} MT5 started"
echo ""

# ─── Done ───────────────────────────────────────────────────────────────
echo -e "${GREEN}✓${NC} Done - check EA on VNC: http://localhost:3000"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo "Container: $CONTAINER | VNC: http://localhost:3000"
echo ""