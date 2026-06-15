#!/usr/bin/env python3
"""
Test response timing - read IMMEDIATELY after send
"""
import socket
import json
import time

def test_immediate_read(host="localhost", port=8080):
    """Test reading response immediately after sending"""
    print("="*60)
    print("Test 1: Read IMMEDIATELY after send")
    print("="*60)
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(15)
    sock.connect((host, port))
    print(f"✅ Connected to {host}:{port}")
    
    signal = {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "volume": 0.5,
        "lot": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "timing_test1",
        "magic": 77771
    }
    
    json_data = json.dumps(signal)
    print(f"📤 Sending: {json_data}")
    sock.sendall(json_data.encode('utf-8'))
    
    # IMMEDIATELY start reading (blocking mode)
    print("📥 Reading response (blocking, 15s timeout)...")
    try:
        response = sock.recv(8192)  # Read up to 8KB
        if response:
            print(f"✅ Received {len(response)} bytes:")
            print(response.decode('utf-8', errors='ignore'))
        else:
            print("⚠️  Empty response")
    except socket.timeout:
        print("❌ Timeout waiting for response")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    sock.close()
    print()

def test_recv_loop(host="localhost", port=8080):
    """Test with recv loop"""
    print("="*60)
    print("Test 2: Multiple recv() calls in loop")
    print("="*60)
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(15)
    sock.connect((host, port))
    print(f"✅ Connected to {host}:{port}")
    
    signal = {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "volume": 0.5,
        "lot": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "timing_test2",
        "magic": 77772
    }
    
    json_data = json.dumps(signal)
    print(f"📤 Sending: {json_data}")
    sock.sendall(json_data.encode('utf-8'))
    
    print("📥 Reading in loop...")
    all_data = b""
    try:
        for i in range(10):  # Try up to 10 times
            chunk = sock.recv(4096)
            if chunk:
                print(f"   Chunk {i+1}: {len(chunk)} bytes")
                all_data += chunk
            else:
                print(f"   Chunk {i+1}: Connection closed")
                break
            time.sleep(0.1)  # Small delay between reads
    except socket.timeout:
        print("   Timeout")
    except Exception as e:
        print(f"   Error: {e}")
    
    if all_data:
        print(f"✅ Total received: {len(all_data)} bytes")
        print(all_data.decode('utf-8', errors='ignore'))
    else:
        print("⚠️  No data received")
    
    sock.close()
    print()

def test_with_shutdown(host="localhost", port=8080):
    """Test with proper shutdown sequence"""
    print("="*60)
    print("Test 3: With socket shutdown(SHUT_WR)")
    print("="*60)
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(15)
    sock.connect((host, port))
    print(f"✅ Connected to {host}:{port}")
    
    signal = {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "volume": 0.5,
        "lot": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "timing_test3",
        "magic": 77773
    }
    
    json_data = json.dumps(signal)
    print(f"📤 Sending: {json_data}")
    sock.sendall(json_data.encode('utf-8'))
    
    # Signal that we're done sending
    print("🔒 Shutting down write side...")
    sock.shutdown(socket.SHUT_WR)
    
    print("📥 Reading response...")
    all_data = b""
    try:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            all_data += chunk
            print(f"   Received chunk: {len(chunk)} bytes")
    except Exception as e:
        print(f"   Error: {e}")
    
    if all_data:
        print(f"✅ Total: {len(all_data)} bytes")
        print(all_data.decode('utf-8', errors='ignore'))
    else:
        print("⚠️  No data")
    
    sock.close()
    print()

def test_recv_until_close(host="localhost", port=8080):
    """Test: recv until connection closes"""
    print("="*60)
    print("Test 4: recv() until connection closes")
    print("="*60)
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect((host, port))
    print(f"✅ Connected to {host}:{port}")
    
    signal = {
        "action": "SELL",
        "symbol": "XAUUSDm",
        "volume": 0.5,
        "lot": 0.5,
        "sl": 0,
        "tp": 0,
        "comment": "timing_test4",
        "magic": 77774
    }
    
    json_data = json.dumps(signal)
    print(f"📤 Sending: {json_data}")
    sock.sendall(json_data.encode('utf-8'))
    
    print("📥 Reading until connection closes (15s timeout)...")
    sock.settimeout(15)
    
    all_data = b""
    start_time = time.time()
    
    try:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                print("   Connection closed by server")
                break
            all_data += chunk
            print(f"   Received: {len(chunk)} bytes (total: {len(all_data)})")
            
            if time.time() - start_time > 15:
                print("   15s timeout reached")
                break
    except socket.timeout:
        print("   Socket timeout")
    except Exception as e:
        print(f"   Error: {e}")
    
    if all_data:
        print(f"✅ Total: {len(all_data)} bytes")
        response_str = all_data.decode('utf-8', errors='ignore')
        print("Response:")
        print(response_str)
        
        # Try to parse JSON
        lines = response_str.strip().split('\n')
        for i, line in enumerate(lines, 1):
            if line.strip():
                try:
                    parsed = json.loads(line.strip())
                    print(f"Line {i} (JSON): {json.dumps(parsed, indent=2)}")
                except:
                    print(f"Line {i} (text): {line}")
    else:
        print("⚠️  No data received")
    
    sock.close()
    print()

if __name__ == "__main__":
    print("\n" + "="*60)
    print("Response Timing Test")
    print("="*60)
    print("\nTesting localhost:8080 (Docker MT5)")
    print("="*60 + "\n")
    
    test_immediate_read()
    time.sleep(2)
    
    test_recv_loop()
    time.sleep(2)
    
    test_with_shutdown()
    time.sleep(2)
    
    test_recv_until_close()
    
    print("\n" + "="*60)
    print("All tests complete!")
    print("="*60)
    print("\nCheck which test successfully received the response")
    print("Expected: ticket number and retcode=10009")
    print("="*60)
