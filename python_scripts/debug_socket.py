#!/usr/bin/env python3
import socket
import time

# Test socket connection
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(5)

print("Connecting...")
sock.connect(('localhost', 8080))
print("Connected!")

message = '{"action":"SELL","symbol":"XAUUSDm","volume":0.01}'
print(f"Sending: {message}")
sock.sendall(message.encode())

print("Waiting for response...")
sock.settimeout(3)

try:
    data = sock.recv(4096)
    print(f"Received: {data}")
except socket.timeout:
    print("Timeout - no data received")
except Exception as e:
    print(f"Error: {e}")

sock.close()
