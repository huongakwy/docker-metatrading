#!/usr/bin/env python3
"""Debug EA response"""
import socket
import json
import time

s = socket.socket()
s.settimeout(2)
s.connect(('127.0.0.1', 8080))

sig = json.dumps({'action': 'PING', 'symbol': 'XAUUSDm', 'volume': 0.01})
print(f"Sending: {sig}")
s.sendall((sig + '\n').encode())

data = b''
print("Waiting for responses...")
while True:
    try:
        chunk = s.recv(4096)
        if not chunk:
            print("  Connection closed")
            break
        data += chunk
        print(f"  Received {len(chunk)} bytes: {chunk[:200]}")
        
        # Check if we have valid JSON
        text = data.decode('utf-8', 'ignore')
        for line in text.strip().split('\n'):
            line = line.strip()
            if line:
                try:
                    obj = json.loads(line)
                    print(f"  Valid JSON: {obj}")
                except:
                    pass
    except socket.timeout:
        print("  Timeout")
        break

s.close()
print(f"\nTotal data: {len(data)} bytes")
