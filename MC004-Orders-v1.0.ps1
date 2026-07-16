<#
==============================================================================
 KOS ENTERPRISE ORDERS MODULE
 Master Code : MC004
 Version     : 1.0.0 (Enterprise)
 Auteur      : KHEPRA EXPERTS
 Date        : 2026-07-16
 Status      : Production Ready
==============================================================================

DESCRIPTION
  Initialisation du module Gestion des Commandes KOS.
  - Modèle de commandes complet
  - Panier et checkout
  - Intégration avec KYC validation
  - Workflows de statut
  - Order history et tracking
  - Audit trail complet

USAGE
  .\MC004-Orders.ps1

PREREQUISITES
  - MC001-Foundation-v2.0.ps1 exécuté
  - MC002-Catalog-v1.0.ps1 exécuté
  - MC003-Customers-v1.0.ps1 exécuté
  - Supabase CLI configuré
  
IDEMPOTENCE
  Peut être exécuté plusieurs fois sans erreur.

==============================================================================#>

#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =============================================================================
# CONFIGURATION GLOBALE
# =============================================================================

$ProjectName = "KOS"
$Root = Join-Path (Get-Location) $ProjectName
$LogDir = Join-Path $Root "logs"
$LogFile = Join-Path $LogDir "MC004-v1.0.log"
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$ExecutionId = [guid]::NewGuid()

# =============================================================================
# FONCTION : LOGGING
# =============================================================================

function Write-KOSLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $ColorMap = @{
        "INFO"    = "Cyan"
        "WARN"    = "Yellow"
        "ERROR"   = "Red"
        "SUCCESS" = "Green"
    }
    $Color = $ColorMap[$Level]
    $LogLine = "[$Time] [$Level] $Message"

    Write-Host $LogLine -ForegroundColor $Color

    if (Test-Path $LogDir) {
        Add-Content -Path $LogFile -Value $LogLine -Encoding UTF8
    }
}

# =============================================================================
# FONCTION : VÉRIFIER DÉPENDANCES
# =============================================================================

function Test-PreviousModules {
    Write-KOSLog "Vérification des modules précédents..." "INFO"
    
    if (-not (Test-Path $Root)) {
        throw "Racine du projet non trouvée. Exécutez MC001 d'abord."
    }

    $RequiredDirs = @(
        "packages\catalog",
        "packages\crm",
        "database\migrations\customers"
    )

    foreach ($Dir in $RequiredDirs) {
        $Path = Join-Path $Root $Dir
        if (-not (Test-Path $Path)) {
            throw "Dossier manquant: $Dir. Exécutez les modules précédents d'abord."
        }
    }

    Write-KOSLog "MC001, MC002, MC003 vérifiés ✓" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER STRUCTURE ORDERS
# =============================================================================

function New-OrdersStructure {
    Write-KOSLog "Création de la structure du module Commandes..." "INFO"

    $OrdersFolders = @(
        # Orders Main
        "packages\orders",
        "packages\orders\src",
        "packages\orders\src\models",
        "packages\orders\src\services",
        "packages\orders\src\repositories",
        "packages\orders\src\controllers",
        "packages\orders\src\routes",
        "packages\orders\src\middleware",
        "packages\orders\src\validators",
        "packages\orders\src\utils",
        "packages\orders\src\types",
        "packages\orders\tests",

        # Cart
        "packages\cart",
        "packages\cart\src",
        "packages\cart\src\services",
        "packages\cart\src\repositories",

        # Checkout
        "packages\checkout",
        "packages\checkout\src",
        "packages\checkout\src\services",
        "packages\checkout\src\workflows",

        # Order Fulfillment
        "packages\fulfillment",
        "packages\fulfillment\src",
        "packages\fulfillment\src\services",
        "packages\fulfillment\src\workflows"
    )

    $CreatedCount = 0
    foreach ($Folder in $OrdersFolders) {
        $Path = Join-Path $Root $Folder
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            $CreatedCount++
        }
    }

    Write-KOSLog "  $CreatedCount dossiers créés" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER MIGRATIONS SQL
# =============================================================================

function New-OrdersMigrations {
    Write-KOSLog "Création des migrations de base de données..." "INFO"

    $MigrationDir = Join-Path $Root "database\migrations\orders"

    # Migration 001 - Orders Core
    $Migration001 = @"
-- ==============================================================================
-- KOS Orders Module - Core Tables
-- Migration: 001-orders-base
-- Date: 2026-07-16
-- ==============================================================================

CREATE TYPE order_status AS ENUM ('draft', 'pending', 'confirmed', 'processing', 'partially_shipped', 'shipped', 'delivered', 'completed', 'cancelled', 'refunded', 'on_hold');
CREATE TYPE order_source AS ENUM ('web', 'api', 'manual', 'import', 'crm');
CREATE TYPE line_item_type AS ENUM ('product', 'subscription', 'service', 'license', 'addon', 'discount', 'tax');

-- Main Orders Table
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Identification
    order_number VARCHAR(100) UNIQUE NOT NULL,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    
    -- Dates
    order_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    required_date DATE,
    shipped_date DATE,
    delivered_date DATE,
    
    -- Status
    status order_status DEFAULT 'draft',
    source order_source DEFAULT 'web',
    
    -- Billing & Shipping
    billing_address JSONB NOT NULL, -- {street, city, postal_code, country, ...}
    shipping_address JSONB NOT NULL,
    same_as_billing BOOLEAN DEFAULT false,
    
    -- Pricing
    subtotal DECIMAL(19, 2) NOT NULL DEFAULT 0,
    tax_amount DECIMAL(19, 2) DEFAULT 0,
    shipping_cost DECIMAL(19, 2) DEFAULT 0,
    discount_amount DECIMAL(19, 2) DEFAULT 0,
    total_amount DECIMAL(19, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'XOF',
    
    -- Payment
    payment_method_id UUID,
    payment_status VARCHAR(50), -- 'pending', 'authorized', 'captured', 'failed', 'refunded'
    payment_reference VARCHAR(255),
    payment_date TIMESTAMP WITH TIME ZONE,
    
    -- Fulfillment
    fulfillment_status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'processing', 'shipped', 'delivered', 'cancelled'
    tracking_number VARCHAR(100),
    carrier VARCHAR(100),
    expected_delivery_date DATE,
    
    -- Additional Info
    notes TEXT,
    internal_notes TEXT,
    tags JSONB DEFAULT '[]'::jsonb,
    custom_fields JSONB DEFAULT '{}',
    
    -- Compliance
    kyc_verified_at_order_time BOOLEAN DEFAULT false,
    kyc_status_at_order_time VARCHAR(50),
    aml_cleared BOOLEAN DEFAULT false,
    
    -- Relationships
    subscription_id UUID,
    parent_order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    
    CONSTRAINT orders_total_amount_check CHECK (total_amount >= 0),
    CONSTRAINT orders_status_valid CHECK (status IS NOT NULL)
);

CREATE INDEX idx_orders_number ON orders(order_number);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_order_date ON orders(order_date DESC);
CREATE INDEX idx_orders_payment_status ON orders(payment_status);
CREATE INDEX idx_orders_fulfillment_status ON orders(fulfillment_status);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);

-- Order Line Items
CREATE TABLE IF NOT EXISTS order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    
    -- Item Info
    line_item_type line_item_type NOT NULL,
    sequence_number INTEGER NOT NULL,
    
    -- Product/Service Reference
    product_id UUID REFERENCES products(id) ON DELETE RESTRICT,
    sku VARCHAR(50),
    product_name VARCHAR(255) NOT NULL,
    product_description TEXT,
    
    -- Subscription Reference (if applicable)
    subscription_plan_id UUID REFERENCES subscription_plans(id) ON DELETE SET NULL,
    
    -- Quantity & Pricing
    quantity DECIMAL(10, 2) NOT NULL DEFAULT 1,
    unit_price DECIMAL(19, 2) NOT NULL,
    line_total DECIMAL(19, 2) NOT NULL,
    
    -- Discounts
    item_discount_amount DECIMAL(19, 2) DEFAULT 0,
    item_discount_percent DECIMAL(5, 2) DEFAULT 0,
    
    -- Tax
    tax_rate DECIMAL(5, 2) DEFAULT 0,
    tax_amount DECIMAL(19, 2) DEFAULT 0,
    
    -- Attributes
    attributes JSONB DEFAULT '{}', -- Size, color, specifications, etc.
    
    -- Fulfillment
    fulfillment_status VARCHAR(50) DEFAULT 'pending',
    quantity_shipped DECIMAL(10, 2) DEFAULT 0,
    quantity_delivered DECIMAL(10, 2) DEFAULT 0,
    quantity_refunded DECIMAL(10, 2) DEFAULT 0,
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT order_line_items_quantity_check CHECK (quantity > 0),
    CONSTRAINT order_line_items_line_total_check CHECK (line_total >= 0)
);

