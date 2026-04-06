#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

banner 1 "Loading Sample Data to Explore DocumentDB"
ensure_main_container || { echo "SKIP: container unavailable"; exit 1; }

tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT

echo "--- Step 1: Download sample data from GitHub ---"
for f in 01-users.js 02-products.js 03-orders.js 04-analytics.js; do
    curl -sLo "$tmpdir/$f" \
        "https://raw.githubusercontent.com/documentdb/documentdb/main/sample-data/$f"
    echo "  Downloaded $f ($(wc -c < "$tmpdir/$f") bytes)"
done
echo ""

echo "--- Step 2: Load each file via mongosh ---"
for f in "$tmpdir"/*.js; do
    echo "  Loading $(basename "$f") ..."
    mongosh "$CONN_URI" --quiet --file "$f" 2>&1 || true
    sleep 1
done
echo ""

echo "--- Step 3: Verify loaded data ---"
mongosh "$CONN_URI" --quiet --eval '
    use("sampledb");
    var colls = db.getCollectionNames().filter(c => !c.startsWith("system."));
    print("Collections in sampledb: " + JSON.stringify(colls));
    colls.forEach(function(c) {
        print("  " + c + ": " + db.getCollection(c).countDocuments() + " documents");
    });
' 2>&1 || true
echo ""

QUERIES_START=$(date +%s%N)

echo "--- Step 4: Single-collection queries ---"

t0=$(date +%s%N)
mongosh "$CONN_URI" --quiet --eval '
    use("sampledb");
    print("Query: Users in San Francisco");
    db.users.find({"city": "San Francisco"}).toArray().forEach(function(u) {
        print("  " + u.username + " — " + u.email);
    });
' 2>&1 || true
echo "  ⏱  $(( ($(date +%s%N) - t0) / 1000000 )) ms"
echo ""

t0=$(date +%s%N)
mongosh "$CONN_URI" --quiet --eval '
    use("sampledb");
    print("Query: Products under $100 sorted by rating");
    db.products.find({price: {$lt: 100}}).sort({"ratings.average": -1}).toArray().forEach(function(p) {
        print("  " + p.name + " — $" + p.price + " (rating: " + p.ratings.average + ")");
    });
' 2>&1 || true
echo "  ⏱  $(( ($(date +%s%N) - t0) / 1000000 )) ms"
echo ""

t0=$(date +%s%N)
mongosh "$CONN_URI" --quiet --eval '
    use("sampledb");
    print("Query: Orders with status shipped or delivered");
    db.orders.find({status: {$in: ["shipped", "delivered"]}}).toArray().forEach(function(o) {
        print("  " + o.orderNumber + " — " + o.status + " — $" + o.orderSummary.total);
    });
' 2>&1 || true
echo "  ⏱  $(( ($(date +%s%N) - t0) / 1000000 )) ms"
echo ""

echo '--- Step 5: Cross-collection queries ($lookup joins) ---'

t0=$(date +%s%N)
mongosh "$CONN_URI" --quiet --eval '
    use("sampledb");
    print("Query: Customer order history (orders JOIN users)");
    print("  Join orders with users to show full customer name and their order totals.\n");
    db.orders.aggregate([
        { $lookup: {
            from: "users",
            localField: "userId",
            foreignField: "_id",
            as: "customer"
        }},
        { $unwind: "$customer" },
        { $project: {
            orderNumber: 1,
            customerName: { $concat: ["$customer.firstName", " ", "$customer.lastName"] },
            customerCity: "$customer.city",
            total: "$orderSummary.total",
            status: 1,
            orderDate: 1
        }},
        { $sort: { orderDate: -1 } }
    ]).toArray().forEach(function(o) {
        print("  " + o.orderNumber + " | " + o.customerName + " (" + o.customerCity + ") | $" + o.total + " | " + o.status);
    });
' 2>&1 || true
echo "  ⏱  $(( ($(date +%s%N) - t0) / 1000000 )) ms"
echo ""

t0=$(date +%s%N)
mongosh "$CONN_URI" --quiet --eval '
    use("sampledb");
    print("Query: Order line items enriched with product details (orders JOIN products)");
    print("  Unwind order items and look up full product info including category and stock.\n");
    db.orders.aggregate([
        { $unwind: "$items" },
        { $lookup: {
            from: "products",
            localField: "items.productId",
            foreignField: "_id",
            as: "productDetail"
        }},
        { $unwind: { path: "$productDetail", preserveNullAndEmptyArrays: true } },
        { $project: {
            orderNumber: 1,
            productName: "$items.productName",
            quantity: "$items.quantity",
            lineTotal: "$items.totalPrice",
            category: "$productDetail.category",
            inStock: "$productDetail.inStock",
            stockRemaining: "$productDetail.stockQuantity"
        }},
        { $sort: { orderNumber: 1 } }
    ]).toArray().forEach(function(item) {
        var stock = item.inStock ? item.stockRemaining + " left" : "OUT OF STOCK";
        print("  " + item.orderNumber + " | " + item.productName + " x" + item.quantity +
              " ($" + item.lineTotal + ") | " + (item.category || "n/a") + " | " + stock);
    });
' 2>&1 || true
echo "  ⏱  $(( ($(date +%s%N) - t0) / 1000000 )) ms"
echo ""

t0=$(date +%s%N)
mongosh "$CONN_URI" --quiet --eval '
    use("sampledb");
    print("Query: Revenue by customer city (orders JOIN users, grouped)");
    print("  Which cities generate the most revenue?\n");
    db.orders.aggregate([
        { $lookup: {
            from: "users",
            localField: "userId",
            foreignField: "_id",
            as: "customer"
        }},
        { $unwind: "$customer" },
        { $group: {
            _id: "$customer.city",
            totalRevenue: { $sum: "$orderSummary.total" },
            orderCount: { $sum: 1 }
        }},
        { $sort: { totalRevenue: -1 } },
        { $project: {
            city: "$_id",
            totalRevenue: { $round: ["$totalRevenue", 2] },
            orderCount: 1,
            _id: 0
        }}
    ]).toArray().forEach(function(r) {
        print("  " + r.city + " — $" + r.totalRevenue + " (" + r.orderCount + " orders)");
    });
' 2>&1 || true
echo "  ⏱  $(( ($(date +%s%N) - t0) / 1000000 )) ms"
echo ""

t0=$(date +%s%N)
mongosh "$CONN_URI" --quiet --eval '
    use("sampledb");
    print("Query: Top customers by total spending (orders grouped, JOIN users)");
    print("  Rank customers by how much theyve spent across all orders.\n");
    db.orders.aggregate([
        { $group: {
            _id: "$userId",
            totalSpent: { $sum: "$orderSummary.total" },
            orderCount: { $sum: 1 },
            avgOrderValue: { $avg: "$orderSummary.total" }
        }},
        { $lookup: {
            from: "users",
            localField: "_id",
            foreignField: "_id",
            as: "user"
        }},
        { $unwind: "$user" },
        { $project: {
            _id: 0,
            username: "$user.username",
            email: "$user.email",
            city: "$user.city",
            totalSpent: { $round: ["$totalSpent", 2] },
            orderCount: 1,
            avgOrderValue: { $round: ["$avgOrderValue", 2] }
        }},
        { $sort: { totalSpent: -1 } }
    ]).toArray().forEach(function(c) {
        print("  " + c.username + " (" + c.city + ") — $" + c.totalSpent +
              " total, " + c.orderCount + " orders, avg $" + c.avgOrderValue);
    });
' 2>&1 || true
echo "  ⏱  $(( ($(date +%s%N) - t0) / 1000000 )) ms"
echo ""

t0=$(date +%s%N)
mongosh "$CONN_URI" --quiet --eval '
    use("sampledb");
    print("Query: Most ordered products (unwind order items, group by product)");
    print("  Which products appear most frequently across all orders?\n");
    db.orders.aggregate([
        { $unwind: "$items" },
        { $group: {
            _id: "$items.productId",
            productName: { $first: "$items.productName" },
            timesOrdered: { $sum: 1 },
            totalQuantity: { $sum: "$items.quantity" },
            totalRevenue: { $sum: "$items.totalPrice" }
        }},
        { $lookup: {
            from: "products",
            localField: "_id",
            foreignField: "_id",
            as: "product"
        }},
        { $unwind: { path: "$product", preserveNullAndEmptyArrays: true } },
        { $project: {
            _id: 0,
            productName: 1,
            category: "$product.category",
            timesOrdered: 1,
            totalQuantity: 1,
            totalRevenue: { $round: ["$totalRevenue", 2] }
        }},
        { $sort: { totalRevenue: -1 } }
    ]).toArray().forEach(function(p) {
        print("  " + p.productName + " (" + (p.category || "n/a") + ") — ordered " +
              p.timesOrdered + "x, qty " + p.totalQuantity + ", revenue $" + p.totalRevenue);
    });
' 2>&1 || true
echo "  ⏱  $(( ($(date +%s%N) - t0) / 1000000 )) ms"
echo ""

echo '--- Step 6: Complex multi-collection queries ---'

t0=$(date +%s%N)
mongosh "$CONN_URI" --quiet --eval '
    use("sampledb");
    print("Query: Full order invoice (orders + users + products, triple join)");
    print("  Build a complete invoice view: customer details, line items with product category, totals.\n");
    db.orders.aggregate([
        { $lookup: { from: "users", localField: "userId", foreignField: "_id", as: "cust" }},
        { $unwind: "$cust" },
        { $unwind: "$items" },
        { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "prod" }},
        { $unwind: { path: "$prod", preserveNullAndEmptyArrays: true } },
        { $group: {
            _id: "$_id",
            orderNumber: { $first: "$orderNumber" },
            customer: { $first: { $concat: ["$cust.firstName", " ", "$cust.lastName", " (", "$cust.city", ")"] } },
            status: { $first: "$status" },
            total: { $first: "$orderSummary.total" },
            lineItems: { $push: {
                product: "$items.productName",
                category: "$prod.category",
                qty: "$items.quantity",
                price: "$items.totalPrice",
                rating: "$prod.ratings.average"
            }}
        }},
        { $sort: { orderNumber: 1 } }
    ]).toArray().forEach(function(inv) {
        print("  " + inv.orderNumber + " | " + inv.customer + " | " + inv.status + " | $" + inv.total);
        inv.lineItems.forEach(function(li) {
            print("    → " + li.product + " [" + (li.category || "?") + "] x" + li.qty + " $" + li.price + " (★" + (li.rating || "?") + ")");
        });
    });
' 2>&1 || true
echo "  ⏱  $(( ($(date +%s%N) - t0) / 1000000 )) ms"
echo ""

t0=$(date +%s%N)
mongosh "$CONN_URI" --quiet --eval '
    use("sampledb");
    print("Query: User activity feed with product & order details (analytics + users + products + orders)");
    print("  Enrich the daily activity log with real user names, product names, and order numbers.\n");
    db.analytics.aggregate([
        { $match: { type: "daily_activity" } },
        { $unwind: "$activities" },
        { $lookup: { from: "users", localField: "activities.userId", foreignField: "_id", as: "actUser" }},
        { $unwind: "$actUser" },
        { $unwind: "$activities.actions" },
        { $lookup: { from: "products", localField: "activities.actions.productId", foreignField: "_id", as: "actProd" }},
        { $unwind: { path: "$actProd", preserveNullAndEmptyArrays: true } },
        { $lookup: { from: "orders", localField: "activities.actions.orderId", foreignField: "_id", as: "actOrder" }},
        { $unwind: { path: "$actOrder", preserveNullAndEmptyArrays: true } },
        { $project: {
            _id: 0,
            date: 1,
            userName: { $concat: ["$actUser.firstName", " ", "$actUser.lastName"] },
            action: "$activities.actions.action",
            product: "$actProd.name",
            orderNumber: "$actOrder.orderNumber",
            orderTotal: "$actOrder.orderSummary.total"
        }},
        { $sort: { date: 1, userName: 1 } }
    ]).toArray().forEach(function(a) {
        var detail = a.action;
        if (a.product) detail += " — " + a.product;
        if (a.orderNumber) detail += " — " + a.orderNumber + " ($" + a.orderTotal + ")";
        print("  " + a.date + " | " + a.userName + " | " + detail);
    });
' 2>&1 || true
echo "  ⏱  $(( ($(date +%s%N) - t0) / 1000000 )) ms"
echo ""

t0=$(date +%s%N)
mongosh "$CONN_URI" --quiet --eval '
    use("sampledb");
    print("Query: Customer lifetime value dashboard (users + orders + products, with computed metrics)");
    print("  For each user: total spent, # orders, avg order value, favorite category, premium status.\n");
    db.users.aggregate([
        { $lookup: { from: "orders", localField: "_id", foreignField: "userId", as: "orders" }},
        { $unwind: { path: "$orders", preserveNullAndEmptyArrays: true } },
        { $unwind: { path: "$orders.items", preserveNullAndEmptyArrays: true } },
        { $lookup: { from: "products", localField: "orders.items.productId", foreignField: "_id", as: "prod" }},
        { $unwind: { path: "$prod", preserveNullAndEmptyArrays: true } },
        { $group: {
            _id: "$_id",
            username: { $first: "$username" },
            city: { $first: "$city" },
            tags: { $first: "$tags" },
            isActive: { $first: "$isActive" },
            totalSpent: { $sum: { $ifNull: ["$orders.items.totalPrice", 0] } },
            orderIds: { $addToSet: "$orders._id" },
            categories: { $push: "$prod.category" }
        }},
        { $addFields: {
            orderCount: { $size: { $filter: { input: "$orderIds", as: "o", cond: { $ne: ["$$o", null] } } } },
            isPremium: { $in: ["premium", { $ifNull: ["$tags", []] }] },
            topCategory: { $arrayElemAt: [
                { $map: {
                    input: { $slice: [
                        { $sortArray: {
                            input: { $map: {
                                input: { $setUnion: { $filter: { input: "$categories", as: "c", cond: { $ne: ["$$c", null] } } } },
                                as: "cat",
                                in: { cat: "$$cat", cnt: { $size: { $filter: { input: "$categories", as: "c2", cond: { $eq: ["$$c2", "$$cat"] } } } } }
                            }},
                            sortBy: { cnt: -1 }
                        }},
                        1
                    ] },
                    as: "top", in: "$$top.cat"
                }},
                0
            ] }
        }},
        { $project: {
            _id: 0, username: 1, city: 1, isPremium: 1, isActive: 1,
            totalSpent: { $round: ["$totalSpent", 2] },
            orderCount: 1,
            avgOrder: { $round: [{ $cond: [{ $gt: ["$orderCount", 0] }, { $divide: ["$totalSpent", "$orderCount"] }, 0] }, 2] },
            topCategory: { $ifNull: ["$topCategory", "none"] }
        }},
        { $sort: { totalSpent: -1 } }
    ]).toArray().forEach(function(u) {
        var badge = (u.isPremium ? "★" : " ") + (u.isActive ? "●" : "○");
        print("  " + badge + " " + u.username + " (" + u.city + ") — $" + u.totalSpent +
              ", " + u.orderCount + " orders, avg $" + u.avgOrder + ", fav: " + u.topCategory);
    });
' 2>&1 || true
echo "  ⏱  $(( ($(date +%s%N) - t0) / 1000000 )) ms"
echo ""

QUERIES_END=$(date +%s%N)
TOTAL_MS=$(( (QUERIES_END - QUERIES_START) / 1000000 ))
echo "================================================================"
echo "  All queries completed in ${TOTAL_MS} ms"
echo "================================================================"
