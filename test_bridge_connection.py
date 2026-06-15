#!/usr/bin/env python3
"""
Test script for MT5 Trading Bridge DLL/EA connection
Tests TCP socket communication on port 8080
"""

import socket
import json
import time
import sys
from typing import Optional, Dict, Any

class TradingBridgeClient:
    """Client for communicating with Trading Bridge DLL/EA"""
    
    def __init__(self, host: str = "localhost", port: int = 8080, timeout: int = 5):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.socket: Optional[socket.socket] = None
    
    def connect(self) -> bool:
        """Establish connection to Trading Bridge"""
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(self.timeout)
            self.socket.connect((self.host, self.port))
            print(f"✅ Connected to {self.host}:{self.port}")
            return True
        except ConnectionRefusedError:
            print(f"❌ Connection refused to {self.host}:{self.port}")
            print("   Make sure:")
            print("   1. Container is running: docker ps | grep mt5")
            print("   2. Port is mapped: docker port mt5_01")
            print("   3. Run: ./scripts/add-port-8080.sh")
            return False
        except socket.timeout:
            print(f"❌ Connection timeout to {self.host}:{self.port}")
            return False
        except Exception as e:
            print(f"❌ Connection error: {e}")
            return False
    
    def send_raw(self, data: bytes) -> Optional[bytes]:
        """Send raw bytes and receive response"""
        if not self.socket:
            print("❌ Not connected")
            return None
        
        try:
            self.socket.sendall(data)
            response = self.socket.recv(4096)
            return response
        except socket.timeout:
            print("❌ Receive timeout")
            return None
        except Exception as e:
            print(f"❌ Send/receive error: {e}")
            return None
    
    def send_json(self, data: Dict[Any, Any]) -> Optional[Dict[Any, Any]]:
        """Send JSON command and receive JSON response"""
        if not self.socket:
            print("❌ Not connected")
            return None
        
        try:
            json_str = json.dumps(data)
            print(f"📤 Sending: {json_str}")
            
            # Send JSON
            self.socket.sendall(json_str.encode('utf-8'))
            
            # Receive response
            response_data = self.socket.recv(4096)
            
            if not response_data:
                print("❌ Empty response")
                return None
            
            print(f"📥 Received: {response_data.decode('utf-8', errors='ignore')}")
            
            # Try to parse as JSON
            try:
                response_json = json.loads(response_data.decode('utf-8'))
                return response_json
            except json.JSONDecodeError:
                print("⚠️  Response is not valid JSON")
                return {"raw": response_data.decode('utf-8', errors='ignore')}
                
        except socket.timeout:
            print("❌ Receive timeout")
            return None
        except Exception as e:
            print(f"❌ Error: {e}")
            return None
    
    def send_text(self, text: str) -> Optional[str]:
        """Send plain text and receive response"""
        if not self.socket:
            print("❌ Not connected")
            return None
        
        try:
            print(f"📤 Sending: {text}")
            self.socket.sendall(text.encode('utf-8'))
            response = self.socket.recv(4096)
            response_text = response.decode('utf-8', errors='ignore')
            print(f"📥 Received: {response_text}")
            return response_text
        except Exception as e:
            print(f"❌ Error: {e}")
            return None
    
    def close(self):
        """Close connection"""
        if self.socket:
            self.socket.close()
            print("🔌 Connection closed")

def test_basic_connection():
    """Test 1: Basic connection test"""
    print("\n" + "="*60)
    print("TEST 1: Basic Connection")
    print("="*60)
    
    client = TradingBridgeClient()
    if client.connect():
        print("✅ Connection successful")
        client.close()
        return True
    return False

def test_json_commands():
    """Test 2: Send various JSON commands"""
    print("\n" + "="*60)
    print("TEST 2: JSON Commands")
    print("="*60)
    
    client = TradingBridgeClient()
    if not client.connect():
        return False
    
    test_commands = [
        {"command": "ping"},
        {"command": "status"},
        {"command": "get_account_info"},
        {"command": "get_positions"},
        {"command": "get_balance"},
        {"action": "ping"},
        {"type": "status"},
    ]
    
    for cmd in test_commands:
        print(f"\n--- Testing command: {cmd} ---")
        response = client.send_json(cmd)
        if response:
            print(f"✅ Response: {json.dumps(response, indent=2)}")
        else:
            print("❌ No response or error")
        time.sleep(0.5)
    
    client.close()
    return True

