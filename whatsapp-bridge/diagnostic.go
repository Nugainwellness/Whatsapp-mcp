package main

import (
	"context"
	"fmt"
	"os"
	"time"

	_ "github.com/mattn/go-sqlite3"
	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/store/sqlstore"
	waLog "go.mau.fi/whatsmeow/util/log"
)

func main() {
	fmt.Println("WhatsApp MCP Diagnostic Tool")
	fmt.Println("============================")
	
	// Set up logger with DEBUG level
	logger := waLog.Stdout("Client", "DEBUG", true)
	
	// Create database connection
	dbLog := waLog.Stdout("Database", "DEBUG", true)
	
	// Clean slate - remove old DB
	os.RemoveAll("store/test.db")
	os.MkdirAll("store", 0755)
	
	container, err := sqlstore.New(context.Background(), "sqlite3", "file:store/test.db?_foreign_keys=on", dbLog)
	if err != nil {
		fmt.Printf("Failed to connect to database: %v\n", err)
		return
	}
	
	// Create new device
	deviceStore := container.NewDevice()
	
	// Create client with minimal config
	client := whatsmeow.NewClient(deviceStore, logger)
	
	fmt.Println("\nTesting connection sequence...")
	fmt.Println("Step 1: Creating client - SUCCESS")
	
	// Try the old way (might fail)
	fmt.Println("\nStep 2: Testing QR channel before connect...")
	qrChan, err := client.GetQRChannel(context.Background())
	if err != nil {
		fmt.Printf("ERROR getting QR channel before connect: %v\n", err)
		
		// Try new way
		fmt.Println("\nStep 3: Trying connect first, then QR channel...")
		err = client.Connect()
		if err != nil {
			fmt.Printf("ERROR connecting: %v\n", err)
			return
		}
		
		// Now try QR channel after connect
		qrChan, err = client.GetQRChannel(context.Background())
		if err != nil {
			fmt.Printf("ERROR getting QR channel after connect: %v\n", err)
			return
		}
		fmt.Println("SUCCESS: Connect first, then QR channel works!")
	} else {
		fmt.Println("SUCCESS: QR channel before connect works!")
		
		// Now connect
		err = client.Connect()
		if err != nil {
			fmt.Printf("ERROR connecting after QR channel: %v\n", err)
			return
		}
	}
	
	// Wait for QR
	fmt.Println("\nWaiting for QR code...")
	timeout := time.After(10 * time.Second)
	
	select {
	case evt := <-qrChan:
		fmt.Printf("Received QR event: %s\n", evt.Event)
		if evt.Event == "code" {
			fmt.Println("SUCCESS: QR code received!")
			fmt.Printf("QR code length: %d\n", len(evt.Code))
		}
	case <-timeout:
		fmt.Println("TIMEOUT: No QR code received in 10 seconds")
	}
	
	client.Disconnect()
	fmt.Println("\nDiagnostic complete.")
}
