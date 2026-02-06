#!/usr/bin/env python3
"""
Real-time Data Generator for E-commerce Demo
=============================================
Continuously generates orders, reviews, and social media comments
to stress-test DocumentDB under pressure.
"""

import os
import random
import string
import threading
import time
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Optional, Callable
from pymongo import MongoClient
from pymongo.database import Database

# ============================================================================
# CONFIGURATION
# ============================================================================

GENERATOR_RATE = int(os.environ.get('GENERATOR_RATE', 5))  # items per second
BATCH_SIZE = int(os.environ.get('GENERATOR_BATCH_SIZE', 10))  # items per batch

# Social media templates for realistic text generation
POSITIVE_PHRASES = [
    "Absolutely love this {product}! Best purchase ever! 🎉",
    "Amazing quality on the {product}. Highly recommend! ⭐⭐⭐⭐⭐",
    "Just got my {product} and it's perfect! #bestbuy",
    "This {product} exceeded all my expectations! @{brand} you nailed it!",
    "5 stars for this {product}! Will definitely buy again 💯",
    "The {product} is incredible. Fast shipping too! #happy",
    "Can't believe how good this {product} is for the price!",
    "My new favorite {product}! Thanks @{brand} 🙌",
    "Finally found the perfect {product}! So happy! #love",
    "This {product} is a game changer! Everyone needs one!",
]

NEUTRAL_PHRASES = [
    "Got the {product} today. Looks okay so far.",
    "The {product} arrived. Will test it out this week.",
    "Ordered a {product} from @{brand}. Waiting to see how it holds up.",
    "New {product} unboxing. First impressions are decent.",
    "Just another {product} review coming soon #review",
    "The {product} does what it says. Nothing more, nothing less.",
    "Received my {product}. Standard quality I guess.",
    "Testing out the new {product}. Results pending.",
    "Added a {product} to my collection. We'll see.",
    "The {product} is here. Time to put it through its paces.",
]

NEGATIVE_PHRASES = [
    "Disappointed with this {product}. Not worth the money 😞",
    "The {product} broke after one week. @{brand} fix this!",
    "Worst {product} I've ever bought. Avoid! #fail",
    "Can't believe how bad this {product} is. Want a refund!",
    "The {product} quality is terrible. Very unhappy customer.",
    "Don't buy this {product}! Complete waste of money 👎",
    "@{brand} your {product} is garbage. Never again!",
    "Returning this {product} ASAP. Total disappointment.",
    "The {product} doesn't work as advertised. #disappointed",
    "Regret buying this {product}. Save your money!",
]

SOCIAL_SOURCES = ['twitter', 'instagram', 'facebook', 'tiktok', 'reddit']
BRANDS = ['TechGear', 'StyleCo', 'HomeEssentials', 'FitLife', 'GadgetPro', 'EcoWare']
PRODUCT_TYPES = ['headphones', 'jacket', 'blender', 'watch', 'laptop', 'chair', 'shoes', 'camera', 'speaker', 'backpack']
HASHTAGS = ['trending', 'musthave', 'newproduct', 'review', 'unboxing', 'shopping', 'deal', 'quality', 'lifestyle']
ORDER_STATUSES = ['pending', 'confirmed', 'shipped', 'delivered']

# Counter for unique IDs within the generator session
_id_counter = 0
_id_lock = threading.Lock()


def random_string(length: int = 8) -> str:
    return ''.join(random.choices(string.ascii_letters, k=length))


def random_id(prefix: str = '') -> str:
    """Generate a unique ID using timestamp + counter + random component."""
    global _id_counter
    with _id_lock:
        _id_counter += 1
        counter = _id_counter
    # Use microsecond timestamp + counter + small random for uniqueness
    ts = int(time.time() * 1000) % 10000000  # Last 7 digits of ms timestamp
    return f"{prefix}{ts}_{counter}_{random.randint(0, 999):03d}"