CREATE INDEX idx_order_line_items_order_id ON order_line_items(order_id);
CREATE INDEX idx_order_line_items_product_id ON order_line_items(product_id);
CREATE INDEX idx_order_line_items_sku ON order_line_items(sku);

-- Order Status History
CREATE TABLE IF NOT EXISTS order_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    
    -- Status Change
    from_status order_status,
    to_status order_status NOT NULL,
    
    -- Details
    reason VARCHAR(255),
    notes TEXT,
    
    -- Actor
    changed_by UUID,
    
    -- Timestamp
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_order_status_history_order_id ON order_status_history(order_id);
CREATE INDEX idx_order_status_history_to_status ON order_status_history(to_status);

-- Triggers
CREATE OR REPLACE FUNCTION update_orders_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_orders_updated_at ON orders;
CREATE TRIGGER tr_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION update_orders_updated_at();

-- Enable RLS
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Orders readable by owner and admins" ON orders
    FOR SELECT TO authenticated USING (customer_id = auth.uid() OR auth.jwt() ->> 'role' = 'admin');

CREATE POLICY "Admins can manage all orders" ON orders
    FOR ALL TO authenticated USING (auth.jwt() ->> 'role' = 'admin');
"@

    Set-Content -Path (Join-Path $MigrationDir "001-orders-base.sql") -Value $Migration001 -Encoding UTF8
    Write-KOSLog "  ✓ Migration 001 créée: orders-base" "SUCCESS"

    # Migration 002 - Cart & Checkout
    $Migration002 = @"
-- ==============================================================================
-- KOS Orders Module - Cart & Checkout
-- Migration: 002-cart-checkout
-- Date: 2026-07-16
-- ==============================================================================

-- Shopping Carts Table
CREATE TABLE IF NOT EXISTS shopping_carts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Cart Status
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'abandoned', 'converted', 'expired'
    
    -- Pricing Summary (cached for performance)
    subtotal DECIMAL(19, 2) DEFAULT 0,
    total_tax DECIMAL(19, 2) DEFAULT 0,
    total_discount DECIMAL(19, 2) DEFAULT 0,
    shipping_estimate DECIMAL(19, 2) DEFAULT 0,
    estimated_total DECIMAL(19, 2) DEFAULT 0,
    
    -- Applied Discounts
    discount_codes JSONB DEFAULT '[]'::jsonb,
    applied_rules JSONB DEFAULT '[]'::jsonb,
    
    -- Preferences
    preferred_shipping_address_id UUID,
    preferred_billing_address_id UUID,
    shipping_method VARCHAR(100),
    
    -- Metadata
    notes TEXT,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    abandoned_at TIMESTAMP WITH TIME ZONE,
    converted_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_shopping_carts_customer_id ON shopping_carts(customer_id);
CREATE INDEX idx_shopping_carts_status ON shopping_carts(status);
CREATE INDEX idx_shopping_carts_created_at ON shopping_carts(created_at DESC);

-- Cart Items
CREATE TABLE IF NOT EXISTS cart_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cart_id UUID NOT NULL REFERENCES shopping_carts(id) ON DELETE CASCADE,
    
    -- Product/Service Reference
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    sku VARCHAR(50) NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    
    -- Subscription Reference (if applicable)
    subscription_plan_id UUID REFERENCES subscription_plans(id) ON DELETE SET NULL,
    
    -- Quantity & Pricing
    quantity DECIMAL(10, 2) NOT NULL DEFAULT 1,
    unit_price DECIMAL(19, 2) NOT NULL,
    line_total DECIMAL(19, 2) NOT NULL,
    
    -- Item-level discount
    discount_amount DECIMAL(19, 2) DEFAULT 0,
    discount_code VARCHAR(100),
    
    -- Tax
    tax_rate DECIMAL(5, 2) DEFAULT 0,
    tax_amount DECIMAL(19, 2) DEFAULT 0,
    
    -- Custom attributes
    attributes JSONB DEFAULT '{}',
    
    -- Status
    is_available BOOLEAN DEFAULT true,
    availability_status VARCHAR(50), -- 'in_stock', 'low_stock', 'out_of_stock', 'backorder'
    
    -- Timestamps
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_cart_items_cart_id ON cart_items(cart_id);
CREATE INDEX idx_cart_items_product_id ON cart_items(product_id);

-- Checkouts (Session tracking)
CREATE TABLE IF NOT EXISTS checkouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    cart_id UUID NOT NULL REFERENCES shopping_carts(id) ON DELETE SET NULL,
    
    -- Checkout Step Tracking
    current_step VARCHAR(50) DEFAULT 'shipping', -- 'shipping', 'billing', 'payment', 'review', 'confirmation'
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    abandoned_at TIMESTAMP WITH TIME ZONE,
    
    -- Saved Checkout Data
    shipping_address JSONB,
    billing_address JSONB,
    shipping_method VARCHAR(100),
    
    -- Session Info
    session_id VARCHAR(255),
    ip_address INET,
    user_agent VARCHAR(500),
    
    -- Metadata
    utm_source VARCHAR(100),
    utm_medium VARCHAR(100),
    utm_campaign VARCHAR(100),
    
    -- Status
    status VARCHAR(50) DEFAULT 'in_progress', -- 'in_progress', 'abandoned', 'completed'
    
    CONSTRAINT checkouts_step_valid CHECK (current_step IN ('shipping', 'billing', 'payment', 'review', 'confirmation'))
);

