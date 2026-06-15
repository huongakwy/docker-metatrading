#!/usr/bin/env python3
"""
Signal Sender for MT5 Trading Bridge (Docker Version)
Sends trading signals to MT5 EA/DLL running inside Docker container via TCP port 8080

Usage:
    # Buy order
    python3 signalsender.py --action BUY --symbol XAUUSD --volume 0.01 --sl 2000.0 --tp 2100.0

    # Sell order
    python3 signalsender.py --action SELL --symbol XAUUSD --volume 0.01 --sl 2200.0 --tp 2100.0

    # Close order
    python3 signalsender.py --action CLOSE --symbol XAUUSD

    # Get account info
    python3 signalsender.py --action INFO

    # Test connection
    python3 signalsender.py --action PING
"""

import socket
import json
import argparse
import sys
import time
from typing import Optional, Dict, Any

class MT5SignalSender:
    """Send trading signals to MT5 via TCP socket"""

    def __init__(self, host: str = "localhost", port: int = 8080, timeout: int = 10):
        """
        Initialize signal sender
        
        Args:
            host: Docker host IP (localhost if running on same machine)
            port: Port number (8080 for instance 01, 8081 for instance 02, etc.)
            timeout: Connection timeout in seconds
        """
        self.host = host
        self.port = port
        self.timeout = timeout

    def send_signal(self, signal: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Send trading signal to MT5
        
        Args:
            signal: Signal dictionary containing action and parameters
            
        Returns:
            Response from MT5 EA/DLL or None if error
        """
        try:
            # Create socket connection
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(self.timeout)
            sock.setblocking(True)  # Ensure blocking mode
            
            print(f"🔌 Connecting to {self.host}:{self.port}...")
            sock.connect((self.host, self.port))
            print(f"✅ Connected")
            
            # Convert signal to JSON
            json_data = json.dumps(signal)
            print(f"📤 Sending: {json_data}")
            
            # Send signal (add newline so DLL knows message is complete)
            sock.sendall((json_data + '\n').encode('utf-8'))
            
            # Receive response - read until we have the FINAL JSON response
            # EA sends 2 responses: 1) immediate "queued" 2) final result with ticket
            # We need to wait for response #2 (the one with ticket/retcode)
            response_data = b""
            sock.settimeout(5)  # Shorter timeout
            
            responses_received = 0
            
            try:
                while True:
                    chunk = sock.recv(4096)
                    if not chunk:
                        # Connection closed by server
                        break
                    response_data += chunk
                    
                    # Try to parse JSON after each chunk
                    try:
                        decoded = response_data.decode('utf-8', errors='ignore').strip()
                        lines = [l.strip() for l in decoded.split('\n') if l.strip()]
                        
                        # Count valid JSON responses
                        valid_responses = 0
                        for line in lines:
                            try:
                                json.loads(line)
                                valid_responses += 1
                            except:
                                pass
                        
                        # If we have 2 valid JSON responses, we're done
                        # Response 1: {"ok":true,"msg":"queued"}
                        # Response 2: {"ok":true,"ticket":...,"retcode":...}
                        if valid_responses >= 2:
                            break
                    except Exception:
                        pass
            except socket.timeout:
                # Timeout - that's OK if we already have some data
                pass
            except socket.error:
                # Socket error - that's OK if we already have some data  
                pass
            except Exception as e:
                # Unexpected error
                print(f"⚠️  Error during recv: {e}")
            
            try:
                sock.close()
            except:
                pass
            
            if response_data:
                response_str = response_data.decode('utf-8', errors='ignore').strip()
                print(f"📥 Received ({len(response_data)} bytes):")
                
                # Response may contain multiple JSON lines
                lines = [line.strip() for line in response_str.split('\n') if line.strip()]
                
                for i, line in enumerate(lines, 1):
                    print(f"   Line {i}: {line}")
                
                # Parse response
                # Format can be:
                # 1. Single JSON: {"ok":true,"msg":"queued"}
                # 2. Multiple JSON lines (take the last one as final result)
                # 3. Text format: [TradingBridge] OK - BUY...
                
                if lines:
                    # Try to parse last line as JSON (usually the final result)
                    last_line = lines[-1]
                    
                    try:
                        response = json.loads(last_line)
                        
                        # If we have multiple lines, parse first line too
                        if len(lines) > 1:
                            try:
                                first_response = json.loads(lines[0])
                                response['queued'] = first_response.get('msg') == 'queued'
                            except:
                                pass
                        
                        return response
                        
                    except json.JSONDecodeError:
                        # Not JSON, parse as text
                        if 'OK' in last_line.upper() or 'SUCCESS' in last_line.upper():
                            result = {
                                "ok": True,
                                "message": last_line
                            }
                            
                            # Extract ticket
                            if 'ticket=' in last_line:
                                try:
                                    ticket_str = last_line.split('ticket=')[1].split('|')[0].split()[0].strip()
                                    result['ticket'] = int(ticket_str)
                                except:
                                    pass
                            
                            # Extract retcode
                            if 'retcode=' in last_line:
                                try:
                                    retcode_str = last_line.split('retcode=')[1].split('|')[0].split()[0].strip()
                                    result['retcode'] = int(retcode_str)
                                except:
                                    pass
                            
                            return result
                        else:
                            return {
                                "ok": False,
                                "message": last_line,
                                "error": last_line
                            }
                else:
                    print("⚠️  Empty lines after split")
                    return {
                        "ok": False,
                        "error": "Empty response after parsing"
                    }
            else:
                print("⚠️  Empty response from server")
                return {
                    "ok": False,
                    "error": "Empty response"
                }
                
        except ConnectionRefusedError:
            print(f"❌ Connection refused to {self.host}:{self.port}")
            print("   Make sure:")
            print("   1. Container is running: docker ps | grep mt5")
            print("   2. Port is mapped: docker port mt5_01")
            print("   3. EA is attached to chart")
            return None
            
        except socket.timeout:
            print(f"❌ Connection timeout")
            return None
            
        except Exception as e:
            print(f"❌ Error: {e}")
            import traceback
            traceback.print_exc()
            return None

    def buy(self, symbol: str, volume: float, sl: float = 0, tp: float = 0, 
            comment: str = "", magic: int = 0) -> Optional[Dict[str, Any]]:
        """
        Send BUY order signal
        
        Args:
            symbol: Symbol to trade (e.g., "XAUUSD", "EURUSD")
            volume: Lot size (e.g., 0.01, 0.1, 1.0)
            sl: Stop Loss price (0 = no SL)
            tp: Take Profit price (0 = no TP)
            comment: Order comment
            magic: Magic number
        """
        signal = {
            "action": "BUY",
            "symbol": symbol,
            "volume": volume,
            "lot": volume,  # DLL requires both 'volume' and 'lot' fields
            "sl": sl,
            "tp": tp,
            "comment": comment,
            "magic": magic
        }
        return self.send_signal(signal)

    def sell(self, symbol: str, volume: float, sl: float = 0, tp: float = 0,
             comment: str = "", magic: int = 0) -> Optional[Dict[str, Any]]:
        """
        Send SELL order signal
        
        Args:
            symbol: Symbol to trade (e.g., "XAUUSD", "EURUSD")
            volume: Lot size (e.g., 0.01, 0.1, 1.0)
            sl: Stop Loss price (0 = no SL)
            tp: Take Profit price (0 = no TP)
            comment: Order comment
            magic: Magic number
        """
        signal = {
            "action": "SELL",
            "symbol": symbol,
            "volume": volume,
            "lot": volume,  # DLL requires both 'volume' and 'lot' fields
            "sl": sl,
            "tp": tp,
            "comment": comment,
            "magic": magic
        }
        return self.send_signal(signal)

    def close(self, symbol: str = "", ticket: int = 0) -> Optional[Dict[str, Any]]:
        """
        Close position(s)
        
        Args:
            symbol: Close all positions for this symbol (empty = all symbols)
            ticket: Close specific ticket (0 = all tickets)
        """
        signal = {
            "action": "CLOSE",
            "symbol": symbol,
            "ticket": ticket
        }
        return self.send_signal(signal)

    def close_all(self) -> Optional[Dict[str, Any]]:
        """Close all positions"""
        return self.close(symbol="", ticket=0)

    def get_account_info(self) -> Optional[Dict[str, Any]]:
        """Get account information"""
        signal = {
            "action": "INFO",
            "command": "ACCOUNT"
        }
        return self.send_signal(signal)

    def get_positions(self) -> Optional[Dict[str, Any]]:
        """Get all open positions"""
        signal = {
            "action": "INFO",
            "command": "POSITIONS"
        }
        return self.send_signal(signal)

    def get_balance(self) -> Optional[Dict[str, Any]]:
        """Get account balance"""
        signal = {
            "action": "INFO",
            "command": "BALANCE"
        }
        return self.send_signal(signal)

    def ping(self) -> Optional[Dict[str, Any]]:
        """Test connection"""
        signal = {
            "action": "PING"
        }
        return self.send_signal(signal)


def main():
    """Command line interface"""
    parser = argparse.ArgumentParser(
        description="Send trading signals to MT5 via Docker TCP socket",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Buy 0.01 lot XAUUSD with SL and TP
  python3 signalsender.py --action BUY --symbol XAUUSD --volume 0.01 --sl 2000.0 --tp 2100.0

  # Sell 0.1 lot EURUSD
  python3 signalsender.py --action SELL --symbol EURUSD --volume 0.1 --sl 1.0500 --tp 1.0400

  # Close all XAUUSD positions
  python3 signalsender.py --action CLOSE --symbol XAUUSD

  # Close all positions
  python3 signalsender.py --action CLOSE

  # Get account info
  python3 signalsender.py --action INFO

  # Test connection
  python3 signalsender.py --action PING

  # Send to instance 02 (port 8081)
  python3 signalsender.py --port 8081 --action BUY --symbol XAUUSD --volume 0.01
        """
    )

    parser.add_argument('--host', type=str, default='localhost',
                        help='Docker host (default: localhost)')
    parser.add_argument('--port', type=int, default=8080,
                        help='Port number (8080=instance01, 8081=instance02, etc.)')
    parser.add_argument('--timeout', type=int, default=10,
                        help='Connection timeout in seconds (default: 10)')

    parser.add_argument('--action', type=str, required=True,
                        choices=['BUY', 'SELL', 'CLOSE', 'INFO', 'POSITIONS', 'BALANCE', 'PING'],
                        help='Action to perform')
    parser.add_argument('--symbol', type=str,
                        help='Trading symbol (e.g., XAUUSD, XAUUSDm, EURUSD)')
    parser.add_argument('--volume', type=float,
                        help='Lot size (e.g., 0.01, 0.1, 1.0)')
    parser.add_argument('--sl', type=float, default=0,
                        help='Stop Loss price (default: 0 = no SL)')
    parser.add_argument('--tp', type=float, default=0,
                        help='Take Profit price (default: 0 = no TP)')
    parser.add_argument('--comment', type=str, default='',
                        help='Order comment')
    parser.add_argument('--magic', type=int, default=0,
                        help='Magic number')
    parser.add_argument('--ticket', type=int, default=0,
                        help='Ticket number for CLOSE action')

    args = parser.parse_args()

    # Create sender
    sender = MT5SignalSender(host=args.host, port=args.port, timeout=args.timeout)

    print("="*60)
    print("MT5 Signal Sender (Docker Version)")
    print("="*60)
    print(f"Target: {args.host}:{args.port}")
    print(f"Action: {args.action}")
    print("="*60)
    print()

    # Execute action
    response = None

    if args.action == 'BUY':
        if not args.symbol or args.volume is None:
            print("❌ Error: --symbol and --volume are required for BUY action")
            sys.exit(1)
        response = sender.buy(
            symbol=args.symbol,
            volume=args.volume,
            sl=args.sl,
            tp=args.tp,
            comment=args.comment,
            magic=args.magic
        )

    elif args.action == 'SELL':
        if not args.symbol or args.volume is None:
            print("❌ Error: --symbol and --volume are required for SELL action")
            sys.exit(1)
        response = sender.sell(
            symbol=args.symbol,
            volume=args.volume,
            sl=args.sl,
            tp=args.tp,
            comment=args.comment,
            magic=args.magic
        )

    elif args.action == 'CLOSE':
        response = sender.close(
            symbol=args.symbol if args.symbol else '',
            ticket=args.ticket
        )

    elif args.action == 'INFO':
        response = sender.get_account_info()

    elif args.action == 'POSITIONS':
        response = sender.get_positions()

    elif args.action == 'BALANCE':
        response = sender.get_balance()

    elif args.action == 'PING':
        response = sender.ping()

    # Print result
    print()
    print("="*60)
    print("RESULT")
    print("="*60)

    if response:
        print(json.dumps(response, indent=2, ensure_ascii=False))
        
        # Exit code based on response
        if isinstance(response, dict):
            if response.get('ok') == True:
                print("\n✅ SUCCESS")
                sys.exit(0)
            else:
                print("\n❌ FAILED")
                sys.exit(1)
    else:
        print("❌ No response from server")
        sys.exit(1)


if __name__ == "__main__":
    main()
