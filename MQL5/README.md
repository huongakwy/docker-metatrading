# MQL5 Directory Structure

This directory contains MetaTrader 5 MQL5 files that will be mounted into Docker containers.

## Directory Structure

```
MQL5/
├── Experts/              # Expert Advisors (.ex5 files)
├── Libraries/            # DLL libraries (.dll files)
├── Scripts/              # MQL5 scripts
├── Indicators/           # Custom indicators
├── Include/              # Include files (.mqh)
└── Profiles/
    └── Templates/        # Chart templates (.tpl files)
```

## Usage

### Adding EA Files

Copy your compiled EA files here:
```bash
cp YourEA.ex5 MQL5/Experts/
```

### Adding DLL Files

Copy your DLL dependencies here:
```bash
cp YourLibrary.dll MQL5/Libraries/
```

### Adding Templates

1. **Option A:** Create template in MT5 VNC and extract it
   ```bash
   docker cp mt5_account_01:/root/.wine/drive_c/Program\ Files/MetaTrader\ 5/Profiles/Templates/YourTemplate.tpl ./MQL5/Profiles/Templates/
   ```

2. **Option B:** Copy pre-made template
   ```bash
   cp YourTemplate.tpl MQL5/Profiles/Templates/
   ```

### Verify Files in Container

```bash
# Check EA files
docker exec mt5_account_01 ls -la /root/.wine/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Experts/

# Check DLL files
docker exec mt5_account_01 ls -la /root/.wine/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Libraries/

# Check templates
docker exec mt5_account_01 ls -la /root/.wine/drive_c/Program\ Files/MetaTrader\ 5/Profiles/Templates/
```

## Important Notes

1. **File Permissions:** Ensure files have proper permissions
   ```bash
   chmod 644 MQL5/Experts/*.ex5
   chmod 644 MQL5/Libraries/*.dll
   chmod 644 MQL5/Profiles/Templates/*.tpl
   ```

2. **Shared Files:** Files in this directory are shared across all containers (unless overridden by account-specific mounts)

3. **EA Names:** When configuring startup.ini, use EA name WITHOUT .ex5 extension
   ```ini
   Expert=TradingBridgeeaV2  # NOT TradingBridgeeaV2.ex5
   ```

4. **Template Names:** Use template name WITH .tpl extension
   ```ini
   Template=AutoBridge.tpl
   ```

## Example: Setting Up a New EA

```bash
# 1. Copy EA and DLL
cp TradingBridgeeaV2.ex5 MQL5/Experts/
cp TradingBridgeV2.dll MQL5/Libraries/

# 2. Copy template (if you have one)
cp AutoBridge.tpl MQL5/Profiles/Templates/

# 3. Update startup.ini
# Edit configs/account_01/startup.ini:
#   [StartUp]
#   Expert=TradingBridgeeaV2
#   Template=AutoBridge.tpl

# 4. Restart container
docker restart mt5_account_01

# 5. Verify
./scripts/test-startup-config.sh 01
```

## Troubleshooting

### EA Not Found

**Problem:** EA doesn't attach, logs show "EA not found"

**Solutions:**
1. Verify file exists:
   ```bash
   ls -la MQL5/Experts/TradingBridgeeaV2.ex5
   ```

2. Check container mount:
   ```bash
   docker exec mt5_account_01 ls /root/.wine/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Experts/
   ```

3. Restart container:
   ```bash
   docker restart mt5_account_01
   ```

### Template Not Applied

**Problem:** Chart doesn't use the template

**Solutions:**
1. Verify template exists:
   ```bash
   ls -la MQL5/Profiles/Templates/AutoBridge.tpl
   ```

2. Check template name in startup.ini matches file name exactly (case-sensitive)

3. Extract template from working MT5 instance:
   - Open MT5 via VNC
   - Set up chart as desired
   - Right-click chart → Template → Save Template
   - Copy from container to host

## Per-Account Customization

To use different EAs for different accounts:

```bash
# Create account-specific MQL5 directories
mkdir -p configs/account_01/MQL5/Experts
mkdir -p configs/account_02/MQL5/Experts

# Copy different EAs
cp EA_Strategy1.ex5 configs/account_01/MQL5/Experts/
cp EA_Strategy2.ex5 configs/account_02/MQL5/Experts/

# Update docker-compose.yml to use account-specific mounts
# See docker-compose.yml for examples
```

## File Reference

| File Type | Extension | Location | Used For |
|-----------|-----------|----------|----------|
| Expert Advisor | .ex5 | Experts/ | Automated trading |
| Library | .dll | Libraries/ | EA dependencies |
| Script | .ex5 | Scripts/ | Manual execution |
| Indicator | .ex5 | Indicators/ | Chart analysis |
| Template | .tpl | Profiles/Templates/ | Chart layout |
| Settings | .set | Profiles/ | EA parameters |

## Security Notes

1. **DLL Files:** Only use trusted DLL files. Malicious DLLs can compromise your system
2. **Source Control:** Add *.ex5 and *.dll to .gitignore if they contain proprietary code
3. **Backup:** Keep backup copies of all EA files before updates
