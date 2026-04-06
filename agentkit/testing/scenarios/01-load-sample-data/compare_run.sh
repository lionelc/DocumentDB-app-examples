#!/usr/bin/env bash
set -uo pipefail
source "$(cd "$(dirname "$0")/../../harness" && pwd)/helpers.sh"

########################################################################
# compare_run.sh
#
# Benchmark comparison: DocumentDB vs MongoDB on identical queries.
# Runs the same 8 queries against both engines and prints a side-by-side
# timing table.
#
# Flow:
#   1. Run queries against DocumentDB (already running)
#   2. Stop DocumentDB container
#   3. Pull & start MongoDB on the same port
#   4. Load sample data into MongoDB
#   5. Run queries against MongoDB
#   6. Stop MongoDB
#   7. Restart DocumentDB
########################################################################

banner 1 "DocumentDB vs MongoDB — Query Benchmark Comparison"

MONGO_IMAGE="mongo:8.0"
MONGO_CONTAINER="mongodb-compare"
COMPARE_PORT=10260

# ── Write query scripts to temp dir ──────────────────────────────────

QDIR=$(mktemp -d)
trap "rm -rf $QDIR" EXIT

cat > "$QDIR/q1.js" << 'QEOF'
use("sampledb");
print("Q1: Users in San Francisco");
db.users.find({"city": "San Francisco"}).toArray().forEach(function(u) {
    print("  " + u.username + " — " + u.email);
});
QEOF

cat > "$QDIR/q2.js" << 'QEOF'
use("sampledb");
print("Q2: Products under $100 sorted by rating");
db.products.find({price: {$lt: 100}}).sort({"ratings.average": -1}).toArray().forEach(function(p) {
    print("  " + p.name + " — $" + p.price + " (rating: " + p.ratings.average + ")");
});
QEOF

cat > "$QDIR/q3.js" << 'QEOF'
use("sampledb");
print("Q3: Orders shipped or delivered");
db.orders.find({status: {$in: ["shipped", "delivered"]}}).toArray().forEach(function(o) {
    print("  " + o.orderNumber + " — " + o.status + " — $" + o.orderSummary.total);
});
QEOF

cat > "$QDIR/q4.js" << 'QEOF'
use("sampledb");
print("Q4: Customer order history (orders JOIN users)");
db.orders.aggregate([
    { $lookup: { from: "users", localField: "userId", foreignField: "_id", as: "customer" }},
    { $unwind: "$customer" },
    { $project: {
        orderNumber: 1,
        customerName: { $concat: ["$customer.firstName", " ", "$customer.lastName"] },
        customerCity: "$customer.city",
        total: "$orderSummary.total", status: 1, orderDate: 1
    }},
    { $sort: { orderDate: -1 } }
]).toArray().forEach(function(o) {
    print("  " + o.orderNumber + " | " + o.customerName + " (" + o.customerCity + ") | $" + o.total + " | " + o.status);
});
QEOF

cat > "$QDIR/q5.js" << 'QEOF'
use("sampledb");
print("Q5: Order line items enriched with product details");
db.orders.aggregate([
    { $unwind: "$items" },
    { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "pd" }},
    { $unwind: { path: "$pd", preserveNullAndEmptyArrays: true } },
    { $project: {
        orderNumber: 1, productName: "$items.productName",
        quantity: "$items.quantity", lineTotal: "$items.totalPrice",
        category: "$pd.category", stockRemaining: "$pd.stockQuantity"
    }},
    { $sort: { orderNumber: 1 } }
]).toArray().forEach(function(i) {
    print("  " + i.orderNumber + " | " + i.productName + " x" + i.quantity +
          " ($" + i.lineTotal + ") | " + (i.category || "n/a"));
});
QEOF

cat > "$QDIR/q6.js" << 'QEOF'
use("sampledb");
print("Q6: Revenue by customer city");
db.orders.aggregate([
    { $lookup: { from: "users", localField: "userId", foreignField: "_id", as: "c" }},
    { $unwind: "$c" },
    { $group: { _id: "$c.city", totalRevenue: { $sum: "$orderSummary.total" }, orderCount: { $sum: 1 } }},
    { $sort: { totalRevenue: -1 } },
    { $project: { city: "$_id", totalRevenue: { $round: ["$totalRevenue", 2] }, orderCount: 1, _id: 0 }}
]).toArray().forEach(function(r) {
    print("  " + r.city + " — $" + r.totalRevenue + " (" + r.orderCount + " orders)");
});
QEOF

