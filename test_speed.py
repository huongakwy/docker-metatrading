#!/usr/bin/env python3
"""Test response speed after fix"""
import socket
import json
import time

def send_fast(host='localhost', port=8080):
    """Send request and measure round-trip time"""
    s = socket.socket()
    s.settimeout(5)
    s.connect((host, port))
    
    sig = json.dumps({
        'action': 'SELL',
        'symbol': 'XAUUSDm',
        'volume': 0.5,
        'lot': 0.5,
        'sl': 0,
        'tp': 0,
        'comment': 'speed_test',
        'magic': 88800 + int(time.time() % 100)
    })
    
    t = time.perf_counter()
    s.sendall((sig + '\n').encode())  # Add newline!
    
    data = b''
    try:
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
            
            # Try to parse JSON - if valid, exit immediately
            try:
                lines = [l.strip() for l in data.decode('utf-8','ignore').strip().split('\n') if l.strip()]
                if lines:
                    json.loads(lines[-1])
                    break  # Got valid JSON, exit!
            except:
                pass
    except socket.timeout:
        pass
    
    elapsed = (time.perf_counter() - t) * 1000
    response_text = data.decode("utf-8", "ignore").strip()
    
    s.close()
    return elapsed, response_text

print("="*70)
print("Speed Test - Measuring Round-Trip Time")
print("="*70)
print()

times = []
for i in range(10):
    elapsed, response = send_fast()
    times.append(elapsed)
    
    # Parse last line for ticket info
    lines = [l.strip() for l in response.split('\n') if l.strip()]
    if lines:
        try:
            result = json.loads(lines[-1])
            ticket = result.get('ticket', '?')
            retcode = result.get('retcode', '?')
            print(f"Request {i+1:2d}: {elapsed:7.2f}ms | ticket={ticket} retcode={retcode}")
        except:
            print(f"Request {i+1:2d}: {elapsed:7.2f}ms | {response[:50]}...")
    else:
        print(f"Request {i+1:2d}: {elapsed:7.2f}ms | (no response)")

print()
print("="*70)
print("Statistics:")
print(f"  Min:     {min(times):7.2f}ms")
print(f"  Max:     {max(times):7.2f}ms")
print(f"  Average: {sum(times)/len(times):7.2f}ms")
print("="*70)
print()
if sum(times)/len(times) < 100:
    print("✅ EXCELLENT! Response time < 100ms")
elif sum(times)/len(times) < 1000:
    print("✅ GOOD! Response time < 1s")
else:
    print("⚠️  SLOW - response time > 1s")
print("="*70)
