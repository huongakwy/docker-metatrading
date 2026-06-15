#!/usr/bin/env python3
"""
Simple test for MT5 Trading Bridge
One connection per request (server closes after each request)
"""

import socket
import json
import sys

def send_command(host="localhost", port=8080, data=None):
    """Send one command and get response (connection closes after)"""
    try:
        # Create new connection
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect((host, port))
        print(f"✅ Connected to {host}:{port}")
        
        # Send data
        if isinstance(data, dict):
            message = json.dumps(data).encode('utf-8')
            print(f"📤 Sending JSON: {json.dumps(data)}")
        elif isinstance(data, str):
            message = data.encode('utf-8')
            print(f"📤 Sending Text: {data}")
        elif isinstance(data, bytes):
            message = data
            print(f"📤 Sending Bytes: {data}")
        else:
            message = b""
            print(f"📤 Sending empty")
        
        sock.sendall(message)
        
        # Try to receive response
        sock.settimeout(2)
        try:
            response = sock.recv(4096)
            if response:
                print(f"📥 Received ({len(response)} bytes): {response}")
                
                # Try to parse as JSON
                try:
                    response_json = json.loads(response.decode('utf-8'))
                    print(f"📋 JSON Response: {json.dumps(response_json, indent=2)}")
                except:
                    print(f"📋 Text Response: {response.decode('utf-8', errors='ignore')}")
            else:
                print(f"⚠️  Empty response (server closed connection)")
        except socket.timeout:
            print(f"⚠️  No response received (timeout)")
        
        sock.close()
        print("🔌 Connection closed\n")
        return True
        
    except ConnectionRefusedError:
        print(f"❌ Connection refused to {host}:{port}")
        print("   Run: ./scripts/add-port-8080.sh\n")
        return False
    except Exception as e:
        print(f"❌ Error: {e}\n")
        return False

def main():
    """Run tests"""
    print("="*60)
    print("MT5 Trading Bridge - Simple Test")
    print("="*60)
    print()
    
    if len(sys.argv) > 1:
        # Custom command from command line
        try:
            cmd = json.loads(sys.argv[1])
            send_command(data=cmd)
        except:
            send_command(data=sys.argv[1])
        return
    
    # Test 1: Empty message
    print("TEST 1: Empty message")
    print("-"*60)
    send_command(data=b"")
    
    # Test 2: Invalid JSON
    print("TEST 2: Invalid JSON (should return error)")
    print("-"*60)
    send_command(data="not a json")
    
    # Test 3: Valid JSON - ping
    print("TEST 3: JSON command - ping")
    print("-"*60)
    send_command(data={"command": "ping"})
    
    # Test 4: Valid JSON - status
    print("TEST 4: JSON command - status")
    print("-"*60)
    send_command(data={"command": "status"})
    
    # Test 5: Valid JSON - get account info
    print("TEST 5: JSON command - get_account_info")
    print("-"*60)
    send_command(data={"command": "get_account_info"})
    
    # Test 6: Valid JSON - action format
    print("TEST 6: JSON with 'action' key")
    print("-"*60)
    send_command(data={"action": "ping"})
    
    # Test 7: Valid JSON - type format
    print("TEST 7: JSON with 'type' key")
    print("-"*60)
    send_command(data={"type": "status"})
    
    # Test 8: Plain text
    print("TEST 8: Plain text - PING")
    print("-"*60)
    send_command(data="PING")
    
    # Test 9: HTTP-style request
    print("TEST 9: HTTP-style GET request")
    print("-"*60)
    send_command(data="GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
    
    # Test 10: Different ports
    print("TEST 10: Try port 8081 (instance 02)")
    print("-"*60)
    send_command(port=8081, data={"command": "ping"})
    
    print("="*60)
    print("Usage:")
    print('  python3 simple_test.py \'{"command":"ping"}\'')
    print("  python3 simple_test.py 'PING'")
    print("="*60)

if __name__ == "__main__":
    main()
