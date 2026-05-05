#!/bin/bash

# WhatsApp MCP Setup and Fix Script
# This script updates the whatsmeow library and cleans up old sessions

echo "╔════════════════════════════════════════╗"
echo "║    WhatsApp MCP Setup & Fix Script     ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Navigate to the whatsapp-bridge directory
cd "$(dirname "$0")"

echo "1. Checking network connectivity..."
if ping -c 1 google.com &> /dev/null; then
    echo "   ✓ Internet connection OK"
else
    echo "   ✗ No internet connection detected"
    echo "   Please check your network connection and try again."
    exit 1
fi

echo ""
echo "2. Checking WhatsApp Web accessibility..."
if curl -s -o /dev/null -w "%{http_code}" https://web.whatsapp.com | grep -q "200"; then
    echo "   ✓ WhatsApp Web is accessible"
else
    echo "   ⚠ WhatsApp Web might be blocked or unreachable"
    echo "   This could cause connection issues."
fi

echo ""
echo "3. Updating whatsmeow library to latest version..."
echo "   Current version:"
go list -m go.mau.fi/whatsmeow | grep -o 'v[0-9.]*' || echo "   Not found"
go get -u go.mau.fi/whatsmeow@latest
echo "   New version:"
go list -m go.mau.fi/whatsmeow | grep -o 'v[0-9.]*'
echo "   ✓ Updated whatsmeow"

echo ""
echo "4. Updating all dependencies..."
go mod tidy
echo "   ✓ Dependencies updated"

echo ""
echo "5. Cleaning up old session data..."
if [ -d "store" ]; then
    rm -rf store/*.db
    rm -f qr_code.txt
    echo "   ✓ Old session data removed"
else
    mkdir -p store
    echo "   ✓ Created store directory"
fi

echo ""
echo "6. Checking for common issues..."
# Check if running behind proxy
if [ ! -z "$HTTP_PROXY" ] || [ ! -z "$HTTPS_PROXY" ]; then
    echo "   ⚠ Proxy detected. This might interfere with WhatsApp connection."
    echo "     Consider running without proxy if you experience issues."
fi

# Check Go version
GO_VERSION=$(go version | grep -o 'go[0-9.]*')
echo "   Go version: $GO_VERSION"
if [[ "$GO_VERSION" < "go1.19" ]]; then
    echo "   ⚠ Go version might be too old. Consider updating to Go 1.19+"
fi

echo ""
echo "7. Building the application..."
go build -o whatsapp-bridge main.go
if [ $? -eq 0 ]; then
    echo "   ✓ Build successful"
else
    echo "   ✗ Build failed. Please check for errors above."
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════╗"
echo "║           Setup Complete!              ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "You can now run the application with:"
echo "  ./whatsapp-bridge"
echo ""
echo "Or if you prefer:"
echo "  go run main.go"
echo ""
echo "TROUBLESHOOTING:"
echo "• If QR code doesn't appear: Check qr_code.txt"
echo "• If timeout occurs: Wait 5 minutes and try again"
echo "• If still having issues: Check firewall/VPN settings"
echo ""
echo "For persistent issues, try:"
echo "  1. Disable VPN/proxy if using one"
echo "  2. Check if web.whatsapp.com works in browser"
echo "  3. Try from a different network"
