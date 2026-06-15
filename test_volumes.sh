#!/bin/bash

echo "=========================================="
echo "Testing different volume values"
echo "=========================================="

volumes=(0.01 0.1 0.5 1.0 2.0)

for vol in "${volumes[@]}"; do
    echo ""
    echo "Testing volume: $vol"
    echo "Command: python3 signalsender.py --action SELL --symbol XAUUSDm --volume $vol --magic 99999"
    echo "------------------------------------------"
    
    timeout 10 python3 signalsender.py --action SELL --symbol XAUUSDm --volume $vol --magic 99999 2>&1 | grep -E "Sending:|Received:|ticket|retcode|RESULT" || true
    
    echo ""
    echo "Sleeping 3 seconds..."
    sleep 3
done

echo ""
echo "=========================================="
echo "Done. Check MT5 terminal for actual lots"
echo "=========================================="
echo ""
echo "To check in MT5:"
echo "docker exec mt5_01 bash -c 'DISPLAY=:99 xdotool search --name MetaTrader'"
