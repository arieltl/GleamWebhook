# 🚀 Gleam Webhook System

A robust webhook processing system built with **Gleam** and **SQLite**, featuring comprehensive security validation and automatic payment state management.

## 📋 Overview

This webhook system processes payment notifications with multi-layer security validation, automatically moving payments between states (pending → confirmed/cancelled) based on validation results. All data is persisted in SQLite with atomic transactions.

## ✨ Features

### 🔒 **Security-First Design**
- **Token Authentication**: `X-Webhook-Token` header validation (first line of defense)
- **Exact Data Matching**: All webhook fields must match stored payment data exactly
- **Comprehensive Validation**: Amount, currency, timestamp, and event validation
- **Malformed Data Handling**: Smart cancellation for missing/invalid fields

### 💾 **SQLite Database Integration**
- **Three Tables**: `payments` (pending), `confirmations`, `cancellations`
- **Atomic Transactions**: ACID-compliant payment state transitions
- **Efficient Queries**: Direct payment lookup by transaction ID
- **Auto-cleanup**: Payments automatically moved between tables

### 📊 **Comprehensive Logging**
- Detailed mismatch reporting (amount, currency, date, event)
- Request/response tracking
- Database operation logs
- Security event logging

### 🧪 **Full Test Coverage**
- 6 comprehensive test scenarios
- Token validation tests
- Data validation tests  
- Edge case handling

## 🎯 **Optional Implemented Features**

This project implements **5 out of 6** optional advanced features:

### ✅ **Payload Integrity Verification**
- Comprehensive JSON structure validation
- Required field presence checking
- Data type validation for all fields
- Malformed payload detection and handling

### ✅ **Transaction Authenticity Mechanism**
- **Token-based Authentication**: `X-Webhook-Token` header validation
- **Exact Data Matching**: All webhook fields must match stored payment data exactly
- **Database Lookup Verification**: Transaction must exist in pending payments
- **Multi-layer Validation**: Amount, currency, timestamp, and event verification

### ✅ **Transaction Cancellation on Divergence**
- Automatic cancellation for any field mismatch
- External cancellation API integration (`/cancelar` endpoint)
- Smart cancellation for malformed payloads with extractable transaction IDs
- Database persistence of cancelled transactions

### ✅ **Transaction Confirmation on Success**
- External confirmation API integration (`/confirmar` endpoint)
- Atomic database state transition (pending → confirmed)
- Success response with transaction ID
- Detailed success logging

### ✅ **Database Transaction Persistence**
- **SQLite Integration** with three dedicated tables
- **Atomic Transactions**: ACID-compliant operations
- **State Management**: `payments` → `confirmations`/`cancellations`
- **Timestamped Records**: Automatic confirmation/cancellation timestamps
- **Data Integrity**: Primary key constraints and foreign key relationships

## 🛠️ Installation

### Prerequisites
- **Gleam** (>= 1.10.0)
- **Erlang/OTP** (>= 27.1.2)
- **Python 3.x** (for testing)

### Setup
```bash
# Clone the repository
git clone https://github.com/your-username/gleamWebhook.git
cd gleamWebhook

# Install Gleam dependencies
gleam deps download

# Install Python dependencies for testing
pip install -r requirements.txt
```

## 🚀 Running the Application

### Start the Webhook Server
```bash
gleam run
```

The server will start on `http://localhost:5000` and will:
- Initialize SQLite database (`webhook.db`)
- Clear existing data
- Load initial pending payments
- Start listening for webhook requests

### Expected Output
```
Database tables cleared successfully
Initial pending payments inserted successfully
Listening on http://127.0.0.1:5000
```

## 🧪 Testing

### Run Complete Test Suite
```bash
# Start the webhook server first
gleam run

# In another terminal, run the test suite
python test_webhook.py
```

### Test Scenarios
1. **✅ Valid Webhook** - Correct token + matching data → Payment confirmed
2. **🔄 Duplicate Transaction** - Same payment twice → Second attempt rejected
3. **❌ Amount Mismatch** - Wrong amount → Payment cancelled
4. **🚫 Invalid Token** - Wrong/missing token → Request rejected
5. **📝 Invalid Payload** - Malformed JSON → Request rejected
6. **⚠️ Missing Fields** - Incomplete data → Payment cancelled

