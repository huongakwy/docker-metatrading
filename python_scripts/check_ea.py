#!/usr/bin/env python3
"""Fast EA status checker - ~0.23ms if running, ~500ms if stopped"""
import socket
import json
import time
import sys

def check_ea(host='localhost', port=8080, timeout=0.5):
    """Check if EA is running by sending a test command"""
    start = time.perf_counter()
    
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect((host, port))
        
        # Send a simple test command
        sig = json.dumps({
            'action': 'PING',
            'symbol': 'XAUUSDm',
            'volume': 0.01,
        })
        s.sendall((sig + '\n').encode())
        
        # Read responses (EA responds multiple times)
        data = b''
        while True:
            try:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
                
                # Check if we got valid JSON
                try:
                    lines = [l.strip() for l in data.decode('utf-8', 'ignore').strip().split('\n') if l.strip()]
                    for line in lines:
                        if line.startswith('{'):
                            json.loads(line)
                            elapsed = (time.perf_counter() - start) * 1000
                            s.close()
                            return True, elapsed
                except json.JSONDecodeError:
                    continue
                except:
                    break
            except socket.timeout:
                break
            except:
                break
        
        s.close()
        
    except Exception as e:
        pass
    
    elapsed = (time.perf_counter() - start) * 1000
    return False, elapsed

if __name__ == '__main__':
    host = sys.argv[1] if len(sys.argv) > 1 else 'localhost'
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8080
    
    running, ms = check_ea(host, port)
    
    if running:
        print(f"RUNNING ({ms:.1f}ms)")
        sys.exit(0)
    else:
        print(f"STOPPED ({ms:.1f}ms)")
        sys.exit(1)
