#!/usr/bin/env python3
"""
E-commerce Dashboard Backend
============================
Flask-based API server for the e-commerce analytics dashboard.
Demonstrates DocumentDB strengths with a web interface.
"""

import atexit
import os
import signal
import random
import string
import json
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Optional
from flask import Flask, jsonify, render_template, request
from flask_cors import CORS
from pymongo import MongoClient, ASCENDING, DESCENDING
from pymongo.errors import OperationFailure
from bson import ObjectId

from generator import DataGenerator, seed_initial_data, cleanup_data


class JSONEncoder(json.JSONEncoder):
    """Custom JSON encoder that handles MongoDB ObjectId and datetime."""
    def default(self, obj):
        if isinstance(obj, ObjectId):
            return str(obj)
        if isinstance(obj, datetime):
            return obj.isoformat()
        return super().default(obj)


def serialize_doc(doc):
    """Convert MongoDB document to JSON-serializable dict."""
    if doc is None:
        return None
    if isinstance(doc, list):
        return [serialize_doc(d) for d in doc]
    if isinstance(doc, dict):
        return {k: serialize_doc(v) for k, v in doc.items()}
    if isinstance(doc, ObjectId):
        return str(doc)
    if isinstance(doc, datetime):
        return doc.isoformat()
    return doc

# ============================================================================
# CONFIGURATION
# ============================================================================

DB_URI = "mongodb://YOUR_USERNAME:YOUR_PASSWORD@localhost:10260/?tls=true&tlsAllowInvalidCertificates=true&retryWrites=false&directConnection=true" 
DB_NAME = "ecommerce_demo"

app = Flask(__name__)
app.json.encoder = JSONEncoder  # Use custom encoder for ObjectId
CORS(app)

# Global database connection
client = None
db = None

# Global data generator
data_generator: Optional[DataGenerator] = None


def get_db():
    """Get database connection."""
    global client, db
    if client is None:
        client = MongoClient(DB_URI)
        db = client[DB_NAME]
    return db


_shutdown_done = False

def shutdown_handler():
    """Handle server shutdown - stop generator and cleanup data."""
    global data_generator, client, db, _shutdown_done
    
    # Prevent double shutdown
    if _shutdown_done:
        return
    _shutdown_done = True
    
    print("\n[Server] Shutting down...")
    
    # Stop generator first
    if data_generator:
        print("[Server] Stopping data generator...")
        data_generator.stop()
        data_generator = None
    
    # Cleanup data (before closing client!)
    if client is not None and db is not None:
        try:
            cleanup_data(db)
        except Exception as e:
            print(f"[Cleanup] Error during cleanup: {e}")
    
    # Close connection last
    if client is not None:
        try:
            client.close()
        except Exception:
            pass
        client = None
        db = None
    
    print("[Server] Shutdown complete")


def initialize_server():
    """Initialize server - seed data and start generator."""
    global data_generator
    
    database = get_db()
    
    # Seed initial data
    seed_initial_data(database, small=True)
    
    # Start data generator
    rate = int(os.environ.get('GENERATOR_RATE', 5))
    data_generator = DataGenerator(database, rate=rate)
    data_generator.start()
    
    print(f"[Server] Data generator started at {rate} items/sec")


# Register shutdown handler
atexit.register(shutdown_handler)


def random_string(length: int = 8) -> str:
    return ''.join(random.choices(string.ascii_letters, k=length))


# ============================================================================
# API ROUTES - Dashboard Data
# ============================================================================

@app.route('/')
def index():
    """Serve the main dashboard page."""
    return render_template('index.html')


