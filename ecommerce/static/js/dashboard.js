// Dashboard JavaScript
const API_BASE = '';

// State
let charts = {};
let streamStatsInterval = null;

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initNavigation();
    initButtons();
    initFilters();
    loadOverview();
    startStreamStatsPolling();
});

// Navigation
function initNavigation() {
    const navItems = document.querySelectorAll('.nav-item');
    navItems.forEach(item => {
        item.addEventListener('click', (e) => {
            e.preventDefault();
            const section = item.dataset.section;
            
            // Update active nav item
            navItems.forEach(i => i.classList.remove('active'));
            item.classList.add('active');
            
            // Update section visibility
            document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
            document.getElementById(`section-${section}`).classList.add('active');
            
            // Update page title
            const titles = {
                'overview': 'Dashboard Overview',
                'live-feed': 'Live Social Media Feed',
                'data-quality': 'Data Quality - Referential Integrity',
                'sales': 'Sales Analytics',
                'customers': 'Customer Analytics',
                'inventory': 'Inventory Management'
            };
            document.getElementById('page-title').textContent = titles[section] || 'Dashboard';
            
            // Load section data
            loadSectionData(section);
        });
    });
}

function initButtons() {
    document.getElementById('btn-refresh').addEventListener('click', () => {
        const activeSection = document.querySelector('.nav-item.active').dataset.section;
        loadSectionData(activeSection);
    });
    
    document.getElementById('btn-setup').addEventListener('click', resetData);
    document.getElementById('btn-sync-inventory').addEventListener('click', syncInventory);
}

function initFilters() {
    const sentimentFilter = document.getElementById('filter-sentiment');
    const sourceFilter = document.getElementById('filter-source');
    
    if (sentimentFilter) {
        sentimentFilter.addEventListener('change', () => loadLiveFeed());
    }
    if (sourceFilter) {
        sourceFilter.addEventListener('change', () => loadLiveFeed());
    }
}

// Load section data
function loadSectionData(section) {
    switch(section) {
        case 'overview': loadOverview(); break;
        case 'live-feed': loadLiveFeed(); break;
        case 'data-quality': loadDataQuality(); break;
        case 'sales': loadSalesAnalytics(); break;
        case 'customers': loadCustomers(); break;
        case 'inventory': loadInventory(); break;
    }
}

// API Helpers
async function fetchAPI(endpoint) {
    showLoading();
    try {
        const response = await fetch(`${API_BASE}/api/${endpoint}`);
        if (!response.ok) throw new Error('API error');
        return await response.json();
    } catch (error) {
        console.error('API Error:', error);
        showToast('Error loading data', 'error');
        return null;
    } finally {
        hideLoading();
        updateTimestamp();
    }
}

