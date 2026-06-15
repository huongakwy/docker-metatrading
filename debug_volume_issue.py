#!/usr/bin/env python3
"""
Debug volume issue - test với nhiều giá trị volume khác nhau
"""

import socket
import json
import time

def send_test_signal(volume, port=8080):
    """Gửi test signal với volume cụ thể"""
    signal = {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "volume": volume,
        "sl": 0,
        "tp": 0,
        "comment": f"TEST_VOL_{volume}",
        "magic": 99999
    }
    
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(10)
        sock.connect(("localhost", port))
        
        json_data = json.dumps(signal)
        print(f"\n{'='*60}")
        print(f"TEST: volume={volume}")
        print(f"Sending: {json_data}")
        
        sock.sendall(json_data.encode('utf-8'))
        
        # Wait for response
        response_data = b""
        sock.setblocking(False)
        timeout_time = time.time() + 10
        
        while time.time() < timeout_time:
            try:
                chunk = sock.recv(4096)
                if chunk:
                    response_data += chunk
                else:
                    break
            except:
                time.sleep(0.2)
                if response_data:
                    break
        
        sock.close()
        
        if response_data:
            response_str = response_data.decode('utf-8', errors='ignore').strip()
            print(f"Response: {response_str}")
            
            # Đợi 2 giây rồi check positions
            time.sleep(2)
            return True
        else:
            print("Empty response")
            return False
            
    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    print("="*60)
    print("DEBUG VOLUME ISSUE")
    print("="*60)
    print("\nTest các giá trị volume khác nhau:")
    print("Xem EA nhận volume bao nhiêu và đặt lệnh với lot size bao nhiêu")
    print("\nLưu ý: Sau mỗi lần test, check terminal để xem lot size thực tế")
    print("="*60)
    
    # Test với nhiều giá trị volume
    test_volumes = [0.01, 0.05, 0.1, 0.5, 1.0, 2.0]
    
    for vol in test_volumes:
        input(f"\nPress Enter to test volume={vol}...")
        send_test_signal(vol)
        input("Check terminal và nhấn Enter để tiếp tục...")
        
    print("\n" + "="*60)
    print("DONE - Bây giờ so sánh volume sent vs lot size actual trong terminal")
    print("="*60)