@app.route('/api/overview')
def get_overview():
    """Get overview statistics for the dashboard."""
    db = get_db()
    
    try:
        # Get counts
        total_customers = db.customers.count_documents({})
        total_products = db.products.count_documents({})
        total_orders = db.orders.count_documents({})
        
        # Calculate total revenue
        revenue_pipeline = [
            {"$lookup": {
                "from": "order_items",
                "localField": "order_id",
                "foreignField": "order_id",
                "as": "items"
            }},
            {"$unwind": "$items"},
            {"$group": {
                "_id": None,
                "total_revenue": {"$sum": {
                    "$multiply": [
                        "$items.quantity",
                        "$items.unit_price",
                        {"$subtract": [1, {"$ifNull": ["$items.discount", 0]}]}
                    ]
                }}
            }}
        ]
        revenue_result = list(db.orders.aggregate(revenue_pipeline))
        total_revenue = revenue_result[0]["total_revenue"] if revenue_result else 0
        
        # Get order status breakdown
        status_pipeline = [
            {"$group": {"_id": "$status", "count": {"$sum": 1}}},
            {"$sort": {"count": -1}}
        ]
        order_statuses = list(db.orders.aggregate(status_pipeline))
        
        # Get orders today
        today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
        orders_today = db.orders.count_documents({"created_at": {"$gte": today_start}})
        
        # Calculate average order value
        avg_order_value = total_revenue / total_orders if total_orders > 0 else 0
        
        return jsonify({
            "success": True,
            "data": {
                "total_customers": total_customers,
                "total_products": total_products,
                "total_orders": total_orders,
                "total_revenue": round(total_revenue, 2),
                "orders_today": orders_today,
                "avg_order_value": round(avg_order_value, 2),
                "order_statuses": [{"status": s["_id"], "count": s["count"]} for s in order_statuses]
            }
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route('/api/data-quality')
def get_data_quality():
    """Get data quality report - Referential Integrity Check."""
    db = get_db()
    
    try:
        issues = []
        
        # 1. Orphaned order items
        pipeline = [
            {"$lookup": {
                "from": "products",
                "localField": "product_id",
                "foreignField": "product_id",
                "as": "product"
            }},
            {"$match": {"product": {"$size": 0}}},
            {"$count": "count"}
        ]
        result = list(db.order_items.aggregate(pipeline))
        orphaned_items = result[0]["count"] if result else 0
        issues.append({
            "type": "Orphaned Order Items",
            "description": "Order items referencing deleted products",
            "count": orphaned_items,
            "severity": "high" if orphaned_items > 10 else "medium" if orphaned_items > 0 else "low"
        })
        
        # 2. Orders with deleted customers
        pipeline = [
            {"$lookup": {
                "from": "customers",
                "localField": "customer_id",
                "foreignField": "customer_id",
                "as": "customer"
            }},
            {"$match": {"customer": {"$size": 0}}},
            {"$count": "count"}
        ]
        result = list(db.orders.aggregate(pipeline))
        orphaned_orders = result[0]["count"] if result else 0
        issues.append({
            "type": "Orders Without Customers",
            "description": "Orders referencing deleted customers",
            "count": orphaned_orders,
            "severity": "high" if orphaned_orders > 5 else "medium" if orphaned_orders > 0 else "low"
        })
        
        # 3. Orphaned inventory
        pipeline = [
            {"$lookup": {
                "from": "products",
                "localField": "product_id",
                "foreignField": "product_id",
                "as": "product"
            }},
            {"$match": {"product": {"$size": 0}}},
            {"$group": {
                "_id": None,
                "count": {"$sum": 1},
                "units": {"$sum": "$quantity"}
            }}
        ]
        result = list(db.inventory.aggregate(pipeline))
        if result:
            orphaned_inventory = result[0]["count"]
            orphaned_units = result[0]["units"]
        else:
            orphaned_inventory = 0
            orphaned_units = 0
        issues.append({
            "type": "Orphaned Inventory",
            "description": f"Inventory records for deleted products ({orphaned_units} units)",
            "count": orphaned_inventory,
            "severity": "medium" if orphaned_inventory > 0 else "low"
        })
        
        # 4. Invalid reviews
        pipeline = [
            {"$lookup": {
                "from": "products",
                "localField": "product_id",
                "foreignField": "product_id",
                "as": "product"
            }},
            {"$match": {"product": {"$size": 0}}},
            {"$count": "count"}
        ]
        result = list(db.reviews.aggregate(pipeline))
        invalid_reviews = result[0]["count"] if result else 0
        issues.append({
            "type": "Invalid Reviews",
            "description": "Reviews for deleted products",
            "count": invalid_reviews,
            "severity": "low"
        })
        
        # 5. Products from inactive suppliers
        pipeline = [
            {"$lookup": {
                "from": "suppliers",
                "localField": "supplier_id",
                "foreignField": "supplier_id",
                "as": "supplier"
            }},
            {"$unwind": "$supplier"},
            {"$match": {"supplier.active": False, "active": True}},
            {"$count": "count"}
        ]
        result = list(db.products.aggregate(pipeline))
        inactive_supplier_products = result[0]["count"] if result else 0
        issues.append({
            "type": "Inactive Supplier Products",
            "description": "Active products from inactive suppliers",
            "count": inactive_supplier_products,
            "severity": "medium" if inactive_supplier_products > 10 else "low"
        })
        
        total_issues = sum(i["count"] for i in issues)
        
        return jsonify({
            "success": True,
            "data": {
                "total_issues": total_issues,
                "issues": issues,
                "health_score": max(0, 100 - total_issues * 2)
            }
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route('/api/sales-analytics')
def get_sales_analytics():
    """Get sales analytics data."""
    db = get_db()
    days = request.args.get('days', 90, type=int)
    
    try:
        since_date = datetime.now(timezone.utc) - timedelta(days=days)
        
        # Revenue by category
        category_pipeline = [
            {"$match": {"created_at": {"$gte": since_date}}},
            {"$lookup": {
                "from": "order_items",
                "localField": "order_id",
                "foreignField": "order_id",
                "as": "items"
            }},
            {"$unwind": "$items"},
            {"$lookup": {
                "from": "products",
                "localField": "items.product_id",
                "foreignField": "product_id",
                "as": "product"
            }},
            {"$unwind": {"path": "$product", "preserveNullAndEmptyArrays": True}},
            {"$lookup": {
                "from": "categories",
                "localField": "product.category_id",
                "foreignField": "category_id",
                "as": "category"
            }},
            {"$unwind": {"path": "$category", "preserveNullAndEmptyArrays": True}},
            {"$group": {
                "_id": "$category.name",
                "revenue": {"$sum": {
                    "$multiply": ["$items.quantity", "$items.unit_price"]
                }},
                "orders": {"$addToSet": "$order_id"},
                "units": {"$sum": "$items.quantity"}
            }},
            {"$project": {
                "category": {"$ifNull": ["$_id", "Uncategorized"]},
                "revenue": {"$round": ["$revenue", 2]},
                "order_count": {"$size": "$orders"},
                "units_sold": "$units"
            }},
            {"$sort": {"revenue": -1}}
        ]
        
        category_data = list(db.orders.aggregate(category_pipeline, allowDiskUse=True))
        
        # Top products
        product_pipeline = [
            {"$match": {"created_at": {"$gte": since_date}}},
            {"$lookup": {
                "from": "order_items",
                "localField": "order_id",
                "foreignField": "order_id",
                "as": "items"
            }},
            {"$unwind": "$items"},
            {"$lookup": {
                "from": "products",
                "localField": "items.product_id",
                "foreignField": "product_id",
                "as": "product"
            }},
            {"$unwind": {"path": "$product", "preserveNullAndEmptyArrays": True}},
            {"$group": {
                "_id": "$items.product_id",
                "name": {"$first": "$product.name"},
                "revenue": {"$sum": {
                    "$multiply": ["$items.quantity", "$items.unit_price"]
                }},
                "units": {"$sum": "$items.quantity"}
            }},
            {"$project": {
                "product_id": "$_id",
                "name": {"$ifNull": ["$name", "Unknown"]},
                "revenue": {"$round": ["$revenue", 2]},
                "units_sold": "$units"
            }},
            {"$sort": {"revenue": -1}},
            {"$limit": 10}
        ]
        
        top_products = list(db.orders.aggregate(product_pipeline, allowDiskUse=True))
        
        # Daily revenue trend
        daily_pipeline = [
            {"$match": {"created_at": {"$gte": since_date}}},
            {"$lookup": {
                "from": "order_items",
                "localField": "order_id",
                "foreignField": "order_id",
                "as": "items"
            }},
            {"$unwind": "$items"},
            {"$group": {
                "_id": {
                    "$dateToString": {"format": "%Y-%m-%d", "date": "$created_at"}
                },
                "revenue": {"$sum": {
                    "$multiply": ["$items.quantity", "$items.unit_price"]
                }},
                "orders": {"$addToSet": "$order_id"}
            }},
            {"$project": {
                "date": "$_id",
                "revenue": {"$round": ["$revenue", 2]},
                "order_count": {"$size": "$orders"}
            }},
            {"$sort": {"date": 1}}
        ]
        
        daily_trend = list(db.orders.aggregate(daily_pipeline, allowDiskUse=True))
        
        return jsonify({
            "success": True,
            "data": {
                "category_revenue": category_data,
                "top_products": top_products,
                "daily_trend": daily_trend,
                "period_days": days
            }
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route('/api/customers')
def get_customers():
    """Get customer list with summary stats."""
    db = get_db()
    limit = request.args.get('limit', 20, type=int)
    tier = request.args.get('tier', None)
    
    try:
        match_stage = {}
        if tier:
            match_stage["tier"] = tier
        
        pipeline = [
            {"$match": match_stage} if match_stage else {"$match": {}},
            {"$lookup": {
                "from": "orders",
                "localField": "customer_id",
                "foreignField": "customer_id",
                "as": "orders"
            }},
            {"$project": {
                "customer_id": 1,
                "name": 1,
                "email": 1,
                "tier": 1,
                "loyalty_points": 1,
                "address": 1,
                "created_at": 1,
                "order_count": {"$size": "$orders"}
            }},
            {"$sort": {"loyalty_points": -1}},
            {"$limit": limit}
        ]
        
        customers = list(db.customers.aggregate(pipeline))
        
        # Get tier distribution
        tier_pipeline = [
            {"$group": {"_id": "$tier", "count": {"$sum": 1}}},
            {"$sort": {"count": -1}}
        ]
        tier_distribution = list(db.customers.aggregate(tier_pipeline))
        
        return jsonify({
            "success": True,
            "data": {
                "top_customers": serialize_doc(customers),
                "tier_distribution": [{"_id": t["_id"], "count": t["count"]} for t in tier_distribution]
            }
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route('/api/customer/<customer_id>')
def get_customer_detail(customer_id):
    """Get detailed customer 360 view."""
    db = get_db()
    
    try:
        pipeline = [
            {"$match": {"customer_id": customer_id}},
            {"$lookup": {
                "from": "orders",
                "localField": "customer_id",
                "foreignField": "customer_id",
                "as": "orders"
            }},
            {"$unwind": {"path": "$orders", "preserveNullAndEmptyArrays": True}},
            {"$lookup": {
                "from": "order_items",
                "localField": "orders.order_id",
                "foreignField": "order_id",
                "as": "orders.items"
            }},
            {"$group": {
                "_id": "$customer_id",
                "info": {"$first": {
                    "name": "$name",
                    "email": "$email",
                    "tier": "$tier",
                    "loyalty_points": "$loyalty_points",
                    "address": "$address",
                    "created_at": "$created_at"
                }},
                "orders": {"$push": "$orders"},
                "total_spent": {"$sum": {
                    "$reduce": {
                        "input": "$orders.items",
                        "initialValue": 0,
                        "in": {"$add": [
                            "$$value",
                            {"$multiply": [
                                {"$ifNull": ["$$this.quantity", 0]},
                                {"$ifNull": ["$$this.unit_price", 0]}
                            ]}
                        ]}
                    }
                }}
            }},
            {"$project": {
                "customer_id": "$_id",
                "info": 1,
                "order_count": {"$size": {"$filter": {
                    "input": "$orders",
                    "as": "o",
                    "cond": {"$ne": ["$$o.order_id", None]}
                }}},
                "total_spent": {"$round": ["$total_spent", 2]}
            }}
        ]
        
        result = list(db.customers.aggregate(pipeline, allowDiskUse=True))
        
        if not result:
            return jsonify({"success": False, "error": "Customer not found"}), 404
        
        customer = result[0]
        
        # Get recent reviews
        reviews = list(db.reviews.find(
            {"customer_id": customer_id},
            {"_id": 0, "product_id": 1, "rating": 1, "title": 1, "created_at": 1}
        ).sort("created_at", -1).limit(5))
        
        customer["recent_reviews"] = reviews
        
        return jsonify({
            "success": True,
            "data": customer
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route('/api/inventory')
def get_inventory():
    """Get inventory status."""
    db = get_db()
    
    try:
        # Low stock items
        low_stock_pipeline = [
            {"$match": {
                "$expr": {
                    "$lt": [
                        {"$subtract": ["$quantity", "$reserved"]},
                        {"$ifNull": ["$reorder_point", 20]}
                    ]
                }
            }},
            {"$lookup": {
                "from": "products",
                "localField": "product_id",
                "foreignField": "product_id",
                "as": "product"
            }},
            {"$unwind": {"path": "$product", "preserveNullAndEmptyArrays": True}},
            {"$project": {
                "product_id": 1,
                "product_name": {"$ifNull": ["$product.name", "Unknown"]},
                "warehouse": 1,
                "quantity": 1,
                "reserved": 1,
                "available": {"$subtract": ["$quantity", "$reserved"]},
                "reorder_point": {"$ifNull": ["$reorder_point", 20]}
            }},
            {"$sort": {"available": 1}},
            {"$limit": 20}
        ]
        
        low_stock = list(db.inventory.aggregate(low_stock_pipeline))
        
        # Warehouse summary
        warehouse_pipeline = [
            {"$group": {
                "_id": "$warehouse",
                "total_quantity": {"$sum": "$quantity"},
                "total_reserved": {"$sum": "$reserved"},
                "product_count": {"$sum": 1}
            }},
            {"$project": {
                "warehouse": "$_id",
                "total_quantity": 1,
                "total_reserved": 1,
                "available": {"$subtract": ["$total_quantity", "$total_reserved"]},
                "product_count": 1
            }},
            {"$sort": {"warehouse": 1}}
        ]
        
        warehouses = list(db.inventory.aggregate(warehouse_pipeline))
        
        return jsonify({
            "success": True,
            "data": {
                "low_stock": serialize_doc(low_stock),
                "warehouse_summary": serialize_doc(warehouses)
            }
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route('/api/inventory/sync', methods=['POST'])
def sync_inventory():
    """Simulate inventory sync from suppliers (Complex Upsert demo)."""
    db = get_db()
    count = request.json.get('count', 100) if request.json else 100
    
    try:
        suppliers = [f"SUP_{i:04d}" for i in range(50)]
        categories = ["CAT_001", "CAT_002", "CAT_003", "CAT_004", "CAT_005"]
        warehouses = ["WH_EAST", "WH_WEST", "WH_CENTRAL", "WH_SOUTH"]
        
        stats = {
            "new_products": 0,
            "updated_products": 0,
            "inventory_created": 0,
            "inventory_updated": 0,
            "errors": 0
        }
        
        for i in range(count):
            try:
                # Mix of existing and new products
                if random.random() < 0.7:
                    product_id = f"PROD_{random.randint(0, 199):06d}"
                else:
                    product_id = f"PROD_NEW_{random.randint(1000, 9999):06d}"
                
                # Upsert product
                product_result = db.products.update_one(
                    {"product_id": product_id},
                    {
                        "$set": {
                            "name": f"Product {random_string(8)}",
                            "supplier_id": random.choice(suppliers),
                            "category_id": random.choice(categories),
                            "cost": round(random.uniform(5, 200), 2),
                            "last_supplier_sync": datetime.now(timezone.utc)
                        },
                        "$min": {"price": round(random.uniform(10, 400), 2)},
                        "$setOnInsert": {
                            "product_id": product_id,
                            "created_at": datetime.now(timezone.utc),
                            "active": True
                        }
                    },
                    upsert=True
                )
                
                if product_result.upserted_id:
                    stats["new_products"] += 1
                elif product_result.modified_count > 0:
                    stats["updated_products"] += 1
                
                # Upsert inventory
                warehouse = random.choice(warehouses)
                inventory_result = db.inventory.update_one(
                    {"product_id": product_id, "warehouse": warehouse},
                    {
                        "$set": {"last_restocked": datetime.now(timezone.utc)},
                        "$inc": {"quantity": random.randint(10, 100)},
                        "$setOnInsert": {
                            "product_id": product_id,
                            "warehouse": warehouse,
                            "reserved": 0,
                            "reorder_point": random.randint(10, 50)
                        }
                    },
                    upsert=True
                )
                
                if inventory_result.upserted_id:
                    stats["inventory_created"] += 1
                elif inventory_result.modified_count > 0:
                    stats["inventory_updated"] += 1
                    
            except Exception as e:
                stats["errors"] += 1
        
        return jsonify({
            "success": True,
            "data": stats
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route('/api/setup', methods=['POST'])
def setup_data():
    """Initialize sample data."""
    db = get_db()
    
    try:
        num_customers = request.json.get('customers', 500) if request.json else 500
        num_products = request.json.get('products', 200) if request.json else 200
        num_orders = request.json.get('orders', 1000) if request.json else 1000
        
        # Drop existing collections
        for coll in ['customers', 'products', 'orders', 'order_items', 
                     'inventory', 'reviews', 'suppliers', 'categories']:
            db[coll].drop()
        
        # Categories
        categories = [
            {"category_id": "CAT_001", "name": "Electronics", "parent": None},
            {"category_id": "CAT_002", "name": "Computers", "parent": "CAT_001"},
            {"category_id": "CAT_003", "name": "Phones", "parent": "CAT_001"},
            {"category_id": "CAT_004", "name": "Clothing", "parent": None},
            {"category_id": "CAT_005", "name": "Men", "parent": "CAT_004"},
            {"category_id": "CAT_006", "name": "Women", "parent": "CAT_004"},
            {"category_id": "CAT_007", "name": "Home & Garden", "parent": None},
            {"category_id": "CAT_008", "name": "Kitchen", "parent": "CAT_007"},
        ]
        db.categories.insert_many(categories)
        db.categories.create_index("category_id", unique=True)
        
        # Suppliers
        suppliers = [
            {"supplier_id": f"SUP_{i:04d}", "name": f"Supplier {i}",
             "contact_email": f"supplier{i}@example.com",
             "rating": round(random.uniform(3.0, 5.0), 1),
             "active": random.choice([True, True, True, False])}
            for i in range(50)
        ]
        db.suppliers.insert_many(suppliers)
        db.suppliers.create_index("supplier_id", unique=True)
        
        # Customers
        tiers = ["bronze", "silver", "gold", "platinum"]
        customers = [
            {"customer_id": f"CUST_{i:06d}",
             "email": f"customer{i}@example.com",
             "name": f"Customer {i}",
             "tier": random.choice(tiers),
             "loyalty_points": random.randint(0, 10000),
             "created_at": datetime.now(timezone.utc) - timedelta(days=random.randint(1, 365)),
             "address": {
                 "city": random.choice(["New York", "Los Angeles", "Chicago", "Houston", "Phoenix"]),
                 "state": random.choice(["NY", "CA", "IL", "TX", "AZ"]),
                 "zip": f"{random.randint(10000, 99999)}"
             }}
            for i in range(num_customers)
        ]
        db.customers.insert_many(customers)
        db.customers.create_index("customer_id", unique=True)
        
        # Products
        category_ids = [c["category_id"] for c in categories]
        supplier_ids = [s["supplier_id"] for s in suppliers]
        products = [
            {"product_id": f"PROD_{i:06d}",
             "name": f"Product {random_string(8)}",
             "description": f"Description for product {i}",
             "category_id": random.choice(category_ids),
             "supplier_id": random.choice(supplier_ids),
             "price": round(random.uniform(9.99, 999.99), 2),
             "cost": round(random.uniform(5.00, 500.00), 2),
             "active": random.choice([True, True, True, True, False]),
             "created_at": datetime.now(timezone.utc) - timedelta(days=random.randint(1, 180))}
            for i in range(num_products)
        ]
        db.products.insert_many(products)
        db.products.create_index("product_id", unique=True)
        
        # Inventory
        warehouses = ["WH_EAST", "WH_WEST", "WH_CENTRAL", "WH_SOUTH"]
        inventory = []
        for i in range(num_products):
            for wh in random.sample(warehouses, random.randint(1, 3)):
                inventory.append({
                    "product_id": f"PROD_{i:06d}",
                    "warehouse": wh,
                    "quantity": random.randint(0, 500),
                    "reserved": random.randint(0, 50),
                    "reorder_point": random.randint(10, 50),
                    "last_restocked": datetime.now(timezone.utc) - timedelta(days=random.randint(1, 30))
                })
        db.inventory.insert_many(inventory)
        db.inventory.create_index([("product_id", 1), ("warehouse", 1)], unique=True)
        
        # Orders and Order Items
        customer_ids = [c["customer_id"] for c in customers]
        product_ids = [p["product_id"] for p in products]
        statuses = ["pending", "confirmed", "shipped", "delivered", "cancelled"]
        
        orders = []
        order_items = []
        for i in range(num_orders):
            order_id = f"ORD_{i:08d}"
            order_date = datetime.now(timezone.utc) - timedelta(days=random.randint(0, 90))
            orders.append({
                "order_id": order_id,
                "customer_id": random.choice(customer_ids),
                "status": random.choice(statuses),
                "created_at": order_date,
                "updated_at": order_date + timedelta(hours=random.randint(1, 48))
            })
            for j in range(random.randint(1, 5)):
                order_items.append({
                    "order_id": order_id,
                    "product_id": random.choice(product_ids),
                    "quantity": random.randint(1, 5),
                    "unit_price": round(random.uniform(9.99, 299.99), 2),
                    "discount": round(random.uniform(0, 0.2), 2)
                })
        
        db.orders.insert_many(orders)
        db.order_items.insert_many(order_items)
        db.orders.create_index("order_id", unique=True)
        db.orders.create_index("customer_id")
        db.order_items.create_index("order_id")
        
        # Reviews
        reviews = [
            {"review_id": f"REV_{i:08d}",
             "product_id": random.choice(product_ids),
             "customer_id": random.choice(customer_ids),
             "rating": random.randint(1, 5),
             "title": f"Review {i}",
             "text": f"This is review text for review {i}",
             "created_at": datetime.now(timezone.utc) - timedelta(days=random.randint(0, 60)),
             "verified_purchase": random.choice([True, True, False])}
            for i in range(num_orders // 2)
        ]
        db.reviews.insert_many(reviews)
        
        # Add some intentional data quality issues
        orphan_items = [
            {"order_id": "ORD_00000001", "product_id": f"PROD_DELETED_{i:04d}",
             "quantity": 1, "unit_price": 99.99, "discount": 0}
            for i in range(25)
        ]
        db.order_items.insert_many(orphan_items)
        
        orphan_orders = [
            {"order_id": f"ORD_ORPHAN_{i:04d}", "customer_id": f"CUST_DELETED_{i:04d}",
             "status": "pending", "created_at": datetime.now(timezone.utc)}
            for i in range(15)
        ]
        db.orders.insert_many(orphan_orders)
        
        orphan_inventory = [
            {"product_id": f"PROD_REMOVED_{i:04d}", "warehouse": "WH_EAST",
             "quantity": random.randint(10, 100), "reserved": 0}
            for i in range(10)
        ]
        db.inventory.insert_many(orphan_inventory)
        
        orphan_reviews = [
            {"review_id": f"REV_ORPHAN_{i:04d}", "product_id": f"PROD_GONE_{i:04d}",
             "customer_id": "CUST_000001", "rating": 5, "title": "Great!",
             "created_at": datetime.now(timezone.utc)}
            for i in range(20)
        ]
        db.reviews.insert_many(orphan_reviews)
        
        return jsonify({
            "success": True,
            "data": {
                "customers": num_customers,
                "products": num_products,
                "orders": num_orders,
                "order_items": len(order_items),
                "inventory_records": len(inventory),
                "reviews": len(reviews),
                "data_quality_issues_added": 70
            }
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


# ============================================================================
# API ROUTES - Live Data Feed
# ============================================================================

@app.route('/api/stream/stats')
def get_stream_stats():
    """Get data generator statistics."""
    global data_generator
    
    db = get_db()
    
    try:
        # Get generator stats
        generator_stats = data_generator.get_stats() if data_generator else {
            'orders_generated': 0,
            'reviews_generated': 0,
            'social_comments_generated': 0,
            'items_per_second': 0,
            'start_time': None,
            'running': False
        }
        
        # Get total counts from database
        total_orders = db.orders.count_documents({})
        total_reviews = db.reviews.count_documents({})
        total_social = db.social_comments.count_documents({})
        
        # Get recent activity (last minute)
        one_minute_ago = datetime.now(timezone.utc) - timedelta(minutes=1)
        recent_orders = db.orders.count_documents({'created_at': {'$gte': one_minute_ago}})
        recent_social = db.social_comments.count_documents({'created_at': {'$gte': one_minute_ago}})
        
        return jsonify({
            "success": True,
            "data": {
                "generator": {
                    "running": data_generator.running if data_generator else False,
                    "items_per_second": generator_stats.get('items_per_second', 0),
                    "start_time": generator_stats.get('start_time'),
                    "orders_generated": generator_stats.get('orders_generated', 0),
                    "reviews_generated": generator_stats.get('reviews_generated', 0),
                    "social_generated": generator_stats.get('social_comments_generated', 0)
                },
                "totals": {
                    "orders": total_orders,
                    "reviews": total_reviews,
                    "social_comments": total_social
                },
                "recent_activity": {
                    "orders_last_minute": recent_orders,
                    "social_last_minute": recent_social
                }
            }
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route('/api/social-feed')
def get_social_feed():
    """Get social media comments feed."""
    db = get_db()
    
    limit = request.args.get('limit', 50, type=int)
    sentiment = request.args.get('sentiment', None)
    source = request.args.get('source', None)
    
    try:
        # Build match stage
        match_stage = {}
        if sentiment:
            match_stage['sentiment'] = sentiment
        if source:
            match_stage['source'] = source
        
        # Get recent comments
        pipeline = [
            {"$match": match_stage} if match_stage else {"$match": {}},
            {"$sort": {"created_at": -1}},
            {"$limit": limit},
            {"$lookup": {
                "from": "products",
                "localField": "product_id",
                "foreignField": "product_id",
                "as": "product"
            }},
            {"$unwind": {"path": "$product", "preserveNullAndEmptyArrays": True}},
            {"$project": {
                "comment_id": 1,
                "source": 1,
                "username": 1,
                "text": 1,
                "sentiment": 1,
                "sentiment_score": 1,
                "hashtags": 1,
                "mentions": 1,
                "likes": 1,
                "shares": 1,
                "created_at": 1,
                "product_name": {"$ifNull": ["$product.name", None]}
            }}
        ]
        
        comments = list(db.social_comments.aggregate(pipeline))
        
        # Get sentiment distribution
        sentiment_pipeline = [
            {"$group": {"_id": "$sentiment", "count": {"$sum": 1}}},
            {"$sort": {"count": -1}}
        ]
        sentiment_dist = list(db.social_comments.aggregate(sentiment_pipeline))
        
        # Get source distribution
        source_pipeline = [
            {"$group": {"_id": "$source", "count": {"$sum": 1}}},
            {"$sort": {"count": -1}}
        ]
        source_dist = list(db.social_comments.aggregate(source_pipeline))
        
        return jsonify({
            "success": True,
            "data": {
                "comments": serialize_doc(comments),
                "sentiment_distribution": sentiment_dist,
                "source_distribution": source_dist,
                "total_count": db.social_comments.count_documents({})
            }
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


# ============================================================================
# MAIN
# ============================================================================

if __name__ == '__main__':
    print("🚀 Starting E-commerce Dashboard Server...")
    print("   Dashboard: http://localhost:5000")
    print("   API Docs:  http://localhost:5000/api/overview")
    
    # Initialize server (seed data and start generator)
    initialize_server()
    
    # Handle signals for graceful shutdown
    def signal_handler(signum, frame):
        shutdown_handler()
        exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Run server (debug=False to avoid double initialization)
    app.run(host='0.0.0.0', port=5000, debug=False)