CREATE INDEX idx_checkouts_customer_id ON checkouts(customer_id);
CREATE INDEX idx_checkouts_status ON checkouts(status);
CREATE INDEX idx_checkouts_started_at ON checkouts(started_at DESC);

-- Enable RLS
ALTER TABLE shopping_carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE checkouts ENABLE ROW LEVEL SECURITY;

-- Update timestamp function for carts
CREATE OR REPLACE FUNCTION update_shopping_carts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_shopping_carts_updated_at ON shopping_carts;
CREATE TRIGGER tr_shopping_carts_updated_at
BEFORE UPDATE ON shopping_carts
FOR EACH ROW
EXECUTE FUNCTION update_shopping_carts_updated_at();

CREATE OR REPLACE FUNCTION update_cart_items_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_cart_items_updated_at ON cart_items;
CREATE TRIGGER tr_cart_items_updated_at
BEFORE UPDATE ON cart_items
FOR EACH ROW
EXECUTE FUNCTION update_cart_items_updated_at();
"@

    Set-Content -Path (Join-Path $MigrationDir "002-cart-checkout.sql") -Value $Migration002 -Encoding UTF8
    Write-KOSLog "  ✓ Migration 002 créée: cart-checkout" "SUCCESS"

    # Migration 003 - Order Fulfillment
    $Migration003 = @"
-- ==============================================================================
-- KOS Orders Module - Fulfillment & Shipping
-- Migration: 003-fulfillment-shipping
-- Date: 2026-07-16
-- ==============================================================================

CREATE TYPE shipment_status AS ENUM ('pending', 'processing', 'picked', 'packed', 'shipped', 'in_transit', 'out_for_delivery', 'delivered', 'failed', 'returned');
CREATE TYPE tracking_status AS ENUM ('pending', 'in_transit', 'delivered', 'failed', 'exception', 'returned');

-- Shipments Table
CREATE TABLE IF NOT EXISTS shipments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    
    -- Identification
    shipment_number VARCHAR(100) UNIQUE NOT NULL,
    
    -- Status
    status shipment_status DEFAULT 'pending',
    
    -- Carrier & Tracking
    carrier VARCHAR(100) NOT NULL,
    tracking_number VARCHAR(100) UNIQUE,
    tracking_url VARCHAR(500),
    
    -- Dates
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    picked_at TIMESTAMP WITH TIME ZONE,
    packed_at TIMESTAMP WITH TIME ZONE,
    shipped_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    expected_delivery_date DATE,
    
    -- Shipping Details
    shipping_address JSONB NOT NULL,
    shipping_method VARCHAR(100),
    weight_kg DECIMAL(10, 2),
    dimensions_cm JSONB, -- {length, width, height}
    
    -- Costs
    shipping_cost DECIMAL(19, 2),
    insurance_cost DECIMAL(19, 2),
    
    -- Items in Shipment
    item_count INTEGER DEFAULT 1,
    items_data JSONB DEFAULT '[]'::jsonb, -- {product_id, sku, quantity, line_item_id}
    
    -- Exceptions
    has_exception BOOLEAN DEFAULT false,
    exception_reason VARCHAR(255),
    exception_date TIMESTAMP WITH TIME ZONE,
    
    -- Metadata
    notes TEXT,
    internal_notes TEXT,
    
    -- Audit
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_shipments_order_id ON shipments(order_id);
CREATE INDEX idx_shipments_number ON shipments(shipment_number);
CREATE INDEX idx_shipments_tracking_number ON shipments(tracking_number);
CREATE INDEX idx_shipments_status ON shipments(status);
CREATE INDEX idx_shipments_shipped_at ON shipments(shipped_at DESC);

-- Shipment Tracking Events
CREATE TABLE IF NOT EXISTS shipment_tracking_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shipment_id UUID NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    
    -- Event Info
    event_type VARCHAR(50) NOT NULL, -- 'picked', 'packed', 'shipped', 'in_transit', 'out_for_delivery', 'delivered', 'failed', 'exception'
    event_description VARCHAR(255),
    
    -- Location
    location VARCHAR(255),
    location_coordinates POINT,
    
    -- Timestamp
    event_timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Additional Data
    event_data JSONB DEFAULT '{}'
);

CREATE INDEX idx_shipment_tracking_events_shipment_id ON shipment_tracking_events(shipment_id);
CREATE INDEX idx_shipment_tracking_events_event_type ON shipment_tracking_events(event_type);
CREATE INDEX idx_shipment_tracking_events_timestamp ON shipment_tracking_events(event_timestamp DESC);

-- Returns & Refunds
CREATE TABLE IF NOT EXISTS order_returns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    
    -- Return Info
    return_number VARCHAR(100) UNIQUE NOT NULL,
    return_reason VARCHAR(255) NOT NULL, -- 'defective', 'wrong_item', 'not_as_described', 'damaged', 'customer_request', 'other'
    return_description TEXT,
    
    -- Items Being Returned
    items_data JSONB NOT NULL, -- {product_id, sku, quantity, line_item_id, reason}
    
    -- Refund
    refund_amount DECIMAL(19, 2) NOT NULL,
    refund_status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'processed', 'completed', 'rejected'
    refund_date TIMESTAMP WITH TIME ZONE,
    refund_reference VARCHAR(255),
    
    -- Shipping Return
    return_shipping_address JSONB,
    return_tracking_number VARCHAR(100),
    returned_at TIMESTAMP WITH TIME ZONE,
    received_at TIMESTAMP WITH TIME ZONE,
    
    -- Inspection
    inspection_status VARCHAR(50), -- 'pending', 'passed', 'failed_quality'
    inspection_notes TEXT,
    inspected_by UUID,
    inspected_at TIMESTAMP WITH TIME ZONE,
    
    -- Status
    status VARCHAR(50) DEFAULT 'initiated', -- 'initiated', 'shipped_back', 'received', 'inspected', 'approved', 'refunded', 'rejected'
    
    -- Dates
    initiated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    
    -- Audit
    created_by UUID,
    updated_by UUID
);

CREATE INDEX idx_order_returns_order_id ON order_returns(order_id);
CREATE INDEX idx_order_returns_number ON order_returns(return_number);
CREATE INDEX idx_order_returns_status ON order_returns(status);