cat > "$QDIR/q7.js" << 'QEOF'
use("sampledb");
print("Q7: Top customers by spending");
db.orders.aggregate([
    { $group: { _id: "$userId", totalSpent: { $sum: "$orderSummary.total" }, orderCount: { $sum: 1 }, avg: { $avg: "$orderSummary.total" } }},
    { $lookup: { from: "users", localField: "_id", foreignField: "_id", as: "u" }},
    { $unwind: "$u" },
    { $project: { _id: 0, username: "$u.username", city: "$u.city", totalSpent: { $round: ["$totalSpent", 2] }, orderCount: 1, avg: { $round: ["$avg", 2] } }},
    { $sort: { totalSpent: -1 } }
]).toArray().forEach(function(c) {
    print("  " + c.username + " (" + c.city + ") — $" + c.totalSpent + " total, " + c.orderCount + " orders");
});
QEOF

cat > "$QDIR/q8.js" << 'QEOF'
use("sampledb");
print("Q8: Most ordered products");
db.orders.aggregate([
    { $unwind: "$items" },
    { $group: { _id: "$items.productId", name: { $first: "$items.productName" }, cnt: { $sum: 1 }, qty: { $sum: "$items.quantity" }, rev: { $sum: "$items.totalPrice" } }},
    { $lookup: { from: "products", localField: "_id", foreignField: "_id", as: "p" }},
    { $unwind: { path: "$p", preserveNullAndEmptyArrays: true } },
    { $project: { _id: 0, name: 1, category: "$p.category", cnt: 1, qty: 1, rev: { $round: ["$rev", 2] } }},
    { $sort: { rev: -1 } }
]).toArray().forEach(function(p) {
    print("  " + p.name + " (" + (p.category || "n/a") + ") — " + p.cnt + "x, qty " + p.qty + ", $" + p.rev);
});
QEOF

cat > "$QDIR/q9.js" << 'QEOF'
use("sampledb");
print("Q9: Full order invoice (triple join: orders + users + products)");
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
            product: "$items.productName", category: "$prod.category",
            qty: "$items.quantity", price: "$items.totalPrice", rating: "$prod.ratings.average"
        }}
    }},
    { $sort: { orderNumber: 1 } }
]).toArray().forEach(function(inv) {
    print("  " + inv.orderNumber + " | " + inv.customer + " | " + inv.status + " | $" + inv.total);
    inv.lineItems.forEach(function(li) {
        print("    -> " + li.product + " [" + (li.category || "?") + "] x" + li.qty + " $" + li.price + " (r:" + (li.rating || "?") + ")");
    });
});
QEOF

cat > "$QDIR/q10.js" << 'QEOF'
use("sampledb");
print("Q10: Activity feed (4-way join: analytics + users + products + orders)");
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
        _id: 0, date: 1,
        userName: { $concat: ["$actUser.firstName", " ", "$actUser.lastName"] },
        action: "$activities.actions.action",
        product: "$actProd.name",
        orderNumber: "$actOrder.orderNumber",
        orderTotal: "$actOrder.orderSummary.total"
    }},
    { $sort: { date: 1, userName: 1 } }
]).toArray().forEach(function(a) {
    var detail = a.action;
    if (a.product) detail += " - " + a.product;
    if (a.orderNumber) detail += " - " + a.orderNumber + " ($" + a.orderTotal + ")";
    print("  " + a.date + " | " + a.userName + " | " + detail);
});
QEOF

cat > "$QDIR/q11.js" << 'QEOF'
use("sampledb");
print("Q11: Customer lifetime value (users + orders + products, computed metrics)");
db.users.aggregate([
    { $lookup: { from: "orders", localField: "_id", foreignField: "userId", as: "orders" }},
    { $unwind: { path: "$orders", preserveNullAndEmptyArrays: true } },
    { $unwind: { path: "$orders.items", preserveNullAndEmptyArrays: true } },
    { $lookup: { from: "products", localField: "orders.items.productId", foreignField: "_id", as: "prod" }},
    { $unwind: { path: "$prod", preserveNullAndEmptyArrays: true } },
    { $group: {
        _id: "$_id", username: { $first: "$username" }, city: { $first: "$city" },
        tags: { $first: "$tags" }, isActive: { $first: "$isActive" },
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
        totalSpent: { $round: ["$totalSpent", 2] }, orderCount: 1,
        avgOrder: { $round: [{ $cond: [{ $gt: ["$orderCount", 0] }, { $divide: ["$totalSpent", "$orderCount"] }, 0] }, 2] },
        topCategory: { $ifNull: ["$topCategory", "none"] }
    }},
    { $sort: { totalSpent: -1 } }
]).toArray().forEach(function(u) {
    var badge = (u.isPremium ? "P" : " ") + (u.isActive ? "A" : " ");
    print("  [" + badge + "] " + u.username + " (" + u.city + ") - $" + u.totalSpent +
          ", " + u.orderCount + " orders, avg $" + u.avgOrder + ", fav: " + u.topCategory);
});
QEOF