async function postAPI(endpoint, data = {}) {
    showLoading();
    try {
        const response = await fetch(`${API_BASE}/api/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        if (!response.ok) throw new Error('API error');
        return await response.json();
    } catch (error) {
        console.error('API Error:', error);
        showToast('Error performing action', 'error');
        return null;
    } finally {
        hideLoading();
    }
}

// Overview Section
async function loadOverview() {
    const response = await fetchAPI('overview');
    if (!response || !response.data) return;
    const data = response.data;
    
    // Update stats
    document.getElementById('stat-customers').textContent = formatNumber(data.total_customers);
    document.getElementById('stat-products').textContent = formatNumber(data.total_products);
    document.getElementById('stat-orders').textContent = formatNumber(data.total_orders);
    document.getElementById('stat-revenue').textContent = formatCurrency(data.total_revenue);
    document.getElementById('avg-order-value').textContent = formatCurrency(data.avg_order_value || 0);
    document.getElementById('orders-today').textContent = formatNumber(data.orders_today || 0);
    
    // Order Status Chart
    renderOrderStatusChart(data.order_statuses || []);
}

function renderOrderStatusChart(statusData) {
    const ctx = document.getElementById('chart-order-status');
    
    if (charts.orderStatus) charts.orderStatus.destroy();
    if (!statusData || statusData.length === 0) return;
    
    const colors = {
        'delivered': '#10b981',
        'shipped': '#3b82f6',
        'processing': '#f59e0b',
        'confirmed': '#f59e0b',
        'pending': '#8b5cf6',
        'cancelled': '#ef4444'
    };
    
    charts.orderStatus = new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: statusData.map(s => capitalizeFirst(s.status || s._id)),
            datasets: [{
                data: statusData.map(s => s.count),
                backgroundColor: statusData.map(s => colors[s.status || s._id] || '#64748b'),
                borderWidth: 0
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'bottom'
                }
            }
        }
    });
}

// Data Quality Section
async function loadDataQuality() {
    const response = await fetchAPI('data-quality');
    if (!response || !response.data) return;
    const data = response.data;
    
    document.getElementById('health-score').textContent = `${data.health_score}%`;
    document.getElementById('total-issues').textContent = formatNumber(data.total_issues);
    
    // Update health score card color
    const healthCard = document.querySelector('#health-score').closest('.stat-card');
    healthCard.className = 'stat-card';
    if (data.health_score >= 90) {
        healthCard.classList.add('highlight');
    } else if (data.health_score < 70) {
        healthCard.classList.add('warning');
    }
    
    // Render issues
    const issuesList = document.getElementById('issues-list');
    issuesList.innerHTML = data.issues.map(issue => `
        <div class="issue-item ${issue.count > 5 ? 'critical' : ''}">
            <span class="issue-icon">${issue.count > 0 ? '⚠️' : '✅'}</span>
            <div class="issue-content">
                <div class="issue-title">${issue.type}</div>
                <div class="issue-desc">${issue.description}</div>
            </div>
            <span class="issue-count">${issue.count}</span>
        </div>
    `).join('');
}

// Sales Analytics Section
async function loadSalesAnalytics() {
    const response = await fetchAPI('sales-analytics');
    if (!response || !response.data) return;
    const data = response.data;
    
    renderRevenueTrendChart(data.daily_trend || []);
    renderCategoryRevenueChart(data.category_revenue || []);
    renderTopProductsTable(data.top_products || []);
}

function renderRevenueTrendChart(dailyData) {
    const ctx = document.getElementById('chart-revenue-trend');
    
    if (charts.revenueTrend) charts.revenueTrend.destroy();
    if (!dailyData || dailyData.length === 0) return;
    
    // Sort by date
    dailyData.sort((a, b) => new Date(a._id || a.date) - new Date(b._id || b.date));
    
    charts.revenueTrend = new Chart(ctx, {
        type: 'line',
        data: {
            labels: dailyData.map(d => formatDate(d._id)),
            datasets: [{
                label: 'Revenue',
                data: dailyData.map(d => d.revenue),
                borderColor: '#4f46e5',
                backgroundColor: 'rgba(79, 70, 229, 0.1)',
                fill: true,
                tension: 0.4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { display: false }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: {
                        callback: value => '$' + formatNumber(value)
                    }
                }
            }
        }
    });
}

function renderCategoryRevenueChart(categoryData) {
    const ctx = document.getElementById('chart-category-revenue');
    
    if (charts.categoryRevenue) charts.categoryRevenue.destroy();
    if (!categoryData || categoryData.length === 0) return;
    
    const colors = ['#4f46e5', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899'];
    
    charts.categoryRevenue = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: categoryData.map(c => c._id || 'Unknown'),
            datasets: [{
                label: 'Revenue',
                data: categoryData.map(c => c.revenue),
                backgroundColor: colors.slice(0, categoryData.length),
                borderRadius: 4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { display: false }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: {
                        callback: value => '$' + formatNumber(value)
                    }
                }
            }
        }
    });
}

function renderTopProductsTable(products) {
    const tbody = document.getElementById('top-products-table');
    if (!products || products.length === 0) {
        tbody.innerHTML = '<tr><td colspan="3" style="text-align: center;">No data available</td></tr>';
        return;
    }
    tbody.innerHTML = products.map(p => `
        <tr>
            <td>${p._id || 'Unknown'}</td>
            <td>${formatNumber(p.units_sold)}</td>
            <td>${formatCurrency(p.revenue)}</td>
        </tr>
    `).join('');
}

// Customers Section
async function loadCustomers() {
    const response = await fetchAPI('customers');
    if (!response || !response.data) return;
    const data = response.data;
    
    renderCustomerTiersChart(data.tier_distribution || []);
    renderCustomersTable(data.top_customers || []);
}

function renderCustomerTiersChart(tierData) {
    const ctx = document.getElementById('chart-customer-tiers');
    
    if (charts.customerTiers) charts.customerTiers.destroy();
    if (!tierData || tierData.length === 0) return;
    
    const colors = {
        'gold': '#f59e0b',
        'silver': '#94a3b8',
        'bronze': '#b45309',
        'standard': '#64748b'
    };
    
    charts.customerTiers = new Chart(ctx, {
        type: 'pie',
        data: {
            labels: tierData.map(t => capitalizeFirst(t._id || 'Standard')),
            datasets: [{
                data: tierData.map(t => t.count),
                backgroundColor: tierData.map(t => colors[t._id] || '#64748b'),
                borderWidth: 2,
                borderColor: '#ffffff'
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'bottom'
                }
            }
        }
    });
}

function renderCustomersTable(customers) {
    const tbody = document.getElementById('customers-table');
    tbody.innerHTML = customers.map(c => `
        <tr>
            <td>${c.name}</td>
            <td>${c.email}</td>
            <td><span class="tier-${(c.tier || 'standard').toLowerCase()}">${capitalizeFirst(c.tier || 'Standard')}</span></td>
            <td>${formatNumber(c.loyalty_points || 0)}</td>
            <td>${formatNumber(c.total_orders || 0)}</td>
        </tr>
    `).join('');
}

// Inventory Section
async function loadInventory() {
    const response = await fetchAPI('inventory');
    if (!response || !response.data) return;
    const data = response.data;
    
    renderWarehouseChart(data.warehouse_summary || []);
    renderLowStockTable(data.low_stock || []);
}

function renderWarehouseChart(warehouseData) {
    const ctx = document.getElementById('chart-warehouse');
    
    if (charts.warehouse) charts.warehouse.destroy();
    if (!warehouseData || warehouseData.length === 0) return;
    
    charts.warehouse = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: warehouseData.map(w => w._id),
            datasets: [{
                label: 'Products',
                data: warehouseData.map(w => w.product_count),
                backgroundColor: '#4f46e5',
                borderRadius: 4
            }, {
                label: 'Total Quantity',
                data: warehouseData.map(w => w.total_quantity / 10), // Scale down for visibility
                backgroundColor: '#10b981',
                borderRadius: 4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'bottom'
                }
            },
            scales: {
                y: { beginAtZero: true }
            }
        }
    });
}

function renderLowStockTable(lowStock) {
    const tbody = document.getElementById('low-stock-table');
    
    if (lowStock.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--success-color);">✅ No low stock alerts</td></tr>';
        return;
    }
    
    tbody.innerHTML = lowStock.map(item => {
        const ratio = item.available / item.reorder_point;
        let statusClass = 'status-ok';
        let statusText = 'OK';
        
        if (ratio <= 0.5) {
            statusClass = 'status-critical';
            statusText = '🚨 Critical';
        } else if (ratio <= 1) {
            statusClass = 'status-low';
            statusText = '⚠️ Low';
        }
        
        return `
            <tr>
                <td>${item.product_id}</td>
                <td>${item.warehouse_id}</td>
                <td>${formatNumber(item.available)}</td>
                <td>${formatNumber(item.reorder_point)}</td>
                <td><span class="status-badge ${statusClass}">${statusText}</span></td>
            </tr>
        `;
    }).join('');
}

async function syncInventory() {
    const btn = document.getElementById('btn-sync-inventory');
    const status = document.getElementById('sync-status');
    
    btn.disabled = true;
    status.textContent = 'Syncing...';
    
    const result = await postAPI('inventory/sync');
    
    if (result) {
        status.textContent = `✅ Synced ${result.items_synced} items in ${result.time_ms}ms`;
        status.className = 'status-text success';
        showToast('Inventory synced successfully!', 'success');
        loadInventory(); // Reload data
    }
    
    btn.disabled = false;
}

// Reset Data
async function resetData() {
    if (!confirm('This will reset all data. Continue?')) return;
    
    const result = await postAPI('setup');
    
    if (result) {
        showToast('Data reset successfully!', 'success');
        loadOverview();
    }
}

// Utilities
function showLoading() {
    document.getElementById('loading-overlay').classList.add('active');
}

function hideLoading() {
    document.getElementById('loading-overlay').classList.remove('active');
}

function showToast(message, type = 'info') {
    const toast = document.getElementById('toast');
    toast.textContent = message;
    toast.className = `toast ${type} show`;
    
    setTimeout(() => {
        toast.classList.remove('show');
    }, 3000);
}

function updateTimestamp() {
    const now = new Date();
    document.getElementById('update-time').textContent = now.toLocaleTimeString();
}

function formatNumber(num) {
    if (num === null || num === undefined) return '-';
    return new Intl.NumberFormat().format(Math.round(num));
}

function formatCurrency(num) {
    if (num === null || num === undefined) return '-';
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD',
        minimumFractionDigits: 0,
        maximumFractionDigits: 0
    }).format(num);
}

function formatDate(dateStr) {
    const date = new Date(dateStr);
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

function capitalizeFirst(str) {
    if (!str) return '';
    return str.charAt(0).toUpperCase() + str.slice(1);
}

function formatTimeAgo(dateStr) {
    const date = new Date(dateStr);
    const now = new Date();
    const diffMs = now - date;
    const diffSec = Math.floor(diffMs / 1000);
    const diffMin = Math.floor(diffSec / 60);
    const diffHour = Math.floor(diffMin / 60);
    
    if (diffSec < 60) return `${diffSec}s ago`;
    if (diffMin < 60) return `${diffMin}m ago`;
    if (diffHour < 24) return `${diffHour}h ago`;
    return formatDate(dateStr);
}

// ============================================================================
// Live Feed Section
// ============================================================================

function startStreamStatsPolling() {
    // Poll stream stats every 3 seconds for live indicator
    updateStreamStats();
    streamStatsInterval = setInterval(updateStreamStats, 3000);
}

async function updateStreamStats() {
    try {
        const response = await fetch(`${API_BASE}/api/stream/stats`);
        const result = await response.json();
        
        if (result.success && result.data) {
            const data = result.data;
            const rate = data.generator?.items_per_second || 0;
            
            // Update header live indicator
            const liveRate = document.getElementById('live-rate');
            if (liveRate) {
                liveRate.textContent = `${rate.toFixed(1)} items/sec`;
            }
        }
    } catch (error) {
        console.error('Stream stats error:', error);
    }
}

async function loadLiveFeed() {
    // Get filter values
    const sentimentFilter = document.getElementById('filter-sentiment')?.value || '';
    const sourceFilter = document.getElementById('filter-source')?.value || '';
    
    // Build query params
    let params = new URLSearchParams();
    if (sentimentFilter) params.append('sentiment', sentimentFilter);
    if (sourceFilter) params.append('source', sourceFilter);
    params.append('limit', '50');
    
    // Fetch stream stats
    const statsResponse = await fetchAPI('stream/stats');
    if (statsResponse && statsResponse.data) {
        const stats = statsResponse.data;
        
        document.getElementById('stream-rate').textContent = 
            (stats.generator?.items_per_second || 0).toFixed(1);
        document.getElementById('total-social').textContent = 
            formatNumber(stats.totals?.social_comments || 0);
        document.getElementById('total-reviews').textContent = 
            formatNumber(stats.totals?.reviews || 0);
        document.getElementById('recent-activity').textContent = 
            formatNumber((stats.recent_activity?.orders_last_minute || 0) + 
                        (stats.recent_activity?.social_last_minute || 0));
    }
    
    // Fetch social feed
    const feedResponse = await fetchAPI(`social-feed?${params.toString()}`);
    if (feedResponse && feedResponse.data) {
        renderSentimentChart(feedResponse.data.sentiment_distribution || []);
        renderSourcesChart(feedResponse.data.source_distribution || []);
        renderSocialFeed(feedResponse.data.comments || []);
    }
}

function renderSentimentChart(sentimentData) {
    const ctx = document.getElementById('chart-sentiment');
    if (!ctx) return;
    
    if (charts.sentiment) charts.sentiment.destroy();
    if (!sentimentData || sentimentData.length === 0) return;
    
    const colors = {
        'positive': '#10b981',
        'neutral': '#f59e0b',
        'negative': '#ef4444'
    };
    
    charts.sentiment = new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: sentimentData.map(s => capitalizeFirst(s._id)),
            datasets: [{
                data: sentimentData.map(s => s.count),
                backgroundColor: sentimentData.map(s => colors[s._id] || '#64748b'),
                borderWidth: 0
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { position: 'bottom' }
            }
        }
    });
}

function renderSourcesChart(sourceData) {
    const ctx = document.getElementById('chart-sources');
    if (!ctx) return;
    
    if (charts.sources) charts.sources.destroy();
    if (!sourceData || sourceData.length === 0) return;
    
    const colors = {
        'twitter': '#1da1f2',
        'instagram': '#e4405f',
        'facebook': '#1877f2',
        'tiktok': '#000000',
        'reddit': '#ff4500'
    };
    
    charts.sources = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: sourceData.map(s => capitalizeFirst(s._id)),
            datasets: [{
                label: 'Comments',
                data: sourceData.map(s => s.count),
                backgroundColor: sourceData.map(s => colors[s._id] || '#64748b'),
                borderRadius: 4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { display: false }
            },
            scales: {
                y: { beginAtZero: true }
            }
        }
    });
}

function renderSocialFeed(comments) {
    const feed = document.getElementById('social-feed');
    if (!feed) return;
    
    if (!comments || comments.length === 0) {
        feed.innerHTML = '<div style="text-align: center; color: var(--text-secondary); padding: 2rem;">No comments yet. Data is being generated...</div>';
        return;
    }
    
    const sourceIcons = {
        'twitter': '🐦',
        'instagram': '📷',
        'facebook': '📘',
        'tiktok': '🎵',
        'reddit': '🔴'
    };
    
    const sentimentEmojis = {
        'positive': '😊',
        'neutral': '😐',
        'negative': '😞'
    };
    
    feed.innerHTML = comments.map(comment => `
        <div class="social-comment ${comment.sentiment}">
            <div class="comment-source">${sourceIcons[comment.source] || '💬'}</div>
            <div class="comment-content">
                <div class="comment-header">
                    <span class="comment-username">@${comment.username}</span>
                    <span class="sentiment-badge sentiment-${comment.sentiment}">
                        ${sentimentEmojis[comment.sentiment] || ''} ${capitalizeFirst(comment.sentiment)}
                    </span>
                    <span class="comment-time">${formatTimeAgo(comment.created_at)}</span>
                </div>
                <div class="comment-text">${escapeHtml(comment.text)}</div>
                ${comment.hashtags && comment.hashtags.length > 0 ? `
                    <div class="comment-hashtags">
                        ${comment.hashtags.map(tag => `<span class="hashtag">${tag}</span>`).join('')}
                    </div>
                ` : ''}
                <div class="comment-meta">
                    <span>❤️ ${formatNumber(comment.likes)}</span>
                    <span>🔄 ${formatNumber(comment.shares)}</span>
                    ${comment.product_name ? `<span class="product-link">📦 ${comment.product_name}</span>` : ''}
                </div>
            </div>
        </div>
    `).join('');
}

function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