### Expected Results
```
6/6 tests completed.
Confirmações recebidas: ['abc123']
Cancelamentos recebidos: ['abc123a', 'abc123abc']
```

## 📡 API Documentation

### Webhook Endpoint
**POST** `/webhook`

**Headers:**
```
Content-Type: application/json
X-Webhook-Token: meu-token-secreto
```

**Request Body:**
```json
{
  "transaction_id": "abc123",
  "amount": "49.90",
  "currency": "BRL", 
  "event": "payment_success",
  "timestamp": "2023-10-01T12:00:00Z"
}
```

### Response Codes
- **200** - Payment confirmed successfully
- **400** - Invalid token, data mismatch, or malformed request
- **404** - Payment not found in database
- **500** - Database error



## 🏗️ Project Structure

```
gleamWebhook/
├── src/
│   ├── gleamwebhook.gleam      # Main application entry point
│   └── app/
│       ├── router.gleam        # HTTP request handling & validation
│       ├── database.gleam      # SQLite operations
│       └── web.gleam          # Type definitions
├── test/
│   └── gleamwebhook_test.gleam # Unit tests
├── test_webhook.py             # Integration test suite
├── gleam.toml                  # Project configuration
├── requirements.txt            # Python test dependencies
└── README.md                   # This file
```

## 🔧 Configuration

### Database Schema
```sql
-- Pending payments
CREATE TABLE payments (
  transaction_id TEXT PRIMARY KEY,
  amount TEXT NOT NULL,
  currency TEXT NOT NULL,
  event TEXT NOT NULL,
  timestamp TEXT NOT NULL
);

-- Confirmed payments  
CREATE TABLE confirmations (
  transaction_id TEXT PRIMARY KEY,
  amount TEXT NOT NULL,
  currency TEXT NOT NULL,
  event TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  confirmed_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Cancelled payments
CREATE TABLE cancellations (
  transaction_id TEXT PRIMARY KEY,
  amount TEXT NOT NULL,
  currency TEXT NOT NULL,
  event TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  cancelled_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### Initial Data
The application loads these test payments on startup:
```gleam
[
  PaymentWebhook("abc123", "49.90", "BRL", "payment_success", "2023-10-01T12:00:00Z"),
  PaymentWebhook("abc123a", "29.90", "BRL", "payment_success", "2023-10-01T13:00:00Z"),
  PaymentWebhook("def456", "29.90", "BRL", "payment_success", "2023-10-01T13:00:00Z"),
  PaymentWebhook("ghi789", "99.90", "BRL", "payment_success", "2023-10-01T14:00:00Z"),
]
```

## 🛡️ Security Flow

1. **Token Validation** - Verify `X-Webhook-Token` header
2. **JSON Parsing** - Decode and validate webhook structure  
3. **Database Lookup** - Find payment by `transaction_id`
4. **Field Validation** - Exact match of all fields against stored data
5. **State Transition** - Move payment to appropriate table
6. **External Notification** - Send confirmation/cancellation to external service

## 🐛 Troubleshooting

### Common Issues

**Port Already in Use:**
```bash
# Kill existing Gleam processes
pkill gleam

# Or use a different port by modifying gleamwebhook.gleam
```

**Database Errors:**
- Database file is automatically created
- Tables are recreated on each startup
- Check file permissions for `webhook.db`

**Test Failures:**
- Ensure webhook server is running first
- Check that ports 5000 and 5001 are available
- Verify Python dependencies are installed

## 🤖 Generative AI Usage

This project was developed with assistance from generative AI technologies in the following ways:

• **IDE Autocomplete**: Generative AI autocomplete was enabled in the development environment
• **Debugging & Issue Resolution**: Generative AI was utilized to debug and solve complex issues
• **Documentation Enhancement**: Generative AI assisted in improving code structure, formatting this comprehensive README, and ensuring clear technical documentation
• **SQL Query Generation**: Generative AI was used to generate SQL queries for the database