QUERY_NAMES=(
    "Users in SF (filter)"
    "Products <100 (sort)"
    "Orders shipped (in)"
    "Order history (lookup)"
    "Line items (unwind+lookup)"
    "Revenue by city (grp+lookup)"
    "Top customers (grp+lookup)"
    "Popular products (unw+grp+lkp)"
    "Full invoice (triple join)"
    "Activity feed (4-way join)"
    #"Customer LTV (3-join+compute)"
)

# ── Benchmark function ───────────────────────────────────────────────

run_benchmark() {
    local label="$1" uri="$2"
    local -n result_arr=$3
    local output_dir="$4"
    result_arr=()

    mkdir -p "$output_dir"

    echo ""
    echo "  Running 10 queries against $label ..."
    echo ""

    local total_start; total_start=$(date +%s%N)

    for i in $(seq 1 10); do
        local t0; t0=$(date +%s%N)
        local out
        out=$(mongosh "$uri" --quiet --file "$QDIR/q${i}.js" 2>&1)
        local elapsed=$(( ($(date +%s%N) - t0) / 1000000 ))
        echo "$out" | sed 's/^/    /'
        echo "    ⏱  ${elapsed} ms"
        echo ""
        # Save output for comparison (strip timing/whitespace noise)
        echo "$out" > "$output_dir/q${i}.out"
        result_arr+=("$elapsed")
    done

    local total_elapsed=$(( ($(date +%s%N) - total_start) / 1000000 ))
    result_arr+=("$total_elapsed")
    echo "  $label total: ${total_elapsed} ms"
}

# ── Load sample data function ────────────────────────────────────────