class DataGenerator:
    """Background data generator for stress testing DocumentDB."""
    
    def __init__(self, db: Database, rate: int = GENERATOR_RATE):
        self.db = db
        self.rate = rate
        self.running = False
        self.thread: Optional[threading.Thread] = None
        self.stats = {
            'orders_generated': 0,
            'reviews_generated': 0,
            'social_comments_generated': 0,
            'start_time': None,
            'last_batch_time': None,
            'items_per_second': 0.0
        }
        self._lock = threading.Lock()
        
        # Cache some data for faster generation
        self._customer_ids: List[str] = []
        self._product_ids: List[str] = []
        self._product_names: Dict[str, str] = {}
        
    def _refresh_cache(self):
        """Refresh cached IDs from database."""
        try:
            customers = list(self.db.customers.find({}, {'customer_id': 1}).limit(500))
            self._customer_ids = [c['customer_id'] for c in customers]
            
            products = list(self.db.products.find({}, {'product_id': 1, 'name': 1}).limit(500))
            self._product_ids = [p['product_id'] for p in products]
            self._product_names = {p['product_id']: p.get('name', 'Product') for p in products}
        except Exception as e:
            print(f"[Generator] Cache refresh error: {e}")
    
    def _generate_order(self) -> dict:
        """Generate a random order with items."""
        if not self._customer_ids or not self._product_ids:
            return None
            
        customer_id = random.choice(self._customer_ids)
        order_id = f"ORD_{random_id()}"
        num_items = random.randint(1, 5)
        
        items = []
        for _ in range(num_items):
            product_id = random.choice(self._product_ids)
            items.append({
                'order_id': order_id,
                'product_id': product_id,
                'quantity': random.randint(1, 3),
                'unit_price': round(random.uniform(10, 500), 2),
                'discount': random.choice([0, 0, 0, 0.1, 0.15, 0.2])
            })
        
        order = {
            'order_id': order_id,
            'customer_id': customer_id,
            'status': random.choice(ORDER_STATUSES),
            'created_at': datetime.now(timezone.utc),
            'updated_at': datetime.now(timezone.utc)
        }
        
        return {'order': order, 'items': items}
    
    def _generate_review(self) -> dict:
        """Generate a random product review."""
        if not self._customer_ids or not self._product_ids:
            return None
            
        rating = random.choices([1, 2, 3, 4, 5], weights=[5, 10, 20, 30, 35])[0]
        
        if rating >= 4:
            text = random.choice(POSITIVE_PHRASES)
        elif rating >= 3:
            text = random.choice(NEUTRAL_PHRASES)
        else:
            text = random.choice(NEGATIVE_PHRASES)
        
        product_id = random.choice(self._product_ids)
        product_name = self._product_names.get(product_id, random.choice(PRODUCT_TYPES))
        brand = random.choice(BRANDS)
        
        text = text.format(product=product_name, brand=brand)
        
        return {
            'review_id': f"REV_{random_id()}",
            'product_id': product_id,
            'customer_id': random.choice(self._customer_ids),
            'rating': rating,
            'title': f"{'Great' if rating >= 4 else 'Okay' if rating >= 3 else 'Poor'} {product_name}",
            'text': text,
            'verified_purchase': random.choice([True, True, True, False]),
            'created_at': datetime.now(timezone.utc)
        }
    
    def _generate_social_comment(self) -> dict:
        """Generate a random social media comment."""
        if not self._product_ids:
            return None
            
        # Sentiment distribution: 50% positive, 30% neutral, 20% negative
        sentiment = random.choices(['positive', 'neutral', 'negative'], weights=[50, 30, 20])[0]
        
        if sentiment == 'positive':
            text = random.choice(POSITIVE_PHRASES)
        elif sentiment == 'neutral':
            text = random.choice(NEUTRAL_PHRASES)
        else:
            text = random.choice(NEGATIVE_PHRASES)
        
        product_id = random.choice(self._product_ids)
        product_name = self._product_names.get(product_id, random.choice(PRODUCT_TYPES))
        brand = random.choice(BRANDS)
        
        text = text.format(product=product_name, brand=brand)
        
        # Extract hashtags from text and add some random ones
        hashtags = [tag for tag in text.split() if tag.startswith('#')]
        hashtags.extend([f"#{random.choice(HASHTAGS)}" for _ in range(random.randint(0, 3))])
        
        # Extract mentions from text
        mentions = [m for m in text.split() if m.startswith('@')]
        
        source = random.choice(SOCIAL_SOURCES)
        
        return {
            'comment_id': f"SOC_{random_id()}",
            'source': source,
            'username': f"user_{random_string(6).lower()}",
            'text': text,
            'sentiment': sentiment,
            'sentiment_score': {
                'positive': random.uniform(0.7, 1.0) if sentiment == 'positive' else random.uniform(0.0, 0.3),
                'negative': random.uniform(0.7, 1.0) if sentiment == 'negative' else random.uniform(0.0, 0.3),
                'neutral': random.uniform(0.7, 1.0) if sentiment == 'neutral' else random.uniform(0.0, 0.3)
            },
            'hashtags': list(set(hashtags)),
            'mentions': list(set(mentions)),
            'product_id': product_id if random.random() > 0.3 else None,  # 70% have product link
            'likes': random.randint(0, 1000),
            'shares': random.randint(0, 100),
            'created_at': datetime.now(timezone.utc)
        }
    
    def _generator_loop(self):
        """Main generator loop running in background thread."""
        print(f"[Generator] Started at {self.rate} items/sec")
        self._refresh_cache()
        
        interval = 1.0 / max(self.rate, 1)
        last_stats_time = time.time()
        items_since_last_stats = 0
        
        while self.running:
            try:
                batch_start = time.time()
                
                # Generate mixed batch of data
                orders_batch = []
                order_items_batch = []
                reviews_batch = []
                social_batch = []
                
                for _ in range(BATCH_SIZE):
                    if not self.running:
                        break
                    
                    # Random distribution: 20% orders, 30% reviews, 50% social
                    rand = random.random()
                    
                    if rand < 0.2:
                        order_data = self._generate_order()
                        if order_data:
                            orders_batch.append(order_data['order'])
                            order_items_batch.extend(order_data['items'])
                    elif rand < 0.5:
                        review = self._generate_review()
                        if review:
                            reviews_batch.append(review)
                    else:
                        comment = self._generate_social_comment()
                        if comment:
                            social_batch.append(comment)
                
                # Bulk insert
                if orders_batch:
                    self.db.orders.insert_many(orders_batch, ordered=False)
                if order_items_batch:
                    self.db.order_items.insert_many(order_items_batch, ordered=False)
                if reviews_batch:
                    self.db.reviews.insert_many(reviews_batch, ordered=False)
                if social_batch:
                    self.db.social_comments.insert_many(social_batch, ordered=False)
                
                # Update stats
                with self._lock:
                    self.stats['orders_generated'] += len(orders_batch)
                    self.stats['reviews_generated'] += len(reviews_batch)
                    self.stats['social_comments_generated'] += len(social_batch)
                    self.stats['last_batch_time'] = datetime.now(timezone.utc).isoformat()
                
                items_since_last_stats += len(orders_batch) + len(reviews_batch) + len(social_batch)
                
                # Update items/sec every second
                now = time.time()
                if now - last_stats_time >= 1.0:
                    with self._lock:
                        self.stats['items_per_second'] = items_since_last_stats / (now - last_stats_time)
                    items_since_last_stats = 0
                    last_stats_time = now
                
                # Sleep to maintain rate
                elapsed = time.time() - batch_start
                sleep_time = max(0, (BATCH_SIZE * interval) - elapsed)
                if sleep_time > 0:
                    time.sleep(sleep_time)
                    
            except Exception as e:
                print(f"[Generator] Error: {e}")
                time.sleep(1)  # Back off on error
                self._refresh_cache()  # Try refreshing cache
        
        print("[Generator] Stopped")
    
    def start(self):
        """Start the generator in a background thread."""
        if self.running:
            return
        
        self.running = True
        self.stats['start_time'] = datetime.now(timezone.utc).isoformat()
        self.stats['orders_generated'] = 0
        self.stats['reviews_generated'] = 0
        self.stats['social_comments_generated'] = 0
        
        self.thread = threading.Thread(target=self._generator_loop, daemon=True)
        self.thread.start()
    
    def stop(self):
        """Stop the generator."""
        self.running = False
        if self.thread:
            self.thread.join(timeout=5)
            self.thread = None
    
    def get_stats(self) -> dict:
        """Get current generator statistics."""
        with self._lock:
            return dict(self.stats)