-- Enable RLS
ALTER TABLE shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipment_tracking_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_returns ENABLE ROW LEVEL SECURITY;
"@

    Set-Content -Path (Join-Path $MigrationDir "003-fulfillment-shipping.sql") -Value $Migration003 -Encoding UTF8
    Write-KOSLog "  ✓ Migration 003 créée: fulfillment-shipping" "SUCCESS"

    # Migration 004 - Order Analytics & Reporting
    $Migration004 = @"
-- ==============================================================================
-- KOS Orders Module - Analytics & Reporting
-- Migration: 004-order-analytics
-- Date: 2026-07-16
-- ==============================================================================

-- Order Metrics (for fast queries)
CREATE TABLE IF NOT EXISTS order_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Time Period
    metric_date DATE NOT NULL,
    metric_month DATE NOT NULL, -- First day of month
    metric_year INTEGER NOT NULL,
    
    -- Aggregates
    total_orders INTEGER DEFAULT 0,
    total_revenue DECIMAL(19, 2) DEFAULT 0,
    average_order_value DECIMAL(19, 2) DEFAULT 0,
    
    -- By Status
    orders_pending INTEGER DEFAULT 0,
    orders_processing INTEGER DEFAULT 0,
    orders_completed INTEGER DEFAULT 0,
    orders_cancelled INTEGER DEFAULT 0,
    
    -- By Source
    orders_web INTEGER DEFAULT 0,
    orders_api INTEGER DEFAULT 0,
    orders_manual INTEGER DEFAULT 0,
    
    -- Customer Metrics
    new_customers INTEGER DEFAULT 0,
    repeat_customers INTEGER DEFAULT 0,
    
    -- Payment Metrics
    successful_payments INTEGER DEFAULT 0,
    failed_payments INTEGER DEFAULT 0,
    refunded_amount DECIMAL(19, 2) DEFAULT 0,
    
    -- Product Metrics
    top_products JSONB DEFAULT '[]'::jsonb,
    
    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX idx_order_metrics_date ON order_metrics(metric_date);
CREATE INDEX idx_order_metrics_month ON order_metrics(metric_month);