load_sample_data() {
    local uri="$1" label="$2"
    local datadir; datadir=$(mktemp -d)

    echo "  Loading sample data into $label ..."
    for f in 01-users.js 02-products.js 03-orders.js 04-analytics.js; do
        curl -sLo "$datadir/$f" \
            "https://raw.githubusercontent.com/documentdb/documentdb/main/sample-data/$f"
    done
    for f in "$datadir"/*.js; do
        mongosh "$uri" --quiet --file "$f" 2>&1 | grep -v "^$" | head -3 | sed 's/^/    /'
    done
    rm -rf "$datadir"
    echo ""
}

# ══════════════════════════════════════════════════════════════════════
# Phase 1: Benchmark DocumentDB
# ══════════════════════════════════════════════════════════════════════

echo "================================================================"
echo "  Phase 1: DocumentDB"
echo "================================================================"

ensure_main_container || { echo "FAIL: DocumentDB container unavailable"; exit 1; }

DOCDB_URI="mongodb://${USER}:${PASSWORD}@localhost:${COMPARE_PORT}/?tls=true&tlsAllowInvalidCertificates=true&directConnection=true"

# Ensure sample data is loaded
mongosh "$DOCDB_URI" --quiet --eval '
    use("sampledb");
    if (db.users.countDocuments() === 0) { print("NEED_DATA"); }
    else { print("DATA_OK: " + db.users.countDocuments() + " users"); }
' 2>&1 | grep -q "NEED_DATA" && load_sample_data "$DOCDB_URI" "DocumentDB"

DOCDB_TIMES=()
run_benchmark "DocumentDB" "$DOCDB_URI" DOCDB_TIMES "$QDIR/out_docdb"

# ══════════════════════════════════════════════════════════════════════
# Phase 2: Stop DocumentDB, start MongoDB
# ══════════════════════════════════════════════════════════════════════

echo ""
echo "================================================================"
echo "  Phase 2: MongoDB"
echo "================================================================"

echo "  Stopping DocumentDB container ($MAIN_CONTAINER) ..."
docker stop "$MAIN_CONTAINER" 2>/dev/null || true
echo ""

echo "  Pulling MongoDB image ($MONGO_IMAGE) ..."
docker pull "$MONGO_IMAGE" 2>&1 | tail -1
echo ""

echo "  Starting MongoDB on port $COMPARE_PORT ..."
docker run -dt \
    -p "${COMPARE_PORT}:27017" \
    --name "$MONGO_CONTAINER" \
    -e MONGO_INITDB_ROOT_USERNAME="$USER" \
    -e MONGO_INITDB_ROOT_PASSWORD="$PASSWORD" \
    "$MONGO_IMAGE" 2>&1
echo ""

# Wait for MongoDB to be ready
MONGO_URI="mongodb://${USER}:${PASSWORD}@localhost:${COMPARE_PORT}/?directConnection=true&authSource=admin"
echo "  Waiting for MongoDB to be ready ..."
waited=0
while (( waited < 60 )); do
    if mongosh "$MONGO_URI" --quiet --eval "db.runCommand({ping:1})" &>/dev/null 2>&1; then
        echo "  MongoDB ready after ${waited}s"
        break
    fi
    sleep 2
    waited=$((waited + 2))
done
if (( waited >= 60 )); then
    echo "  TIMEOUT: MongoDB not ready"
    docker logs "$MONGO_CONTAINER" 2>&1 | tail -10
    docker rm -f "$MONGO_CONTAINER" 2>/dev/null || true
    docker start "$MAIN_CONTAINER" 2>/dev/null || true
    exit 1
fi
echo ""

# Load sample data into MongoDB
load_sample_data "$MONGO_URI" "MongoDB"

MONGO_TIMES=()
run_benchmark "MongoDB" "$MONGO_URI" MONGO_TIMES "$QDIR/out_mongo"

# ══════════════════════════════════════════════════════════════════════
# Phase 3: Stop MongoDB, restart DocumentDB
# ══════════════════════════════════════════════════════════════════════

echo ""
echo "  Stopping and removing MongoDB container ..."
docker rm -f "$MONGO_CONTAINER" 2>/dev/null || true

echo "  Restarting DocumentDB container ($MAIN_CONTAINER) ..."
docker start "$MAIN_CONTAINER" 2>/dev/null || true
echo "  Waiting for DocumentDB to be ready ..."
waited=0
while (( waited < 60 )); do
    if mongosh "$DOCDB_URI" --quiet --eval "db.runCommand({ping:1})" &>/dev/null 2>&1; then
        echo "  DocumentDB ready after ${waited}s"
        break
    fi
    sleep 2
    waited=$((waited + 2))
done
echo ""

# ══════════════════════════════════════════════════════════════════════
# Results comparison
# ══════════════════════════════════════════════════════════════════════

echo "================================================================"
echo "  BENCHMARK RESULTS: DocumentDB vs MongoDB"
echo "================================================================"
echo ""
printf "  %-32s %10s %10s %10s\n" "Query" "DocumentDB" "MongoDB" "Diff"
echo "  ────────────────────────────────────────────────────────────────"

for i in $(seq 0 9); do
    d=${DOCDB_TIMES[$i]}
    m=${MONGO_TIMES[$i]}
    if (( m > 0 )); then
        diff_ms=$((d - m))
        if (( diff_ms >= 0 )); then
            diff_str="+${diff_ms} ms"
        else
            diff_str="${diff_ms} ms"
        fi
    else
        diff_str="n/a"
    fi
    printf "  %-32s %8s ms %8s ms %10s\n" "${QUERY_NAMES[$i]}" "$d" "$m" "$diff_str"
done

echo "  ────────────────────────────────────────────────────────────────"
d_total=${DOCDB_TIMES[10]}
m_total=${MONGO_TIMES[10]}
diff_total=$((d_total - m_total))
if (( diff_total >= 0 )); then
    diff_total_str="+${diff_total} ms"
else
    diff_total_str="${diff_total} ms"
fi
printf "  %-32s %8s ms %8s ms %10s\n" "TOTAL" "$d_total" "$m_total" "$diff_total_str"
echo ""
echo "  Note: Timings include mongosh startup (~600-700ms overhead per query)."
echo "        Diff = DocumentDB - MongoDB (negative = DocumentDB faster)."
echo "================================================================"
echo ""

# ══════════════════════════════════════════════════════════════════════
# Results correctness comparison
# ══════════════════════════════════════════════════════════════════════

echo "================================================================"
echo "  RESULTS CORRECTNESS CHECK"
echo "================================================================"
echo ""

ALL_IDENTICAL=true
for i in $(seq 1 10); do
    docdb_out="$QDIR/out_docdb/q${i}.out"
    mongo_out="$QDIR/out_mongo/q${i}.out"

    if diff -q "$docdb_out" "$mongo_out" &>/dev/null; then
        printf "  Q%-2s %-34s ✅ Results are identical\n" "$i" "${QUERY_NAMES[$((i-1))]}"
    else
        printf "  Q%-2s %-34s ❌ Results DIFFER\n" "$i" "${QUERY_NAMES[$((i-1))]}"
        ALL_IDENTICAL=false
        echo "      DocumentDB output:"
        sed 's/^/        /' "$docdb_out"
        echo "      MongoDB output:"
        sed 's/^/        /' "$mongo_out"
        echo ""
    fi
done

echo ""
if [[ "$ALL_IDENTICAL" == true ]]; then
    echo "  ✅  ALL QUERY RESULTS ARE IDENTICAL — full compatibility confirmed."
else
    echo "  ⚠️   SOME RESULTS DIFFER — see details above for compatibility gaps."
fi
echo "================================================================"