def seed_initial_data(db: Database, small: bool = True):
    """
    Seed initial demo data into the database.
    
    Args:
        db: MongoDB database instance
        small: If True, create smaller dataset for faster startup
    """
    print("[Seed] Creating initial demo data...")
    
    # Configuration
    if small:
        num_customers = 100
        num_products = 50
        num_orders = 200
        num_social = 100
    else:
        num_customers = 500
        num_products = 200
        num_orders = 1000
        num_social = 500
    
    # Create collections (drop if exist)
    collections = ['customers', 'products', 'orders', 'order_items', 
                   'reviews', 'social_comments', 'categories', 'suppliers', 'inventory']
    for coll in collections:
        db[coll].drop()
    
    # Categories
    categories = [
        {'category_id': 'CAT_001', 'name': 'Electronics', 'parent': None},
        {'category_id': 'CAT_002', 'name': 'Clothing', 'parent': None},
        {'category_id': 'CAT_003', 'name': 'Home & Garden', 'parent': None},
        {'category_id': 'CAT_004', 'name': 'Sports', 'parent': None},
        {'category_id': 'CAT_005', 'name': 'Phones', 'parent': 'CAT_001'},
        {'category_id': 'CAT_006', 'name': 'Computers', 'parent': 'CAT_001'},
        {'category_id': 'CAT_007', 'name': 'Men', 'parent': 'CAT_002'},
        {'category_id': 'CAT_008', 'name': 'Women', 'parent': 'CAT_002'},
    ]
    db.categories.insert_many(categories)
    
    # Suppliers
    suppliers = []
    for i in range(20):
        suppliers.append({
            'supplier_id': f'SUP_{i:03d}',
            'name': f'Supplier {random_string(6)}',
            'contact_email': f'contact@supplier{i}.com',
            'rating': round(random.uniform(3.0, 5.0), 1),
            'active': random.random() > 0.1
        })
    db.suppliers.insert_many(suppliers)
    
    # Customers
    tiers = ['bronze', 'silver', 'gold', 'platinum']
    customers = []
    for i in range(num_customers):
        customers.append({
            'customer_id': f'CUST_{i:06d}',
            'name': f'{random_string(6)} {random_string(8)}',
            'email': f'user{i}@example.com',
            'tier': random.choice(tiers),
            'loyalty_points': random.randint(0, 10000),
            'address': {
                'city': random.choice(['New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix']),
                'country': 'USA'
            },
            'created_at': datetime.now(timezone.utc) - timedelta(days=random.randint(1, 365))
        })
    db.customers.insert_many(customers)
    customer_ids = [c['customer_id'] for c in customers]
    
    # Products
    category_ids = [c['category_id'] for c in categories]
    supplier_ids = [s['supplier_id'] for s in suppliers]
    products = []
    for i in range(num_products):
        products.append({
            'product_id': f'PROD_{i:06d}',
            'name': f'Product {random_string(8)}',
            'description': f'Description for product {i}',
            'category_id': random.choice(category_ids),
            'supplier_id': random.choice(supplier_ids),
            'price': round(random.uniform(10, 1000), 2),
            'cost': round(random.uniform(5, 500), 2),
            'active': random.random() > 0.05
        })
    db.products.insert_many(products)
    product_ids = [p['product_id'] for p in products]
    product_names = {p['product_id']: p['name'] for p in products}
    
    # Inventory
    warehouses = ['WH_EAST', 'WH_WEST', 'WH_CENTRAL', 'WH_SOUTH']
    inventory = []
    for product_id in product_ids:
        for wh in random.sample(warehouses, random.randint(1, 3)):
            inventory.append({
                'product_id': product_id,
                'warehouse_id': wh,
                'warehouse': wh,
                'quantity': random.randint(0, 200),
                'reserved': random.randint(0, 50),
                'reorder_point': random.randint(10, 50),
                'last_restocked': datetime.now(timezone.utc) - timedelta(days=random.randint(1, 30))
            })
    db.inventory.insert_many(inventory)
    
    # Orders and Order Items
    orders = []
    order_items = []
    reviews = []
    
    for i in range(num_orders):
        order_id = f'ORD_{i:06d}'
        customer_id = random.choice(customer_ids)
        order_date = datetime.now(timezone.utc) - timedelta(days=random.randint(0, 90))
        
        orders.append({
            'order_id': order_id,
            'customer_id': customer_id,
            'status': random.choice(['pending', 'confirmed', 'shipped', 'delivered', 'cancelled']),
            'created_at': order_date,
            'updated_at': order_date + timedelta(hours=random.randint(1, 48))
        })
        
        # Order items
        num_items = random.randint(1, 5)
        for _ in range(num_items):
            product_id = random.choice(product_ids)
            order_items.append({
                'order_id': order_id,
                'product_id': product_id,
                'quantity': random.randint(1, 5),
                'unit_price': round(random.uniform(10, 500), 2),
                'discount': random.choice([0, 0, 0, 0.1, 0.15, 0.2])
            })
        
        # Some orders get reviews
        if random.random() > 0.5:
            rating = random.choices([1, 2, 3, 4, 5], weights=[5, 10, 20, 30, 35])[0]
            product_id = random.choice(product_ids)
            reviews.append({
                'review_id': f'REV_{i:06d}',
                'product_id': product_id,
                'customer_id': customer_id,
                'rating': rating,
                'title': f"{'Great' if rating >= 4 else 'Okay' if rating >= 3 else 'Poor'} product",
                'text': random.choice(POSITIVE_PHRASES if rating >= 4 else NEUTRAL_PHRASES if rating >= 3 else NEGATIVE_PHRASES).format(
                    product=product_names.get(product_id, 'product'),
                    brand=random.choice(BRANDS)
                ),
                'verified_purchase': True,
                'created_at': order_date + timedelta(days=random.randint(1, 14))
            })
    
    db.orders.insert_many(orders)
    db.order_items.insert_many(order_items)
    if reviews:
        db.reviews.insert_many(reviews)
    
    # Initial social comments
    social_comments = []
    for i in range(num_social):
        sentiment = random.choices(['positive', 'neutral', 'negative'], weights=[50, 30, 20])[0]
        
        if sentiment == 'positive':
            text = random.choice(POSITIVE_PHRASES)
        elif sentiment == 'neutral':
            text = random.choice(NEUTRAL_PHRASES)
        else:
            text = random.choice(NEGATIVE_PHRASES)
        
        product_id = random.choice(product_ids)
        text = text.format(
            product=product_names.get(product_id, random.choice(PRODUCT_TYPES)),
            brand=random.choice(BRANDS)
        )
        
        hashtags = [tag for tag in text.split() if tag.startswith('#')]
        mentions = [m for m in text.split() if m.startswith('@')]
        
        social_comments.append({
            'comment_id': f'SOC_{i:06d}',
            'source': random.choice(SOCIAL_SOURCES),
            'username': f'user_{random_string(6).lower()}',
            'text': text,
            'sentiment': sentiment,
            'sentiment_score': {
                'positive': random.uniform(0.7, 1.0) if sentiment == 'positive' else random.uniform(0.0, 0.3),
                'negative': random.uniform(0.7, 1.0) if sentiment == 'negative' else random.uniform(0.0, 0.3),
                'neutral': random.uniform(0.7, 1.0) if sentiment == 'neutral' else random.uniform(0.0, 0.3)
            },
            'hashtags': list(set(hashtags)),
            'mentions': list(set(mentions)),
            'product_id': product_id if random.random() > 0.3 else None,
            'likes': random.randint(0, 1000),
            'shares': random.randint(0, 100),
            'created_at': datetime.now(timezone.utc) - timedelta(minutes=random.randint(0, 60*24))
        })
    
    db.social_comments.insert_many(social_comments)
    
    # Create indexes
    db.customers.create_index('customer_id', unique=True)
    db.products.create_index('product_id', unique=True)
    db.orders.create_index('order_id', unique=True)
    db.orders.create_index('customer_id')
    db.orders.create_index('created_at')
    db.order_items.create_index('order_id')
    db.order_items.create_index('product_id')
    db.reviews.create_index('product_id')
    db.reviews.create_index('customer_id')
    db.social_comments.create_index('created_at')
    db.social_comments.create_index('sentiment')
    db.social_comments.create_index('source')
    db.inventory.create_index([('product_id', 1), ('warehouse_id', 1)])
    
    print(f"[Seed] Created: {num_customers} customers, {num_products} products, "
          f"{num_orders} orders, {len(reviews)} reviews, {num_social} social comments")


def cleanup_data(db: Database):
    """Remove all data from the database."""
    print("[Cleanup] Removing all data...")
    collections = ['customers', 'products', 'orders', 'order_items', 
                   'reviews', 'social_comments', 'categories', 'suppliers', 'inventory']
    
    dropped = 0
    for coll in collections:
        try:
            db[coll].drop()
            dropped += 1
        except Exception as e:
            # Silently ignore "client closed" errors during shutdown
            if "MongoClient" not in str(e):
                print(f"[Cleanup] Error dropping {coll}: {e}")
    
    print(f"[Cleanup] Done (dropped {dropped} collections)")