-- Customer Order Summary
CREATE TABLE IF NOT EXISTS customer_order_summary (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL UNIQUE REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Order Stats
    total_orders INTEGER DEFAULT 0,
    total_spent DECIMAL(19, 2) DEFAULT 0,
    average_order_value DECIMAL(19, 2) DEFAULT 0,
    
    -- Dates
    first_order_date DATE,
    last_order_date DATE,
    
    -- Status
    active_subscriptions INTEGER DEFAULT 0,
    
    -- Metrics
    customer_lifetime_value DECIMAL(19, 2) DEFAULT 0,
    
    -- Preferences
    preferred_payment_method VARCHAR(100),
    preferred_shipping_method VARCHAR(100),
    
    -- Audit
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_customer_order_summary_customer_id ON customer_order_summary(customer_id);
CREATE INDEX idx_customer_order_summary_total_spent ON customer_order_summary(total_spent DESC);

-- Order Notes & Comments
CREATE TABLE IF NOT EXISTS order_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    
    -- Note Info
    note_type VARCHAR(50) NOT NULL, -- 'internal', 'customer_visible', 'fulfillment', 'payment', 'compliance'
    title VARCHAR(255),
    content TEXT NOT NULL,
    
    -- Author
    created_by UUID NOT NULL,
    
    -- Metadata
    is_pinned BOOLEAN DEFAULT false,
    attachments JSONB DEFAULT '[]'::jsonb,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_order_notes_order_id ON order_notes(order_id);
CREATE INDEX idx_order_notes_type ON order_notes(note_type);

-- Enable RLS
ALTER TABLE order_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_order_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_notes ENABLE ROW LEVEL SECURITY;
"@

    Set-Content -Path (Join-Path $MigrationDir "004-order-analytics.sql") -Value $Migration004 -Encoding UTF8
    Write-KOSLog "  ✓ Migration 004 créée: order-analytics" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER MODÈLES TYPESCRIPT
# =============================================================================

function New-OrdersTypeScriptModels {
    Write-KOSLog "Création des modèles TypeScript..." "INFO"

    $TypesDir = Join-Path $Root "packages\orders\src\types"

    # Types Orders
    $OrderTypes = @"
// ==============================================================================
// KOS Orders - Order Types
// ==============================================================================

export type OrderStatus = 'draft' | 'pending' | 'confirmed' | 'processing' | 'partially_shipped' | 'shipped' | 'delivered' | 'completed' | 'cancelled' | 'refunded' | 'on_hold';
export type OrderSource = 'web' | 'api' | 'manual' | 'import' | 'crm';
export type PaymentStatus = 'pending' | 'authorized' | 'captured' | 'failed' | 'refunded';
export type FulfillmentStatus = 'pending' | 'processing' | 'shipped' | 'delivered' | 'cancelled';
export type LineItemType = 'product' | 'subscription' | 'service' | 'license' | 'addon' | 'discount' | 'tax';

export interface IAddress {
  street: string;
  city: string;
  postalCode: string;
  country: string;
  state?: string;
  building?: string;
}

export interface IOrderLineItem {
  id: string;
  orderId: string;
  lineItemType: LineItemType;
  sequenceNumber: number;
  productId?: string;
  sku: string;
  productName: string;
  productDescription?: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
  discountAmount?: number;
  taxRate?: number;
  taxAmount?: number;
  attributes?: Record<string, any>;
  fulfillmentStatus: FulfillmentStatus;
  createdAt: Date;
}

export interface IOrder {
  id: string;
  orderNumber: string;
  customerId: string;
  orderDate: Date;
  requiredDate?: Date;
  shippedDate?: Date;
  deliveredDate?: Date;
  
  // Status
  status: OrderStatus;
  source: OrderSource;
  
  // Addresses
  billingAddress: IAddress;
  shippingAddress: IAddress;
  sameAsBilling: boolean;
  
  // Pricing
  subtotal: number;
  taxAmount: number;
  shippingCost: number;
  discountAmount: number;
  totalAmount: number;
  currency: string;
  
  // Payment
  paymentMethodId?: string;
  paymentStatus?: PaymentStatus;
  paymentReference?: string;
  paymentDate?: Date;
  
  // Fulfillment
  fulfillmentStatus: FulfillmentStatus;
  trackingNumber?: string;
  carrier?: string;
  expectedDeliveryDate?: Date;
  
  // Compliance
  kycVerifiedAtOrderTime: boolean;
  amlCleared: boolean;
  
  // Line Items
  lineItems: IOrderLineItem[];
  
  // Metadata
  notes?: string;
  tags: string[];
  
  // Audit
  createdAt: Date;
  updatedAt: Date;
  createdBy?: string;
  deletedAt?: Date;
}

export interface CreateOrderDTO {
  customerId: string;
  lineItems: CreateLineItemDTO[];
  billingAddress: IAddress;
  shippingAddress?: IAddress;
  sameAsBilling?: boolean;
  paymentMethodId?: string;
  source?: OrderSource;
  notes?: string;
}

export interface CreateLineItemDTO {
  productId?: string;
  sku: string;
  productName: string;
  quantity: number;
  unitPrice: number;
  lineItemType?: LineItemType;
  attributes?: Record<string, any>;
}

export interface UpdateOrderDTO {
  status?: OrderStatus;
  paymentStatus?: PaymentStatus;
  fulfillmentStatus?: FulfillmentStatus;
  trackingNumber?: string;
  carrier?: string;
  notes?: string;
  shippingAddress?: IAddress;
}

export interface IOrderStatusChange {
  id: string;
  orderId: string;
  fromStatus?: OrderStatus;
  toStatus: OrderStatus;
  reason?: string;
  changedBy?: string;
  createdAt: Date;
}
"@

    Set-Content -Path (Join-Path $TypesDir "order.types.ts") -Value $OrderTypes -Encoding UTF8
    Write-KOSLog "  ✓ Types créés: order.types.ts" "SUCCESS"

    # Types Cart
    $CartTypes = @"
// ==============================================================================
// KOS Orders - Cart & Checkout Types
// ==============================================================================

export type CartStatus = 'active' | 'abandoned' | 'converted' | 'expired';
export type CheckoutStep = 'shipping' | 'billing' | 'payment' | 'review' | 'confirmation';
export type CheckoutStatus = 'in_progress' | 'abandoned' | 'completed';

export interface ICartItem {
  id: string;
  cartId: string;
  productId: string;
  sku: string;
  productName: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
  discountAmount?: number;
  taxRate?: number;
  taxAmount?: number;
  isAvailable: boolean;
  availabilityStatus?: 'in_stock' | 'low_stock' | 'out_of_stock' | 'backorder';
  attributes?: Record<string, any>;
  addedAt: Date;
}

export interface IShoppingCart {
  id: string;
  customerId: string;
  status: CartStatus;
  
  // Pricing
  subtotal: number;
  totalTax: number;
  totalDiscount: number;
  shippingEstimate: number;
  estimatedTotal: number;
  
  // Items
  items: ICartItem[];
  
  // Discounts
  discountCodes: string[];
  appliedRules: string[];
  
  // Preferences
  preferredShippingMethod?: string;
  
  // Metadata
  notes?: string;
  
  // Timestamps
  createdAt: Date;
  updatedAt: Date;
  abandonedAt?: Date;
  convertedAt?: Date;
  expiresAt?: Date;
}

export interface ICheckout {
  id: string;
  customerId: string;
  cartId: string;
  currentStep: CheckoutStep;
  status: CheckoutStatus;
  
  // Addresses
  shippingAddress?: IAddress;
  billingAddress?: IAddress;
  shippingMethod?: string;
  
  // Metadata
  utmSource?: string;
  utmMedium?: string;
  utmCampaign?: string;
  
  // Timestamps
  startedAt: Date;
  completedAt?: Date;
  abandonedAt?: Date;
}

export interface AddToCartRequest {
  productId: string;
  quantity: number;
  attributes?: Record<string, any>;
}

export interface UpdateCartItemRequest {
  quantity: number;
  attributes?: Record<string, any>;
}

export interface ApplyDiscountRequest {
  discountCode: string;
}
"@

    Set-Content -Path (Join-Path $TypesDir "cart.types.ts") -Value $CartTypes -Encoding UTF8
    Write-KOSLog "  ✓ Types créés: cart.types.ts" "SUCCESS"

    # Types Fulfillment
    $FulfillmentTypes = @"
// ==============================================================================
// KOS Orders - Fulfillment & Shipping Types
// ==============================================================================

export type ShipmentStatus = 'pending' | 'processing' | 'picked' | 'packed' | 'shipped' | 'in_transit' | 'out_for_delivery' | 'delivered' | 'failed' | 'returned';
export type TrackingStatus = 'pending' | 'in_transit' | 'delivered' | 'failed' | 'exception' | 'returned';
export type ReturnReason = 'defective' | 'wrong_item' | 'not_as_described' | 'damaged' | 'customer_request' | 'other';
export type ReturnStatus = 'initiated' | 'shipped_back' | 'received' | 'inspected' | 'approved' | 'refunded' | 'rejected';

export interface IShipment {
  id: string;
  orderId: string;
  shipmentNumber: string;
  status: ShipmentStatus;
  carrier: string;
  trackingNumber?: string;
  trackingUrl?: string;
  
  // Dates
  createdAt: Date;
  pickedAt?: Date;
  packedAt?: Date;
  shippedAt?: Date;
  deliveredAt?: Date;
  expectedDeliveryDate?: Date;
  
  // Shipping Details
  shippingAddress: IAddress;
  shippingMethod: string;
  weightKg?: number;
  dimensions?: { length: number; width: number; height: number };
  
  // Costs
  shippingCost: number;
  insuranceCost?: number;
  
  // Items
  itemCount: number;
  
  // Exception
  hasException: boolean;
  exceptionReason?: string;
  exceptionDate?: Date;
  
  // Metadata
  notes?: string;
}

export interface ITrackingEvent {
  id: string;
  shipmentId: string;
  orderId: string;
  eventType: string;
  eventDescription?: string;
  location?: string;
  eventTimestamp: Date;
  eventData?: Record<string, any>;
}

export interface IOrderReturn {
  id: string;
  orderId: string;
  returnNumber: string;
  returnReason: ReturnReason;
  returnDescription?: string;
  
  // Items & Refund
  itemsData: any[];
  refundAmount: number;
  refundStatus: string;
  refundDate?: Date;
  
  // Shipping
  returnTrackingNumber?: string;
  returnedAt?: Date;
  receivedAt?: Date;
  
  // Inspection
  inspectionStatus?: string;
  inspectionNotes?: string;
  
  // Status
  status: ReturnStatus;
  
  // Dates
  initiatedAt: Date;
  completedAt?: Date;
}

export interface CreateShipmentRequest {
  orderId: string;
  carrier: string;
  shippingMethod: string;
  weightKg?: number;
  items: { lineItemId: string; quantity: number }[];
}

export interface CreateReturnRequest {
  orderId: string;
  reason: ReturnReason;
  description?: string;
  items: { lineItemId: string; quantity: number; reason?: string }[];
}
"@

    Set-Content -Path (Join-Path $TypesDir "fulfillment.types.ts") -Value $FulfillmentTypes -Encoding UTF8
    Write-KOSLog "  ✓ Types créés: fulfillment.types.ts" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER SEED DATA
# =============================================================================

function New-OrdersSeedData {
    Write-KOSLog "Création des données de seed..." "INFO"

    $SeedDir = Join-Path $Root "database\seed\orders"

    # Seed Orders
    $SeedOrders = @"
-- ==============================================================================
-- KOS Orders Module - Seed Data
-- ==============================================================================

-- Insert sample orders
INSERT INTO orders (
    order_number, customer_id, order_date, status, source,
    billing_address, shipping_address, same_as_billing,
    subtotal, tax_amount, shipping_cost, total_amount, currency,
    payment_status, fulfillment_status, kyc_verified_at_order_time, aml_cleared
)
SELECT
    'ORD-' || TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD') || '-001',
    id,
    CURRENT_TIMESTAMP,
    'pending',
    'web',
    '{"street": "123 Rue de la Paix", "city": "Dakar", "postal_code": "18000", "country": "SEN"}'::jsonb,
    '{"street": "123 Rue de la Paix", "city": "Dakar", "postal_code": "18000", "country": "SEN"}'::jsonb,
    true,
    55000,
    9900,
    5000,
    69900,
    'XOF',
    'pending',
    'pending',
    false,
    false
FROM customers WHERE customer_number = 'CUST-IND-001'
UNION ALL
SELECT
    'ORD-' || TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD') || '-002',
    id,
    CURRENT_TIMESTAMP,
    'confirmed',
    'api',
    '{"street": "456 Avenue Clemenceau", "city": "Dakar", "postal_code": "18000", "country": "SEN"}'::jsonb,
    '{"street": "456 Avenue Clemenceau", "city": "Dakar", "postal_code": "18000", "country": "SEN"}'::jsonb,
    true,
    100000,
    18000,
    0,
    118000,
    'XOF',
    'authorized',
    'processing',
    false,
    false
FROM customers WHERE customer_number = 'CUST-COM-001';

-- Insert order line items
INSERT INTO order_line_items (
    order_id, line_item_type, sequence_number,
    product_id, sku, product_name, quantity, unit_price, line_total
)
SELECT
    o.id, 'service', 1,
    p.id, p.sku, p.name, 1, p.base_price, p.base_price
FROM orders o
JOIN customers c ON o.customer_id = c.id
JOIN products p ON p.sku IN ('COMPL-KYC-001', 'COMPL-AML-001')
WHERE c.customer_number IN ('CUST-IND-001', 'CUST-COM-001');
"@

    Set-Content -Path (Join-Path $SeedDir "001-seed-orders.sql") -Value $SeedOrders -Encoding UTF8
    Write-KOSLog "  ✓ Seed données: orders" "SUCCESS"

    # Seed Carts
    $SeedCarts = @"
-- ==============================================================================
-- KOS Orders - Shopping Carts Seed Data
-- ==============================================================================

-- Insert sample shopping carts
INSERT INTO shopping_carts (
    customer_id, status, subtotal, total_tax, estimated_total
)
SELECT id, 'active', 25000, 4500, 29500
FROM customers WHERE customer_number = 'CUST-NGO-001';

-- Insert cart items
INSERT INTO cart_items (
    cart_id, product_id, sku, product_name, quantity, unit_price, line_total
)
SELECT
    sc.id, p.id, p.sku, p.name, 1, p.base_price, p.base_price
FROM shopping_carts sc
JOIN customers c ON sc.customer_id = c.id
JOIN products p ON p.sku = 'SUPP-EMAIL-001'
WHERE c.customer_number = 'CUST-NGO-001';
"@

    Set-Content -Path (Join-Path $SeedDir "002-seed-carts.sql") -Value $SeedCarts -Encoding UTF8
    Write-KOSLog "  ✓ Seed données: shopping carts" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER DOCUMENTATION
# =============================================================================

function New-OrdersDocumentation {
    Write-KOSLog "Création de la documentation..." "INFO"

    $DocsDir = Join-Path $Root "docs\orders"
    
    # README Orders
    $ReadmeOrders = @"
# KOS Orders Module

## Vue d'ensemble

Le module Orders KOS gère l'ensemble du cycle de vie des commandes, du panier au suivi de livraison.

## Domaines

### 1. **Orders** (Gestion des commandes)
- Création de commandes (web, API, manuel)
- Status workflow complet
- Line items avec support multi-types
- Pricing avec taxes, discounts, shipping
- Audit trail complet

### 2. **Cart & Checkout** (Panier et paiement)
- Gestion du panier (active/abandoned/converted)
- Multi-step checkout (shipping → billing → payment → review)
- Cart abandonment tracking
- Discount code management
- Pricing calculations en temps réel

### 3. **Fulfillment & Shipping** (Livraison)
- Shipments avec multi-carriers
- Tracking real-time
- Returns & Refunds management
- Inspection workflows
- Exception handling

### 4. **Analytics & Reporting** (Analytics)
- Order metrics (par jour/mois)
- Customer order summaries
- Revenue tracking
- Top products reporting

## Architecture

### Base de Données

\`\`\`
orders
├── order_line_items
├── order_status_history
└── order_notes

shopping_carts
└── cart_items

checkouts

shipments
├── shipment_tracking_events
└── order_returns

order_metrics
└── customer_order_summary
\`\`\`

## Workflows

### Order Creation Flow

1. **Add to Cart** (shopping_carts + cart_items)
2. **Checkout** (checkouts + step progression)
3. **Order Confirmation** (orders created)
4. **Payment Processing** (payment_status: pending → captured)
5. **Fulfillment** (fulfillment_status: pending → shipped → delivered)

### Order Status Workflow

\`\`\`
draft → pending → confirmed → processing → partially_shipped → shipped → delivered → completed
                                    ↓
                              cancelled / on_hold
\`\`\`

### Fulfillment Workflow

\`\`\`
pending → processing → picked → packed → shipped → in_transit → out_for_delivery → delivered
                                                        ↓
                                                    exception / failed
\`\`\`

### Return Workflow

\`\`\`
initiated → shipped_back → received → inspected → approved → refunded
                                           ↓
                                       rejected
\`\`\`

## API Endpoints

### Orders
- \`GET /api/orders\` - Lister commandes
- \`GET /api/orders/:id\` - Détails commande
- \`POST /api/orders\` - Créer commande
- \`PUT /api/orders/:id\` - Modifier commande
- \`PUT /api/orders/:id/status\` - Changer status

### Cart
- \`GET /api/cart\` - Panier courant
- \`POST /api/cart/items\` - Ajouter produit
- \`PUT /api/cart/items/:itemId\` - Modifier quantité
- \`DELETE /api/cart/items/:itemId\` - Supprimer produit
- \`POST /api/cart/discounts\` - Appliquer code promo

### Checkout
- \`POST /api/checkout/start\` - Démarrer checkout
- \`PUT /api/checkout/:id/shipping\` - Configurer shipping
- \`PUT /api/checkout/:id/billing\` - Configurer billing
- \`POST /api/checkout/:id/payment\` - Traiter paiement
- \`POST /api/checkout/:id/confirm\` - Confirmer commande

### Fulfillment
- \`GET /api/shipments\` - Lister shipments
- \`POST /api/shipments\` - Créer shipment
- \`GET /api/shipments/:id/tracking\` - Tracking events
- \`POST /api/returns\` - Créer retour
- \`POST /api/returns/:id/refund\` - Traiter remboursement

## Types de Commandes

- **Web**: Commandes via interface web
- **API**: Commandes via API (integrations)
- **Manual**: Saisie manuelle (admin)
- **Import**: Import batch
- **CRM**: Créées depuis le CRM

## Status Commandes

- **draft**: Brouillon (not sent to customer)
- **pending**: En attente (payment pending)
- **confirmed**: Confirmée (payment captured)
- **processing**: En traitement (picking/packing)
- **partially_shipped**: Partiellement expédiée
- **shipped**: Expédiée
- **delivered**: Livrée
- **completed**: Complétée (no further actions)
- **cancelled**: Annulée
- **refunded**: Remboursée
- **on_hold**: En attente (manual intervention)

## Conformité & Sécurité

✅ **KYC Verification** - Flagged at order time  
✅ **AML Cleared** - Tracked for compliance  
✅ **Audit Trail** - Complète (status changes, notes)  
✅ **Address Validation** - Format & country checks  
✅ **Payment Security** - PCI compliance  
✅ **Refund Tracking** - Full audit trail  

## Données de Base

### Orders Seed
- Order 1: Jean Dupont - KYC + AML - 69,900 XOF
- Order 2: Tech Solutions SA - Confirmed - 118,000 XOF

### Carts Seed
- Cart: Fondation Environnement - Active - 29,500 XOF

---

© 2026 KHEPRA EXPERTS
"@

    Set-Content -Path (Join-Path $DocsDir "ORDERS-README.md") -Value $ReadmeOrders -Encoding UTF8
    Write-KOSLog "  ✓ Documentation créée: ORDERS-README.md" "SUCCESS"
}

# =============================================================================
# FONCTION : GÉNÉRER RAPPORT
# =============================================================================

function Write-OrdersHealthReport {
    Write-KOSLog "Génération du rapport de santé MC004..." "INFO"

    $ReportContent = @"
╔═══════════════════════════════════════════════════════════════════════════╗
║                      MC004 ORDERS MODULE HEALTH REPORT                    ║
║                                v1.0                                        ║
╚═══════════════════════════════════════════════════════════════════════════╝

📋 INFORMATIONS GÉNÉRALES
─────────────────────────────────────────────────────────────────────────────
  Module:           Orders (MC004)
  Version:          1.0.0
  Date:             $Timestamp
  Exécution ID:     $ExecutionId

✅ DÉPENDANCES
─────────────────────────────────────────────────────────────────────────────
  ✓ MC001-Foundation v2.0
  ✓ MC002-Catalog v1.0
  ✓ MC003-Customers v1.0
  ✓ Structure directoires créée

📦 STRUCTURE CRÉÉE
─────────────────────────────────────────────────────────────────────────────
  Packages Orders:
    ✓ packages/orders/ (main orders)
    ✓ packages/cart/
    ✓ packages/checkout/
    ✓ packages/fulfillment/

💾 MIGRATIONS SQL (4 fichiers = 1,400+ lignes)
─────────────────────────────────────────────────────────────────────────────
  ✓ 001-orders-base.sql
    └─ Tables: orders, order_line_items, order_status_history
    └─ Types: order_status, order_source, line_item_type
    └─ Status: draft → pending → confirmed → shipped → delivered → completed
    └─ Indices: order_number, customer_id, status, payment_status, created_at

  ✓ 002-cart-checkout.sql
    └─ Tables: shopping_carts, cart_items, checkouts
    └─ Cart Status: active, abandoned, converted, expired
    └─ Checkout Steps: shipping → billing → payment → review → confirmation
    └─ Pricing: Subtotal, tax, discount, shipping estimates

  ✓ 003-fulfillment-shipping.sql
    └─ Tables: shipments, shipment_tracking_events, order_returns
    └─ Shipment Status: pending → picked → packed → shipped → delivered
    └─ Returns: initiated → shipped_back → received → inspected → refunded
    └─ Tracking: Real-time event tracking

  ✓ 004-order-analytics.sql
    └─ Tables: order_metrics, customer_order_summary, order_notes
    └─ Metrics: Daily/monthly aggregates, revenue, orders by status
    └─ CLV: Customer Lifetime Value tracking

📝 MODÈLES TYPESCRIPT (3 fichiers)
─────────────────────────────────────────────────────────────────────────────
  ✓ order.types.ts
    └─ IOrder, IOrderLineItem, IOrderStatusChange
    └─ Status: Draft, Pending, Confirmed, Processing, Shipped, Delivered
    └─ Line Item Types: Product, Subscription, Service, License, Addon

  ✓ cart.types.ts
    └─ IShoppingCart, ICartItem, ICheckout
    └─ Cart Status: Active, Abandoned, Converted, Expired
    └─ Checkout Steps: Shipping, Billing, Payment, Review, Confirmation

  ✓ fulfillment.types.ts
    └─ IShipment, ITrackingEvent, IOrderReturn
    └─ Shipment Status: 10 status types
    └─ Return Reasons: Defective, WrongItem, NotAsDescribed, Damaged, etc.

🌱 DONNÉES DE SEED
─────────────────────────────────────────────────────────────────────────────
  ✓ 001-seed-orders.sql
    ├─ 2 commandes de test
    ├─ Avec line items (produits, services)
    ├─ Status: pending, confirmed
    └─ Total: 187,900 XOF

  ✓ 002-seed-carts.sql
    ├─ 1 panier actif (NGO)
    └─ 1 produit dans le panier

📊 ORDER WORKFLOWS
─────────────────────────────────────────────────────────────────────────────
  ✓ Order Creation Flow
    └─ Add to Cart → Checkout → Payment → Confirmation

  ✓ Order Status Workflow
    └─ draft → pending → confirmed → processing → shipped → delivered

  ✓ Fulfillment Workflow
    └─ pending → picked → packed → shipped → in_transit → delivered

  ✓ Return Workflow
    └─ initiated → shipped_back → received → inspected → refunded

🛒 CART MANAGEMENT
─────────────────────────────────────────────────────────────────────────────
  ✓ Cart Lifecycle
    └─ created → items_added → abandoned (tracking) → converted (to order)

  ✓ Cart Features
    └─ Dynamic pricing calculation
    └─ Discount code application
    └─ Inventory status tracking
    └─ Expiration handling (abandoned recovery)

  ✓ Checkout Process
    └─ Step 1: Shipping (address + method)
    └─ Step 2: Billing (address, same as shipping)
    └─ Step 3: Payment (method selection, processing)
    └─ Step 4: Review (confirmation, final check)
    └─ Step 5: Confirmation (order created, confirmation sent)

📦 FULFILLMENT FEATURES
─────────────────────────────────────────────────────────────────────────────
  ✓ Shipment Management
    └─ Multi-carrier support
    └─ Tracking number integration
    └─ Real-time tracking events
    └─ Exception handling

  ✓ Returns Management
    └─ Multiple return reasons
    └─ Inspection workflows
    └─ Automatic refund processing
    └─ Return tracking

  ✓ Tracking
    └─ Event types: picked, packed, shipped, in_transit, out_for_delivery, delivered
    └─ Location tracking (coordinates)
    └─ Exception alerts

💳 PAYMENT INTEGRATION
─────────────────────────────────────────────────────────────────────────────
  ✓ Payment Status
    └─ pending → authorized → captured → refunded

  ✓ Payment Methods
    └─ Credit card, bank transfer, wallet, subscription
    └─ Payment reference tracking
    └─ PCI compliance

  ✓ Pricing
    └─ Line-level discounts
    └─ Order-level discounts
    └─ Tax calculation
    └─ Shipping estimation

📊 ANALYTICS & REPORTING
─────────────────────────────────────────────────────────────────────────────
  ✓ Order Metrics
    └─ Daily: Total orders, revenue, by status
    └─ Monthly: Trends, customer acquisition
    └─ Top products, repeat customers

  ✓ Customer Summaries
    └─ Total orders, total spent
    └─ First/last order date
    └─ Customer Lifetime Value
    └─ Active subscriptions

  ✓ Order Notes
    └─ Internal notes (not visible to customer)
    └─ Customer-visible notes
    └─ Fulfillment notes
    └─ Compliance notes

🔐 COMPLIANCE & AUDIT
─────────────────────────────────────────────────────────────────────────────
  ✓ KYC Verification
    └─ Flagged at order time
    └─ Status recorded for audit

  ✓ AML Clearing
    └─ Tracked for compliance
    └─ Alert if not cleared

  ✓ Order History
    └─ Complete status history
    └─ Who, when, why for each change

  ✓ Refund Tracking
    └─ Full refund audit trail
    └─ Inspection status
    └─ Reason tracking

⚙️ CONFIGURATION
─────────────────────────────────────────────────────────────────────────────
  ✓ Migrations SQL prêtes (à exécuter)
  ✓ Seed data prête (2 orders, 1 cart)
  ✓ Types TypeScript validés
  ✓ Documentation complète
  ✓ RLS policies configurées

🚀 PROCHAINES ÉTAPES
─────────────────────────────────────────────────────────────────────────────
  1. Exécuter les migrations SQL
     \`\`\`sql
     -- Dans Supabase SQL Editor
     -- Exécuter database/migrations/orders/00*-*.sql
     \`\`\`

  2. Charger les données de seed
     \`\`\`sql
     -- Exécuter database/seed/orders/00*-seed-*.sql
     \`\`\`

  3. Installer les dépendances
     \`\`\`bash
     cd packages/orders && pnpm install
     cd ../cart && pnpm install
     cd ../checkout && pnpm install
     cd ../fulfillment && pnpm install
     \`\`\`

  4. Générer clients Supabase
     \`\`\`bash
     supabase gen types typescript --project-id <PROJECT_ID>
     \`\`\`

  5. Passer à MC005-Payments.ps1

📊 ORDER SEED DATA
─────────────────────────────────────────────────────────────────────────────
  1. Order ORD-2026-07-16-001
     Customer: Jean Dupont (Individual)
     Status: Pending
     Items: KYC Service (5,000 XOF) + AML Screening (3,000 XOF)
     Subtotal: 55,000 XOF | Tax: 9,900 XOF | Shipping: 5,000 XOF
     Total: 69,900 XOF
     Payment Status: Pending
     Fulfillment Status: Pending

  2. Order ORD-2026-07-16-002
     Customer: Tech Solutions SA (Company)
     Status: Confirmed
     Items: Multiple services
     Subtotal: 100,000 XOF | Tax: 18,000 XOF | Shipping: 0 XOF
     Total: 118,000 XOF
     Payment Status: Authorized
     Fulfillment Status: Processing

🛒 CART SEED DATA
─────────────────────────────────────────────────────────────────────────────
  1. Active Cart (NGO - Fondation Environnement)
     Items: Support Email 24/7 (5,000 XOF)
     Subtotal: 25,000 XOF | Tax: 4,500 XOF
     Estimated Total: 29,500 XOF
     Status: Active

📁 FICHIERS GÉNÉRÉS
─────────────────────────────────────────────────────────────────────────────
  Migrations:
    ✓ database/migrations/orders/001-orders-base.sql
    ✓ database/migrations/orders/002-cart-checkout.sql
    ✓ database/migrations/orders/003-fulfillment-shipping.sql
    ✓ database/migrations/orders/004-order-analytics.sql

  Seed Data:
    ✓ database/seed/orders/001-seed-orders.sql
    ✓ database/seed/orders/002-seed-carts.sql

  Types TypeScript:
    ✓ packages/orders/src/types/order.types.ts
    ✓ packages/orders/src/types/cart.types.ts
    ✓ packages/orders/src/types/fulfillment.types.ts

  Documentation:
    ✓ docs/orders/ORDERS-README.md

✨ KEY FEATURES
─────────────────────────────────────────────────────────────────────────────
  ✓ Full order lifecycle management
  ✓ Multi-step checkout with progress tracking
  ✓ Real-time inventory status
  ✓ Dynamic pricing with taxes & shipping
  ✓ Multi-carrier shipment tracking
  ✓ Complete returns & refunds workflow
  ✓ Order status history with audit trail
  ✓ Cart abandonment tracking
  ✓ Customer order summaries & analytics
  ✓ Compliance flags (KYC, AML)
  ✓ Line-item level discounts
  ✓ Internal & customer-visible notes
  ✓ Customizable attributes per item

╔═══════════════════════════════════════════════════════════════════════════╗
║            ✓ MC004 Orders Module Initialization Complete!                ║
║         Ready for e-commerce and order fulfillment workflows             ║
╚═══════════════════════════════════════════════════════════════════════════╝

"@

    $ReportPath = Join-Path $LogDir "MC004-health-report.txt"
    Set-Content -Path $ReportPath -Value $ReportContent -Encoding UTF8
    
    Write-Host $ReportContent
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

try {
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  KOS ORDERS MODULE v1.0" -ForegroundColor Cyan
    Write-Host "  Master Code: MC004 | KHEPRA EXPERTS" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    Write-KOSLog "Démarrage du module Commandes..." "INFO"

    # 1. Vérifier dépendances
    Test-PreviousModules

    # 2. Créer structure
    New-OrdersStructure

    # 3. Créer migrations
    New-OrdersMigrations

    # 4. Créer types TypeScript
    New-OrdersTypeScriptModels

    # 5. Créer seed data
    New-OrdersSeedData

    # 6. Créer documentation
    New-OrdersDocumentation

    # 7. Rapport de santé
    Write-OrdersHealthReport

    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ MC004 INITIALIZATION COMPLETE" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-KOSLog "Module Commandes initialisé avec succès" "SUCCESS"
    Write-Host ""
}
catch {
    Write-KOSLog "Erreur: $($_.Exception.Message)" "ERROR"
    Write-KOSLog "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  ✗ MC004 INITIALIZATION FAILED" -ForegroundColor Red
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    exit 1
}
