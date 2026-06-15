#!/usr/bin/env python3
"""
Test different JSON field names and formats for volume
"""
import socket
import json
import time

def test_signal(description, signal, host="103.72.56.53", port=8080):
    """Send a test signal"""
    print(f"\n{'='*70}")
    print(f"Test: {description}")
    print(f"{'='*70}")
    print(f"Signal: {json.dumps(signal, indent=2)}")
    
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(10)
        sock.connect((host, port))
        
        json_data = json.dumps(signal)
        sock.sendall(json_data.encode('utf-8'))
        print("✅ Sent")
        
        time.sleep(2)
        
        # Try to get response
        sock.setblocking(False)
        response = b""
        for _ in range(10):
            try:
                chunk = sock.recv(4096)
                if chunk:
                    response += chunk
            except:
                time.sleep(0.1)
        
        if response:
            print(f"Response: {response.decode('utf-8', errors='ignore').strip()}")
        
        sock.close()
        print("Wait 3 seconds before next test...")
        time.sleep(3)
        
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    print("="*70)
    print("Testing Different Volume Field Names and Formats")
    print("="*70)
    print("\nTarget: Remote Windows (103.72.56.53:8080)")
    print("Check MT5 Terminal → Trade tab → Comment and Volume columns")
    print("="*70)
    
    # Test 1: Original format (volume as number)
    test_signal("1. volume as number 0.5", {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "volume": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "test1_vol_num",
        "magic": 11111
    })
    
    # Test 2: volume as string
    test_signal("2. volume as string '0.5'", {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "volume": "0.5",
        "sl": 0,
        "tp": 0,
        "comment": "test2_vol_str",
        "magic": 11112
    })
    
    # Test 3: lot instead of volume
    test_signal("3. lot (not volume)", {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "lot": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "test3_lot",
        "magic": 11113
    })
    
    # Test 4: lots instead of volume
    test_signal("4. lots (plural)", {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "lots": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "test4_lots",
        "magic": 11114
    })
    
    # Test 5: size instead of volume
    test_signal("5. size", {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "size": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "test5_size",
        "magic": 11115
    })
    
    # Test 6: Both volume and lot
    test_signal("6. Both volume AND lot", {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "volume": 0.5,
        "lot": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "test6_both",
        "magic": 11116
    })
    
    # Test 7: Uppercase VOLUME
    test_signal("7. VOLUME (uppercase)", {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "VOLUME": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "test7_upper",
        "magic": 11117
    })
    
    # Test 8: amount
    test_signal("8. amount", {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "amount": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "test8_amount",
        "magic": 11118
    })
    
    # Test 9: qty (quantity)
    test_signal("9. qty", {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "qty": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "test9_qty",
        "magic": 11119
    })
    
    # Test 10: lotsize
    test_signal("10. lotsize", {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "lotsize": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "test10_lotsize",
        "magic": 11120
    })
    
    # Test 11: volume with explicit 2 decimals
    test_signal("11. volume as '0.50' (2 decimals)", {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "volume": "0.50",
        "sl": 0,
        "tp": 0,
        "comment": "test11_050",
        "magic": 11121
    })
    
    # Test 12: Test với 1.0
    test_signal("12. volume = 1.0", {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "volume": 1.0,
        "sl": 0,
        "tp": 0,
        "comment": "test12_1lot",
        "magic": 11122
    })
    
    print("\n" + "="*70)
    print("All tests completed!")
    print("="*70)
    print("\n📋 Next steps:")
    print("1. Check Windows MT5 → Terminal → Trade tab")
    print("2. Look for orders with Comment: test1_*, test2_*, etc.")
    print("3. Check Volume column for each order")
    print("4. Find which test shows Volume = 0.5 or 1.0 (not 0.01)")
    print("5. That's the correct field name/format!")
    print("="*70)
