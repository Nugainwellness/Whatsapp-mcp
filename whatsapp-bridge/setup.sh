#!/bin/bash

# WhatsApp MCP Setup and Fix Script
# This script updates the whatsmeow library and cleans up old sessions

echo "╔════════════════════════════════════════╗"
echo "║    WhatsApp MCP Setup & Fix Script     ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Navigate to the whatsapp-bridge directory
cd "$(dirname "$0")"

echo "1. Updating whatsmeow library to latest version..."
go get -u go.mau.fi/whatsmeow@latest
echo "   ✓ Updated whatsmeow"

echo ""
echo "2. Updating all dependencies..."
go mod tidy
echo "   ✓ Dependencies updated"

echo ""
echo "3. Cleaning up old session data..."
if [ -d "store" ]; then
    rm -rf store/*.db
    rm -f qr_code.txt
    echo "   ✓ Old session data removed"
else
    echo "   ℹ No existing session data found"
fi

echo ""
echo "4. Building the application..."
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
echo "The QR code will appear in the terminal."
echo "If it doesn't display properly, check qr_code.txt"
