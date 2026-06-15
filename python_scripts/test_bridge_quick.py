import socket
import json
import time

def ping_ea(port=8080):
    """Ping EA and check if it responds"""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1)
    try:
        s.connect(("127.0.0.1", port))
        s.sendall(b'ping\n')
        resp1 = s.recv(4096)
        print(f"Response 1: {resp1}")
        
        # Second ping
        s.sendall(b'ping\n')
        resp2 = s.recv(4096)
        print(f"Response 2: {resp2}")
        
        s.close()
        
        if resp1 or resp2:
            return True
    except Exception as e:
        print(f"Error: {e}")
    return False

# Test
print("Testing EA ping...")
if ping_ea(8080):
    print("EA is RUNNING")
else:
    print("EA is STOPPED")
