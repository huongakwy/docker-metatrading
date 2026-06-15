#!/usr/bin/env python3
"""
Debug volume issue - test different volume values
"""
import socket
import json
import time

def test_volume(volume, port=8080):
    """Test sending a specific volume"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(10)
        sock.connect(("localhost", port))
        
        signal = {
            "action": "SELL",
            "symbol": "XAUUSDm",
            "volume": volume,
            "sl": 0,
            "tp": 0,
            "comment": f"test_vol_{volume}",
            "magic": 12345
        }
        
        json_data = json.dumps(signal)
        print(f"\n{'='*60}")
        print(f"Testing volume: {volume}")
        print(f"Sending: {json_data}")
        
        sock.sendall(json_data.encode('utf-8'))
        
        # Wait for response
        sock.setblocking(False)
        response_data = b""
        timeout_time = time.time() + 5
        
        while time.time() < timeout_time:
            try:
                chunk = sock.recv(4096)
                if chunk:
                    response_data += chunk
                else:
                    break
            except:
                time.sleep(0.1)
        
        sock.close()
        
        if response_data:
            response_str = response_data.decode('utf-8', errors='ignore').strip()
            print(f"Response: {response_str}")
        else:
            print("No response")
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    print("="*60)
    print("Volume Debug Test")
    print("="*60)
    
    # Test different volume values
    volumes = [0.01, 0.1, 0.5, 1.0, 2.0]
    
    for vol in volumes:
        test_volume(vol)
        time.sleep(2)  # Wait between tests
    
    print("\n" + "="*60)
    print("Done. Check MT5 terminal to see actual lot sizes placed.")
    print("="*60)
