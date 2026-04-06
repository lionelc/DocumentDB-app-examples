# E-commerce Analytics Dashboard

A real-time e-commerce analytics dashboard demonstrating DocumentDB's capabilities with continuous data streaming from simulated social media comments and reviews.

## Features

- **Real-time Data Generation**: Continuous streaming of orders, reviews, and social media comments
- **Live Dashboard**: Interactive web interface with charts and live feed
- **Data Quality Monitoring**: Referential integrity checks showcasing DocumentDB's SQL-like capabilities
- **Sales Analytics**: Multi-collection joins for revenue analysis
- **Inventory Management**: Complex upsert operations demo
- **Social Media Feed**: Sentiment analysis on streaming social comments

## Prerequisites

- Docker
- Python 3.10+
- pip

## Quick Start

### Step 1: Launch DocumentDB Container (see [documentdb.io](https://documentdb.io/docs/getting-started/python-setup))

```bash
# Pull the latest DocumentDB Docker image
docker pull ghcr.io/documentdb/documentdb/documentdb-local:latest

# Tag the image for convenience
docker tag ghcr.io/documentdb/documentdb/documentdb-local:latest documentdb

# Run the container with your chosen username and password
docker run -dt -p 10260:10260 --name documentdb-container documentdb --username YOUR_USERNAME --password YOUR_PASSWORD
```

### Step 2: Set Up Python Environment

```bash
# Navigate to the ecommerce folder
cd /path/to/pgmongo/examples/ecommerce

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate  # Linux/Mac
# or
.\venv\Scripts\activate   # Windows

# Install dependencies
pip install -r requirements.txt
```

### Step 3: Run the Application
First, please use YOUR_USERNAME and YOUR_PASSWORD you chose in Step 1 to fill Line 54 of app.py:

```
DB_URI = "mongodb://YOUR_USERNAME:YOUR_PASSWORD@localhost:10260/?tls=true&tlsAllowInvalidCertificates=true&retryWrites=false&directConnection=true"
```

Then run:

```bash
# Start the server
python app.py
```

You should see output like:
```
🚀 Starting E-commerce Dashboard Server...
   Dashboard: http://localhost:5000
   API Docs:  http://localhost:5000/api/overview
[Seed] Creating initial demo data...
[Seed] Created: 100 customers, 50 products, 200 orders, 95 reviews, 100 social comments
[Generator] Started at 5 items/sec
[Server] Data generator started at 5 items/sec
```

### Step 4: Access the Dashboard

Open your browser and navigate to:
- **Dashboard**: http://localhost:5000
- **API Overview**: http://localhost:5000/api/overview

The UI looks like:

<img width="1601" height="605" alt="image" src="https://github.com/user-attachments/assets/5d64cdbb-b59e-40b9-a7f9-12b46ed26696" />


## Dashboard Sections

| Section | Description |
|---------|-------------|
| **Overview** | Key metrics: customers, products, orders, revenue |
| **Live Feed** | Real-time social media comments with sentiment analysis |
| **Data Quality** | Referential integrity checks and health score |
| **Sales Analytics** | Revenue trends, category breakdown, top products |
| **Customers** | Customer tiers and loyalty analytics |
| **Inventory** | Warehouse summary and low stock alerts |

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GENERATOR_RATE` | `5` | Items generated per second |
| `GENERATOR_BATCH_SIZE` | `10` | Items per batch insert |

Example:
```bash
GENERATOR_RATE=10 python app.py
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Dashboard web interface |
| `/api/overview` | GET | Overview statistics |
| `/api/stream/stats` | GET | Data generator statistics |
| `/api/social-feed` | GET | Social media comments feed |
| `/api/data-quality` | GET | Referential integrity report |
| `/api/sales-analytics` | GET | Sales and revenue analytics |
| `/api/customers` | GET | Customer list and tier distribution |
| `/api/inventory` | GET | Inventory status and alerts |
| `/api/inventory/sync` | POST | Simulate inventory sync |

## Data Lifecycle

- **On Startup**: Seeds initial demo data (customers, products, orders, reviews, social comments)
- **While Running**: Continuously generates new orders, reviews, and social comments
- **On Shutdown** (Ctrl+C): Cleans up all data from DocumentDB

## Stopping the Application

Press `Ctrl+C` in the terminal. The application will:
1. Stop the data generator
2. Clean up all collections from DocumentDB
3. Close the database connection

## Troubleshooting

### "Cannot connect to DocumentDB"
- Ensure the DocumentDB container is running: `docker ps`
- Check if port 10260 is available: `lsof -i :10260`
- Restart the container: `docker restart documentdb-container`

### "Module not found" errors
- Ensure virtual environment is activated
- Reinstall dependencies: `pip install -r requirements.txt`

### Dashboard shows no data
- Check browser console for JavaScript errors
- Verify API is responding: `curl http://localhost:5000/api/overview`
- Ensure DocumentDB container is running

## Project Structure

```
ecommerce/
├── app.py              # Flask application with API routes
├── generator.py        # Real-time data generator
├── requirements.txt    # Python dependencies
├── templates/
│   └── index.html      # Dashboard HTML template
└── static/
    ├── css/
    │   └── style.css   # Dashboard styles
    └── js/
        └── dashboard.js # Dashboard JavaScript
```

## License

This is a demo application for testing DocumentDB capabilities.
