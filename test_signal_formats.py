#!/usr/bin/env python3
"""
Test different signal formats to find the correct one for TradingBridge DLL
"""

import socket
import json
import time

def test_format(name, host, port, message):
    """Test one message format"""
    print(f"\n{'='*60}")
    print(f"Testing: {name}")
    print(f"{'='*60}")
    
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect((host, port))
        print(f"✅ Connected to {host}:{port}")
        
        # Send message
        if isinstance(message, dict):
            data = json.dumps(message).encode('utf-8')
            print(f"📤 Sending JSON: {json.dumps(message)}")
        elif isinstance(message, str):
            data = message.encode('utf-8')
            print(f"📤 Sending String: {message}")
        elif isinstance(message, bytes):
            data = message
            print(f"📤 Sending Bytes: {message}")
        else:
            data = str(message).encode('utf-8')
            print(f"📤 Sending: {message}")
        
        sock.sendall(data)
        
        # Try to receive
        sock.settimeout(3)
        try:
            response = sock.recv(4096)
            if response:
                print(f"📥 Response ({len(response)} bytes): {response}")
                try:
                    parsed = json.loads(response.decode('utf-8'))
                    print(f"✅ Valid JSON response:")
                    print(json.dumps(parsed, indent=2))
                except:
                    print(f"📋 Text response: {response.decode('utf-8', errors='ignore')}")
            else:
                print("⚠️  Empty response")
        except socket.timeout:
            print("⚠️  No response (timeout)")
        
        sock.close()
        
    except Exception as e:
        print(f"❌ Error: {e}")

def main():
    HOST = "localhost"
    PORT = 8080
    
    print("="*60)
    print("Testing TradingBridge Signal Formats")
    print("="*60)
    
    # Test 1: Simple PING
    test_format("Simple PING", HOST, PORT, {"action": "PING"})
    time.sleep(1)
    
    # Test 2: Command-style
    test_format("Command Style", HOST, PORT, {"command": "ping"})
    time.sleep(1)
    
    # Test 3: Type-style
    test_format("Type Style", HOST, PORT, {"type": "ping"})
    time.sleep(1)
    
    # Test 4: BUY order - action/command
    test_format("BUY Order (action/command)", HOST, PORT, {
        "action": "TRADE",
        "command": "BUY",
        "symbol": "XAUUSD",
        "volume": 0.01,
        "sl": 0,
        "tp": 0
    })
    time.sleep(1)
    
    # Test 5: BUY order - simple
    test_format("BUY Order (simple)", HOST, PORT, {
        "action": "BUY",
        "symbol": "XAUUSD",
        "volume": 0.01
    })
    time.sleep(1)
    
    # Test 6: With newline
    test_format("JSON with newline", HOST, PORT, '{"action":"PING"}\n')
    time.sleep(1)
    
    # Test 7: With null terminator
    test_format("JSON with null", HOST, PORT, b'{"action":"PING"}\x00')
    time.sleep(1)
    
    # Test 8: Length-prefixed (4 bytes big-endian)
    import struct
    json_str = json.dumps({"action": "PING"})
    length = struct.pack('!I', len(json_str))
    test_format("Length-prefixed JSON", HOST, PORT, length + json_str.encode())
    time.sleep(1)
    
    # Test 9: GET_INFO
    test_format("Get Info", HOST, PORT, {
        "action": "GET_INFO",
        "type": "ACCOUNT"
    })
    time.sleep(1)
    
    # Test 10: STATUS
    test_format("Status Check", HOST, PORT, {"action": "STATUS"})
    time.sleep(1)
    
    # Test 11: Plain text
    test_format("Plain text PING", HOST, PORT, "PING")
    time.sleep(1)
    
    # Test 12: Trading format variations
    test_format("Trade format v1", HOST, PORT, {
        "cmd": "TRADE",
        "order_type": "BUY",
        "symbol": "XAUUSD",
        "lots": 0.01
    })
    time.sleep(1)
    
    test_format("Trade format v2", HOST, PORT, {
        "type": "ORDER",
        "side": "BUY",
        "symbol": "XAUUSD",
        "volume": 0.01
    })
    time.sleep(1)
    
    test_format("Trade format v3", HOST, PORT, {
        "request": "TRADE",
        "action": "BUY",
        "symbol": "XAUUSD",
        "volume": 0.01,
        "sl": 0,
        "tp": 0,
        "deviation": 10,
        "magic": 0,
        "comment": "test"
    })
    
    print("\n" + "="*60)
    print("Testing Complete")
    print("="*60)

if __name__ == "__main__":
    main()
