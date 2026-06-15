#!/usr/bin/env python3
"""Test sending to remote Windows MT5"""
import socket
import json
import time

HOST = "103.72.56.53"
PORT = 8080

print(f"Connecting to {HOST}:{PORT}...")

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect((HOST, PORT))
    print("✅ Connected!")
    
    # Test 1: PING
    print("\n" + "="*60)
    print("Test 1: PING")
    print("="*60)
    signal = {"action": "PING"}
    json_data = json.dumps(signal)
    print(f"Sending: {json_data}")
    sock.sendall(json_data.encode('utf-8'))
    time.sleep(1)
    
    # Try to read response
    sock.setblocking(False)
    response = b""
    for i in range(10):
        try:
            chunk = sock.recv(4096)
            if chunk:
                response += chunk
                print(f"Received chunk {i+1}: {len(chunk)} bytes")
        except BlockingIOError:
            time.sleep(0.2)
    
    if response:
        print(f"Response: {response.decode('utf-8', errors='ignore')}")
    else:
        print("No response to PING")
    
    sock.close()
    
    # Test 2: SELL with volume 0.5
    print("\n" + "="*60)
    print("Test 2: SELL volume=0.5")
    print("="*60)
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect((HOST, PORT))
    
    signal = {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "volume": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "remote_test",
        "magic": 12345
    }
    json_data = json.dumps(signal)
    print(f"Sending: {json_data}")
    sock.sendall(json_data.encode('utf-8'))
    
    time.sleep(2)
    
    sock.setblocking(False)
    response = b""
    for i in range(15):
        try:
            chunk = sock.recv(4096)
            if chunk:
                response += chunk
                print(f"Received chunk {i+1}: {len(chunk)} bytes")
        except BlockingIOError:
            time.sleep(0.2)
    
    if response:
        response_str = response.decode('utf-8', errors='ignore')
        print(f"Response: {response_str}")
        
        # Try to parse JSON
        lines = [l.strip() for l in response_str.split('\n') if l.strip()]
        for line in lines:
            try:
                parsed = json.loads(line)
                print(f"Parsed JSON: {json.dumps(parsed, indent=2)}")
            except:
                print(f"Non-JSON line: {line}")
    else:
        print("No response to SELL order")
    
    sock.close()
    
    # Test 3: SELL with volume 1.0
    print("\n" + "="*60)
    print("Test 3: SELL volume=1.0")
    print("="*60)
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect((HOST, PORT))
    
    signal = {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "volume": 1.0,
        "sl": 0,
        "tp": 0,
        "comment": "test_1lot",
        "magic": 12346
    }
    json_data = json.dumps(signal)
    print(f"Sending: {json_data}")
    sock.sendall(json_data.encode('utf-8'))
    
    time.sleep(2)
    
    sock.setblocking(False)
    response = b""
    for i in range(15):
        try:
            chunk = sock.recv(4096)
            if chunk:
                response += chunk
        except BlockingIOError:
            time.sleep(0.2)
    
    if response:
        print(f"Response: {response.decode('utf-8', errors='ignore')}")
    else:
        print("No response")
    
    sock.close()
    
    print("\n" + "="*60)
    print("Testing complete!")
    print("Check MT5 on Windows to see actual lot sizes")
    print("="*60)
    
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