def test_text_commands():
    """Test 3: Send plain text"""
    print("\n" + "="*60)
    print("TEST 3: Plain Text Commands")
    print("="*60)
    
    client = TradingBridgeClient()
    if not client.connect():
        return False
    
    test_texts = [
        "PING",
        "STATUS",
        "HELLO",
        "ping",
        "status",
    ]
    
    for text in test_texts:
        print(f"\n--- Testing text: {text} ---")
        response = client.send_text(text)
        if response:
            print(f"✅ Response received")
        else:
            print("❌ No response or error")
        time.sleep(0.5)
    
    client.close()
    return True

def test_raw_bytes():
    """Test 4: Send raw bytes"""
    print("\n" + "="*60)
    print("TEST 4: Raw Bytes")
    print("="*60)
    
    client = TradingBridgeClient()
    if not client.connect():
        return False
    
    # Send empty message
    print("\n--- Sending empty bytes ---")
    response = client.send_raw(b"")
    if response:
        print(f"✅ Response: {response}")
    
    # Send newline
    print("\n--- Sending newline ---")
    response = client.send_raw(b"\n")
    if response:
        print(f"✅ Response: {response}")
    
    # Send JSON with newline
    print("\n--- Sending JSON with newline ---")
    response = client.send_raw(b'{"command":"test"}\n')
    if response:
        print(f"✅ Response: {response}")
    
    client.close()
    return True

def test_multiple_instances():
    """Test 5: Test multiple instances (8080, 8081, 8082)"""
    print("\n" + "="*60)
    print("TEST 5: Multiple Instances")
    print("="*60)
    
    for port in [8080, 8081, 8082]:
        print(f"\n--- Testing port {port} ---")
        client = TradingBridgeClient(port=port)
        if client.connect():
            response = client.send_json({"command": "ping"})
            if response:
                print(f"✅ Instance on port {port} responding")
            client.close()
        else:
            print(f"⚠️  No instance on port {port}")

def test_http_style():
    """Test 6: HTTP-style request"""
    print("\n" + "="*60)
    print("TEST 6: HTTP-Style Request")
    print("="*60)
    
    client = TradingBridgeClient()
    if not client.connect():
        return False
    
    http_request = b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    print(f"📤 Sending HTTP request")
    response = client.send_raw(http_request)
    if response:
        print(f"📥 Response:\n{response.decode('utf-8', errors='ignore')}")
    
    client.close()
    return True

def interactive_mode():
    """Interactive mode: manually send commands"""
    print("\n" + "="*60)
    print("INTERACTIVE MODE")
    print("="*60)
    print("Type JSON commands or 'quit' to exit")
    print("Examples:")
    print('  {"command": "ping"}')
    print('  {"command": "status"}')
    print("="*60 + "\n")
    
    client = TradingBridgeClient()
    if not client.connect():
        return
    
    try:
        while True:
            user_input = input("\n> ").strip()
            
            if user_input.lower() in ['quit', 'exit', 'q']:
                break
            
            if not user_input:
                continue
            
            # Try to parse as JSON
            try:
                cmd = json.loads(user_input)
                response = client.send_json(cmd)
            except json.JSONDecodeError:
                # Send as text
                response = client.send_text(user_input)
            
            if response:
                print(f"✅ Success")
            else:
                print(f"❌ Failed")
    
    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted by user")
    
    client.close()

def main():
    """Main test runner"""
    print("="*60)
    print("MT5 Trading Bridge Connection Test")
    print("="*60)
    
    if len(sys.argv) > 1:
        if sys.argv[1] == "interactive" or sys.argv[1] == "-i":
            interactive_mode()
            return
    
    # Run all tests
    tests = [
        test_basic_connection,
        test_json_commands,
        test_text_commands,
        test_raw_bytes,
        test_http_style,
        test_multiple_instances,
    ]
    
    passed = 0
    failed = 0
    
    for test in tests:
        try:
            if test():
                passed += 1
            else:
                failed += 1
        except Exception as e:
            print(f"❌ Test failed with exception: {e}")
            failed += 1
        time.sleep(1)
    
    # Summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)
    print(f"✅ Passed: {passed}")
    print(f"❌ Failed: {failed}")
    print("="*60)
    
    print("\nTo run interactive mode:")
    print("  python3 test_bridge_connection.py interactive")

if __name__ == "__main__":
    main()
