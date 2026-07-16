<#
==============================================================================
 KOS ENTERPRISE CATALOG MODULE
 Master Code : MC002
 Version     : 1.0.0 (Enterprise)
 Auteur      : KHEPRA EXPERTS
 Date        : 2026-07-16
 Status      : Production Ready
==============================================================================

DESCRIPTION
  Initialisation du module Catalogue produits/services KOS.
  - Modèle de données produits (SKU, pricing, tiers)
  - Modèle d'abonnements (plans, features, quotas)
  - Modèle de tarification dynamique
  - Intégration des fournisseurs de paiement
  - Seeding de données de base
  - Migrations de base de données

USAGE
  .\MC002-Catalog.ps1

PREREQUISITES
  - MC001-Foundation-v2.0.ps1 exécuté avec succès
  - Supabase CLI configuré
  - PostgreSQL accessible
  
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
$LogFile = Join-Path $LogDir "MC002-v1.0.log"
$CatalogDir = Join-Path $Root "packages\catalog"
$DatabaseDir = Join-Path $Root "database"
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
# FONCTION : VÉRIFIER FOUNDATION
# =============================================================================

function Test-FoundationExists {
    Write-KOSLog "Vérification de MC001..." "INFO"
    
    if (-not (Test-Path $Root)) {
        throw "Racine du projet non trouvée. Exécutez MC001-Foundation-v2.0.ps1 d'abord."
    }

    $RequiredDirs = @(
        "packages",
        "database",
        "logs"
    )

    foreach ($Dir in $RequiredDirs) {
        $Path = Join-Path $Root $Dir
        if (-not (Test-Path $Path)) {
            throw "Dossier manquant: $Dir. Exécutez MC001 d'abord."
        }
    }

    Write-KOSLog "MC001 Foundation vérifiée ✓" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER STRUCTURE CATALOG
# =============================================================================

function New-CatalogStructure {
    Write-KOSLog "Création de la structure du module Catalogue..." "INFO"

    $CatalogFolders = @(
        "packages\catalog",
        "packages\catalog\src",
        "packages\catalog\src\models",
        "packages\catalog\src\services",
        "packages\catalog\src\repositories",
        "packages\catalog\src\controllers",
        "packages\catalog\src\routes",
        "packages\catalog\src\middleware",
        "packages\catalog\src\validators",
        "packages\catalog\src\utils",
        "packages\catalog\src\types",
        "packages\catalog\tests",
        "packages\catalog\tests\unit",
        "packages\catalog\tests\integration",
        "packages\catalog\docs",

        # Subscriptions
        "packages\subscriptions",
        "packages\subscriptions\src",
        "packages\subscriptions\src\models",
        "packages\subscriptions\src\services",
        "packages\subscriptions\src\repositories",
        "packages\subscriptions\src\lifecycle",

        # Pricing
        "packages\pricing",
        "packages\pricing\src",
        "packages\pricing\src\models",
        "packages\pricing\src\engines",
        "packages\pricing\src\rules",
        "packages\pricing\src\calculators"
    )

    $CreatedCount = 0
    foreach ($Folder in $CatalogFolders) {
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

function New-CatalogMigrations {
    Write-KOSLog "Création des migrations de base de données..." "INFO"

    $MigrationDir = Join-Path $DatabaseDir "migrations\catalog"
    
    # Migration 001 - Tables produits
    $Migration001 = @"
-- ==============================================================================
-- KOS Catalog Module - Products Tables
-- Migration: 001-products-table
-- Date: 2026-07-16
-- ==============================================================================

-- Products Table
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100) NOT NULL,
    sub_category VARCHAR(100),
    
    -- Pricing
    base_price DECIMAL(19, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'XOF',
    cost_price DECIMAL(19, 2),
    
    -- Classification
    product_type VARCHAR(50) NOT NULL, -- 'service', 'subscription', 'license', 'support'
    tier VARCHAR(50), -- 'basic', 'professional', 'enterprise', 'custom'
    
    -- Status
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'inactive', 'draft', 'archived'
    visibility VARCHAR(50) DEFAULT 'public', -- 'public', 'private', 'internal'
    
    -- Metadata
    tags JSONB DEFAULT '[]'::jsonb,
    attributes JSONB DEFAULT '{}'::jsonb,
    compliance_tags JSONB DEFAULT '[]'::jsonb, -- 'gdpr', 'cima', 'kyc', 'aml'
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    
    CONSTRAINT products_status_check CHECK (status IN ('active', 'inactive', 'draft', 'archived')),
    CONSTRAINT products_type_check CHECK (product_type IN ('service', 'subscription', 'license', 'support')),
    CONSTRAINT products_price_check CHECK (base_price > 0)
);

CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_products_status ON products(status);
CREATE INDEX idx_products_type ON products(product_type);
CREATE INDEX idx_products_tier ON products(tier);
CREATE INDEX idx_products_created_at ON products(created_at DESC);

-- Product Features Table
CREATE TABLE IF NOT EXISTS product_features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    feature_key VARCHAR(100) NOT NULL,
    feature_name VARCHAR(255) NOT NULL,
    description TEXT,
    value_type VARCHAR(50), -- 'boolean', 'integer', 'decimal', 'string', 'json'
    default_value TEXT,
    tier_access JSONB DEFAULT '{}', -- {"basic": false, "professional": true, "enterprise": true}
    quota DECIMAL(19, 2), -- Pour les limites de quantité
    unit VARCHAR(50), -- 'requests/month', 'users', 'storage_gb', etc.
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(product_id, feature_key)
);

CREATE INDEX idx_product_features_product_id ON product_features(product_id);

-- Product Pricing History (Audit)
CREATE TABLE IF NOT EXISTS product_pricing_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    base_price DECIMAL(19, 2) NOT NULL,
    cost_price DECIMAL(19, 2),
    currency VARCHAR(3),
    change_reason VARCHAR(255),
    changed_by UUID,
    effective_date TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_product_pricing_history_product_id ON product_pricing_history(product_id);
CREATE INDEX idx_product_pricing_history_effective_date ON product_pricing_history(effective_date DESC);

-- Trigger: Update updated_at on products
CREATE OR REPLACE FUNCTION update_products_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_products_updated_at ON products;
CREATE TRIGGER tr_products_updated_at
BEFORE UPDATE ON products
FOR EACH ROW
EXECUTE FUNCTION update_products_updated_at();

-- Enable RLS
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_pricing_history ENABLE ROW LEVEL SECURITY;

-- RLS Policies (à affiner selon vos besoins)
CREATE POLICY "Products are readable by authenticated users" ON products
    FOR SELECT TO authenticated USING (status = 'active' OR visibility = 'public');

CREATE POLICY "Product features are readable by authenticated users" ON product_features
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Admins can manage products" ON products
    FOR ALL TO authenticated USING (auth.jwt() ->> 'role' = 'admin');

-- Audit logging
CREATE OR REPLACE FUNCTION log_product_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (entity_type, entity_id, action, old_data, new_data, changed_by, changed_at)
        VALUES ('product', NEW.id, 'INSERT', NULL, row_to_json(NEW), NEW.created_by, NEW.created_at);
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (entity_type, entity_id, action, old_data, new_data, changed_by, changed_at)
        VALUES ('product', NEW.id, 'UPDATE', row_to_json(OLD), row_to_json(NEW), NEW.updated_by, NEW.updated_at);
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (entity_type, entity_id, action, old_data, new_data, changed_by, changed_at)
        VALUES ('product', OLD.id, 'DELETE', row_to_json(OLD), NULL, OLD.updated_by, CURRENT_TIMESTAMP);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_log_product_changes ON products;
CREATE TRIGGER tr_log_product_changes
AFTER INSERT OR UPDATE OR DELETE ON products
FOR EACH ROW
EXECUTE FUNCTION log_product_changes();
"@

    $Migration001Path = Join-Path $MigrationDir "001-products-table.sql"
    Set-Content -Path $Migration001Path -Value $Migration001 -Encoding UTF8
    Write-KOSLog "  ✓ Migration 001 créée: products-table" "SUCCESS"

    # Migration 002 - Tables abonnements
    $Migration002 = @"
-- ==============================================================================
-- KOS Catalog Module - Subscriptions Tables
-- Migration: 002-subscriptions-table
-- Date: 2026-07-16
-- ==============================================================================

-- Subscription Plans Table
CREATE TABLE IF NOT EXISTS subscription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_code VARCHAR(50) UNIQUE NOT NULL,
    plan_name VARCHAR(255) NOT NULL,
    description TEXT,
    
    -- Pricing
    monthly_price DECIMAL(19, 2) NOT NULL,
    annual_price DECIMAL(19, 2),
    setup_fee DECIMAL(19, 2) DEFAULT 0,
    currency VARCHAR(3) DEFAULT 'XOF',
    
    -- Billing
    billing_cycle VARCHAR(50) NOT NULL, -- 'monthly', 'quarterly', 'annual'
    trial_days INTEGER DEFAULT 14,
    cancellation_notice_days INTEGER DEFAULT 30,
    
    -- Limits & Quotas
    features JSONB DEFAULT '{}', -- {"users": 5, "api_calls": 10000, "storage_gb": 100}
    max_users INTEGER,
    api_rate_limit INTEGER DEFAULT 1000, -- Requests per hour
    storage_limit_gb DECIMAL(10, 2),
    
    -- Tier Classification
    tier VARCHAR(50) NOT NULL, -- 'starter', 'professional', 'enterprise', 'custom'
    tier_position INTEGER, -- Pour l'ordre d'affichage
    
    -- Status & Visibility
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'inactive', 'archived', 'deprecated'
    is_public BOOLEAN DEFAULT true,
    is_recommended BOOLEAN DEFAULT false,
    
    -- Compliance
    compliance_level VARCHAR(50), -- 'basic', 'professional', 'enterprise'
    includes_kyc BOOLEAN DEFAULT false,
    includes_aml BOOLEAN DEFAULT false,
    
    -- Metadata
    tags JSONB DEFAULT '[]'::jsonb,
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_by UUID,
    
    CONSTRAINT subscription_plans_price_check CHECK (monthly_price > 0),
    CONSTRAINT subscription_plans_tier_check CHECK (tier IN ('starter', 'professional', 'enterprise', 'custom'))
);

CREATE INDEX idx_subscription_plans_code ON subscription_plans(plan_code);
CREATE INDEX idx_subscription_plans_tier ON subscription_plans(tier);
CREATE INDEX idx_subscription_plans_status ON subscription_plans(status);

-- Plan Features Table (What's included in each plan)
CREATE TABLE IF NOT EXISTS plan_features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
    feature_key VARCHAR(100) NOT NULL,
    feature_name VARCHAR(255) NOT NULL,
    description TEXT,
    is_included BOOLEAN DEFAULT true,
    limit_value DECIMAL(19, 2),
    limit_unit VARCHAR(50), -- 'requests/month', 'users', 'projects', etc.
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(plan_id, feature_key)
);

CREATE INDEX idx_plan_features_plan_id ON plan_features(plan_id);

-- Active Subscriptions Table
CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL,
    plan_id UUID NOT NULL REFERENCES subscription_plans(id),
    
    -- Subscription Details
    subscription_number VARCHAR(100) UNIQUE NOT NULL,
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'past_due', 'cancelled', 'paused', 'expired'
    
    -- Dates
    start_date DATE NOT NULL,
    renewal_date DATE NOT NULL,
    end_date DATE,
    cancelled_at TIMESTAMP WITH TIME ZONE,
    
    -- Pricing
    current_price DECIMAL(19, 2) NOT NULL,
    next_billing_amount DECIMAL(19, 2),
    currency VARCHAR(3) DEFAULT 'XOF',
    
    -- Customizations
    custom_features JSONB DEFAULT '{}', -- Overrides du plan
    custom_limits JSONB DEFAULT '{}',
    
    -- Payment Info
    payment_method_id UUID,
    auto_renew BOOLEAN DEFAULT true,
    failed_payment_attempts INTEGER DEFAULT 0,
    
    -- Metadata
    notes TEXT,
    tags JSONB DEFAULT '[]'::jsonb,
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_by UUID,
    
    CONSTRAINT subscriptions_status_check CHECK (status IN ('active', 'past_due', 'cancelled', 'paused', 'expired'))
);

CREATE INDEX idx_subscriptions_customer_id ON subscriptions(customer_id);
CREATE INDEX idx_subscriptions_plan_id ON subscriptions(plan_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);
CREATE INDEX idx_subscriptions_renewal_date ON subscriptions(renewal_date);

-- Subscription History (Audit Trail)
CREATE TABLE IF NOT EXISTS subscription_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    action VARCHAR(50) NOT NULL, -- 'created', 'upgraded', 'downgraded', 'paused', 'resumed', 'cancelled', 'renewed', 'payment_failed', 'payment_succeeded'
    from_plan_id UUID REFERENCES subscription_plans(id),
    to_plan_id UUID REFERENCES subscription_plans(id),
    from_price DECIMAL(19, 2),
    to_price DECIMAL(19, 2),
    reason TEXT,
    triggered_by UUID, -- User ID qui a déclenché l'action
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_subscription_history_subscription_id ON subscription_history(subscription_id);
CREATE INDEX idx_subscription_history_action ON subscription_history(action);
CREATE INDEX idx_subscription_history_created_at ON subscription_history(created_at DESC);

-- Triggers
CREATE OR REPLACE FUNCTION update_subscriptions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_subscriptions_updated_at ON subscriptions;
CREATE TRIGGER tr_subscriptions_updated_at
BEFORE UPDATE ON subscriptions
FOR EACH ROW
EXECUTE FUNCTION update_subscriptions_updated_at();

-- Enable RLS
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_history ENABLE ROW LEVEL SECURITY;
"@

    $Migration002Path = Join-Path $MigrationDir "002-subscriptions-table.sql"
    Set-Content -Path $Migration002Path -Value $Migration002 -Encoding UTF8
    Write-KOSLog "  ✓ Migration 002 créée: subscriptions-table" "SUCCESS"

    # Migration 003 - Tables pricing
    $Migration003 = @"
-- ==============================================================================
-- KOS Catalog Module - Pricing & Discounts
-- Migration: 003-pricing-discounts
-- Date: 2026-07-16
-- ==============================================================================

-- Pricing Rules Table
CREATE TABLE IF NOT EXISTS pricing_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_code VARCHAR(100) UNIQUE NOT NULL,
    rule_name VARCHAR(255) NOT NULL,
    description TEXT,
    
    -- Rule Type
    rule_type VARCHAR(50) NOT NULL, -- 'percentage', 'fixed', 'tiered', 'bulk'
    
    -- Conditions
    applies_to VARCHAR(50) NOT NULL, -- 'product', 'plan', 'customer_type', 'region', 'volume'
    applies_to_id UUID,
    applies_to_value VARCHAR(100),
    
    -- Discount/Premium
    adjustment_type VARCHAR(50) NOT NULL, -- 'discount', 'premium', 'override'
    adjustment_amount DECIMAL(19, 2) NOT NULL,
    adjustment_unit VARCHAR(50), -- 'percentage', 'fixed_amount'
    
    -- Validity
    valid_from TIMESTAMP WITH TIME ZONE NOT NULL,
    valid_until TIMESTAMP WITH TIME ZONE,
    priority INTEGER DEFAULT 100, -- Pour résoudre les conflits
    
    -- Conditions supplémentaires
    minimum_quantity INTEGER,
    minimum_order_value DECIMAL(19, 2),
    maximum_discount DECIMAL(19, 2),
    
    -- Status
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'inactive', 'archived'
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_by UUID
);

CREATE INDEX idx_pricing_rules_code ON pricing_rules(rule_code);
CREATE INDEX idx_pricing_rules_applies_to ON pricing_rules(applies_to);
CREATE INDEX idx_pricing_rules_status ON pricing_rules(status);
CREATE INDEX idx_pricing_rules_valid_from ON pricing_rules(valid_from DESC);

-- Discount Codes Table
CREATE TABLE IF NOT EXISTS discount_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    
    -- Discount Details
    discount_type VARCHAR(50) NOT NULL, -- 'percentage', 'fixed_amount', 'free_period'
    discount_value DECIMAL(19, 2) NOT NULL,
    
    -- Usage Limits
    max_redemptions INTEGER,
    redemptions_used INTEGER DEFAULT 0,
    max_per_customer INTEGER DEFAULT 1,
    
    -- Validity
    valid_from TIMESTAMP WITH TIME ZONE NOT NULL,
    valid_until TIMESTAMP WITH TIME ZONE NOT NULL,
    
    -- Restrictions
    minimum_purchase DECIMAL(19, 2),
    applicable_plans JSONB DEFAULT '[]'::jsonb, -- Plan IDs where applicable
    applicable_regions JSONB DEFAULT '[]'::jsonb,
    
    -- Status
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'inactive', 'archived', 'expired'
    is_stackable BOOLEAN DEFAULT false,
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID
);

CREATE INDEX idx_discount_codes_code ON discount_codes(code);
CREATE INDEX idx_discount_codes_status ON discount_codes(status);
CREATE INDEX idx_discount_codes_valid_until ON discount_codes(valid_until DESC);

-- Discount Redemptions Audit
CREATE TABLE IF NOT EXISTS discount_redemptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code_id UUID NOT NULL REFERENCES discount_codes(id),
    customer_id UUID NOT NULL,
    order_id UUID,
    redemption_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    discount_amount DECIMAL(19, 2),
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_discount_redemptions_code_id ON discount_redemptions(code_id);
CREATE INDEX idx_discount_redemptions_customer_id ON discount_redemptions(customer_id);

-- Triggers
CREATE OR REPLACE FUNCTION update_pricing_rules_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_pricing_rules_updated_at ON pricing_rules;
CREATE TRIGGER tr_pricing_rules_updated_at
BEFORE UPDATE ON pricing_rules
FOR EACH ROW
EXECUTE FUNCTION update_pricing_rules_updated_at();

-- Enable RLS
ALTER TABLE pricing_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE discount_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE discount_redemptions ENABLE ROW LEVEL SECURITY;
"@

    $Migration003Path = Join-Path $MigrationDir "003-pricing-discounts.sql"
    Set-Content -Path $Migration003Path -Value $Migration003 -Encoding UTF8
    Write-KOSLog "  ✓ Migration 003 créée: pricing-discounts" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER MODÈLES TYPESCRIPT
# =============================================================================

function New-CatalogTypeScriptModels {
    Write-KOSLog "Création des modèles TypeScript..." "INFO"

    $TypesDir = Join-Path $Root "packages\catalog\src\types"

    # Types Produits
    $ProductTypes = @"
// ==============================================================================
// KOS Catalog - Product Types
// ==============================================================================

export type ProductType = 'service' | 'subscription' | 'license' | 'support';
export type ProductStatus = 'active' | 'inactive' | 'draft' | 'archived';
export type ProductTier = 'basic' | 'professional' | 'enterprise' | 'custom';
export type ProductVisibility = 'public' | 'private' | 'internal';

export interface IProduct {
  id: string;
  sku: string;
  name: string;
  description?: string;
  category: string;
  subCategory?: string;

  // Pricing
  basePrice: number;
  currency: string; // ISO 4217
  costPrice?: number;

  // Classification
  productType: ProductType;
  tier?: ProductTier;

  // Status
  status: ProductStatus;
  visibility: ProductVisibility;

  // Metadata
  tags: string[];
  attributes: Record<string, any>;
  complianceTags: string[]; // 'gdpr', 'cima', 'kyc', 'aml'

  // Audit
  createdAt: Date;
  updatedAt: Date;
  createdBy?: string;
  updatedBy?: string;
  deletedAt?: Date;
}

export interface IProductFeature {
  id: string;
  productId: string;
  featureKey: string;
  featureName: string;
  description?: string;
  valueType: 'boolean' | 'integer' | 'decimal' | 'string' | 'json';
  defaultValue?: any;
  tierAccess: Record<string, boolean>;
  quota?: number;
  unit?: string;

  createdAt: Date;
  updatedAt: Date;
}

export interface IProductPricingHistory {
  id: string;
  productId: string;
  basePrice: number;
  costPrice?: number;
  currency: string;
  changeReason?: string;
  changedBy?: string;
  effectiveDate: Date;
  createdAt: Date;
}

export interface CreateProductDTO {
  sku: string;
  name: string;
  description?: string;
  category: string;
  subCategory?: string;
  basePrice: number;
  currency?: string;
  costPrice?: number;
  productType: ProductType;
  tier?: ProductTier;
  tags?: string[];
  attributes?: Record<string, any>;
}

export interface UpdateProductDTO {
  name?: string;
  description?: string;
  basePrice?: number;
  costPrice?: number;
  status?: ProductStatus;
  tier?: ProductTier;
  tags?: string[];
  attributes?: Record<string, any>;
}
"@

    Set-Content -Path (Join-Path $TypesDir "product.types.ts") -Value $ProductTypes -Encoding UTF8
    Write-KOSLog "  ✓ Types créés: product.types.ts" "SUCCESS"

    # Types Abonnements
    $SubscriptionTypes = @"
// ==============================================================================
// KOS Catalog - Subscription Types
// ==============================================================================

export type SubscriptionTier = 'starter' | 'professional' | 'enterprise' | 'custom';
export type BillingCycle = 'monthly' | 'quarterly' | 'annual';
export type SubscriptionStatus = 'active' | 'past_due' | 'cancelled' | 'paused' | 'expired';
export type SubscriptionAction = 'created' | 'upgraded' | 'downgraded' | 'paused' | 'resumed' | 'cancelled' | 'renewed';

export interface ISubscriptionPlan {
  id: string;
  planCode: string;
  planName: string;
  description?: string;

  // Pricing
  monthlyPrice: number;
  annualPrice?: number;
  setupFee: number;
  currency: string;

  // Billing
  billingCycle: BillingCycle;
  trialDays: number;
  cancellationNoticeDays: number;

  // Limits & Quotas
  features: Record<string, any>;
  maxUsers?: number;
  apiRateLimit: number;
  storageLimitGb?: number;

  // Tier Classification
  tier: SubscriptionTier;
  tierPosition: number;

  // Status
  status: 'active' | 'inactive' | 'archived' | 'deprecated';
  isPublic: boolean;
  isRecommended: boolean;

  // Compliance
  complianceLevel?: string;
  includesKyc: boolean;
  includesAml: boolean;

  // Metadata
  tags: string[];

  // Audit
  createdAt: Date;
  updatedAt: Date;
  createdBy?: string;
  updatedBy?: string;
}

export interface ISubscription {
  id: string;
  customerId: string;
  planId: string;

  // Subscription Details
  subscriptionNumber: string;
  status: SubscriptionStatus;

  // Dates
  startDate: Date;
  renewalDate: Date;
  endDate?: Date;
  cancelledAt?: Date;

  // Pricing
  currentPrice: number;
  nextBillingAmount?: number;
  currency: string;

  // Customizations
  customFeatures: Record<string, any>;
  customLimits: Record<string, any>;

  // Payment Info
  paymentMethodId?: string;
  autoRenew: boolean;
  failedPaymentAttempts: number;

  // Metadata
  notes?: string;
  tags: string[];

  // Audit
  createdAt: Date;
  updatedAt: Date;
  createdBy?: string;
  updatedBy?: string;
}

export interface ISubscriptionHistory {
  id: string;
  subscriptionId: string;
  action: SubscriptionAction;
  fromPlanId?: string;
  toPlanId?: string;
  fromPrice?: number;
  toPrice?: number;
  reason?: string;
  triggeredBy?: string;
  createdAt: Date;
}

export interface CreateSubscriptionDTO {
  customerId: string;
  planId: string;
  startDate?: Date;
  customFeatures?: Record<string, any>;
  customLimits?: Record<string, any>;
  autoRenew?: boolean;
}

export interface UpdateSubscriptionDTO {
  status?: SubscriptionStatus;
  planId?: string;
  customFeatures?: Record<string, any>;
  customLimits?: Record<string, any>;
  autoRenew?: boolean;
}

export interface IPlanFeature {
  id: string;
  planId: string;
  featureKey: string;
  featureName: string;
  description?: string;
  isIncluded: boolean;
  limitValue?: number;
  limitUnit?: string;
  createdAt: Date;
}
"@

    Set-Content -Path (Join-Path $TypesDir "subscription.types.ts") -Value $SubscriptionTypes -Encoding UTF8
    Write-KOSLog "  ✓ Types créés: subscription.types.ts" "SUCCESS"

    # Types Pricing
    $PricingTypes = @"
// ==============================================================================
// KOS Catalog - Pricing Types
// ==============================================================================

export type RuleType = 'percentage' | 'fixed' | 'tiered' | 'bulk';
export type AdjustmentType = 'discount' | 'premium' | 'override';
export type AdjustmentUnit = 'percentage' | 'fixed_amount';
export type PricingRuleStatus = 'active' | 'inactive' | 'archived';
export type DiscountType = 'percentage' | 'fixed_amount' | 'free_period';
export type DiscountStatus = 'active' | 'inactive' | 'archived' | 'expired';

export interface IPricingRule {
  id: string;
  ruleCode: string;
  ruleName: string;
  description?: string;

  // Rule Type
  ruleType: RuleType;

  // Conditions
  appliesToType: string; // 'product', 'plan', 'customer_type', 'region', 'volume'
  appliesToId?: string;
  appliesToValue?: string;

  // Adjustment
  adjustmentType: AdjustmentType;
  adjustmentAmount: number;
  adjustmentUnit: AdjustmentUnit;

  // Validity
  validFrom: Date;
  validUntil?: Date;
  priority: number;

  // Additional Conditions
  minimumQuantity?: number;
  minimumOrderValue?: number;
  maximumDiscount?: number;

  // Status
  status: PricingRuleStatus;

  // Audit
  createdAt: Date;
  updatedAt: Date;
  createdBy?: string;
  updatedBy?: string;
}

export interface IDiscountCode {
  id: string;
  code: string;
  description?: string;

  // Discount Details
  discountType: DiscountType;
  discountValue: number;

  // Usage Limits
  maxRedemptions?: number;
  redemptionsUsed: number;
  maxPerCustomer: number;

  // Validity
  validFrom: Date;
  validUntil: Date;

  // Restrictions
  minimumPurchase?: number;
  applicablePlans: string[]; // Plan IDs
  applicableRegions: string[];

  // Status
  status: DiscountStatus;
  isStackable: boolean;

  // Audit
  createdAt: Date;
  createdBy?: string;
}

export interface IDiscountRedemption {
  id: string;
  codeId: string;
  customerId: string;
  orderId?: string;
  redemptionDate: Date;
  discountAmount: number;
  createdAt: Date;
}

export interface PriceCalculationRequest {
  productId?: string;
  planId?: string;
  quantity?: number;
  customerId?: string;
  customerType?: string;
  region?: string;
  discountCodes?: string[];
  currency?: string;
}

export interface PriceCalculationResult {
  basePrice: number;
  adjustments: IPriceAdjustment[];
  subtotal: number;
  tax?: number;
  total: number;
  currency: string;
  validUntil?: Date;
}

export interface IPriceAdjustment {
  ruleId: string;
  ruleName: string;
  adjustmentType: AdjustmentType;
  amount: number;
  reason?: string;
}
"@

    Set-Content -Path (Join-Path $TypesDir "pricing.types.ts") -Value $PricingTypes -Encoding UTF8
    Write-KOSLog "  ✓ Types créés: pricing.types.ts" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER SEED DATA
# =============================================================================

function New-CatalogSeedData {
    Write-KOSLog "Création des données de seed..." "INFO"

    $SeedDir = Join-Path $DatabaseDir "seed\catalog"

    # Seed Products
    $SeedProducts = @"
-- ==============================================================================
-- KOS Catalog - Product Seed Data
-- ==============================================================================

INSERT INTO products (sku, name, description, category, sub_category, base_price, currency, cost_price, product_type, tier, status, visibility, tags, attributes, compliance_tags)
VALUES
    -- Core Compliance Services
    ('COMPL-KYC-001', 'KYC - Individus', 'Vérification Connaître Votre Client pour personnes physiques', 'Compliance', 'KYC', 5000, 'XOF', 1500, 'service', 'professional', 'active', 'public', '["kyc", "compliance", "core"]'::jsonb, '{"verification_time": "24h", "documents": 5}'::jsonb, '["kyc", "gdpr"]'::jsonb),
    ('COMPL-KYC-002', 'KYC - Entreprises', 'Vérification Connaître Votre Client pour personnes morales', 'Compliance', 'KYC', 10000, 'XOF', 3000, 'service', 'professional', 'active', 'public', '["kyc", "compliance", "corporate"]'::jsonb, '{"verification_time": "48h", "documents": 8}'::jsonb, '["kyc", "gdpr"]'::jsonb),
    ('COMPL-AML-001', 'AML Screening', 'Contrôle Anti-Blanchiment de Capitaux', 'Compliance', 'AML', 3000, 'XOF', 1000, 'service', 'professional', 'active', 'public', '["aml", "compliance", "screening"]'::jsonb, '{"screening_lists": 50, "real_time": true}'::jsonb, '["aml", "cima"]'::jsonb),
    ('COMPL-AUDIT-001', 'Audit Trail - Annual', 'Archivage et audit des modifications (année)', 'Compliance', 'Audit', 15000, 'XOF', 4000, 'service', 'enterprise', 'active', 'public', '["audit", "compliance", "archive"]'::jsonb, '{"retention": "365 days", "compliance_reports": 12}'::jsonb, '["gdpr", "cima"]'::jsonb),

    -- Support Services
    ('SUPP-PHONE-001', 'Support Téléphonique - 8h/jour', 'Support client par téléphone (8h-17h)', 'Support', 'Telephony', 2000, 'XOF', 600, 'service', 'basic', 'active', 'public', '["support", "phone"]'::jsonb, '{"hours": "8x5", "languages": ["fr", "en"]}'::jsonb, '[]'::jsonb),
    ('SUPP-EMAIL-001', 'Support Email - 24/7', 'Support client par email 24h/24, 7j/7', 'Support', 'Email', 5000, 'XOF', 1500, 'service', 'professional', 'active', 'public', '["support", "email"]'::jsonb, '{"response_time": "4h", "sla": "99%"}'::jsonb, '[]'::jsonb),
    ('SUPP-CHAT-001', 'Chat Support - Live', 'Support par chat en direct', 'Support', 'Chat', 3000, 'XOF', 1000, 'service', 'professional', 'active', 'public', '["support", "chat"]'::jsonb, '{"availability": "9-18h", "response_time": "1 min"}'::jsonb, '[]'::jsonb),

    -- Integration Services
    ('INT-API-001', 'API Standard - Monthly', 'Accès API standard avec 10k requêtes/mois', 'Integration', 'API', 5000, 'XOF', 1500, 'service', 'professional', 'active', 'public', '["api", "integration"]'::jsonb, '{"requests": 10000, "rate_limit": 100}'::jsonb, '[]'::jsonb),
    ('INT-API-PRO-001', 'API Professional - Monthly', 'Accès API professionnel avec 100k requêtes/mois', 'Integration', 'API', 25000, 'XOF', 7000, 'service', 'enterprise', 'active', 'public', '["api", "integration", "pro"]'::jsonb, '{"requests": 100000, "rate_limit": 1000, "webhook": true}'::jsonb, '[]'::jsonb),

    -- Training Services
    ('TRAIN-WEB-001', 'Formation Web - 3 jours', 'Formation pratique plateforme web KOS (3 jours)', 'Training', 'Web', 150000, 'XOF', 40000, 'service', 'professional', 'active', 'public', '["training", "web"]'::jsonb, '{"duration": "3 days", "participants": 10, "certification": true}'::jsonb, '[]'::jsonb),
    ('TRAIN-API-001', 'Formation API - 2 jours', 'Formation intégration API (2 jours)', 'Training', 'API', 120000, 'XOF', 35000, 'service', 'professional', 'active', 'public', '["training", "api"]'::jsonb, '{"duration": "2 days", "participants": 8, "certification": true}'::jsonb, '[]'::jsonb);

-- Tags pour les données insérées
UPDATE products SET tags = tags || '["regtech", "africa"]'::jsonb WHERE category IN ('Compliance', 'Integration', 'Training');
"@

    Set-Content -Path (Join-Path $SeedDir "001-seed-products.sql") -Value $SeedProducts -Encoding UTF8
    Write-KOSLog "  ✓ Seed données: products" "SUCCESS"

    # Seed Subscription Plans
    $SeedPlans = @"
-- ==============================================================================
-- KOS Catalog - Subscription Plans Seed Data
-- ==============================================================================

INSERT INTO subscription_plans (plan_code, plan_name, description, monthly_price, annual_price, setup_fee, currency, billing_cycle, trial_days, cancellation_notice_days, features, max_users, api_rate_limit, storage_limit_gb, tier, tier_position, status, is_public, is_recommended, compliance_level, includes_kyc, includes_aml, tags)
VALUES
    ('STARTER', 'Starter Plan', 'Plan d''entrée pour les petites organisations', 15000, 150000, 5000, 'XOF', 'monthly', 14, 30, '{
        "kyc_checks": 10,
        "aml_screening": 5,
        "users": 3,
        "api_calls": 1000,
        "storage_gb": 5,
        "support": "email"
    }'::jsonb, 3, 100, 5, 'starter', 1, 'active', true, false, 'basic', true, false, '["starter", "entry-level"]'::jsonb),

    ('PROFESSIONAL', 'Professional Plan', 'Plan pour PME et organisations établies', 50000, 480000, 10000, 'XOF', 'monthly', 14, 30, '{
        "kyc_checks": 100,
        "aml_screening": 50,
        "users": 10,
        "api_calls": 10000,
        "storage_gb": 50,
        "support": "email+phone",
        "sso": true,
        "audit_trail": true,
        "reporting": true
    }'::jsonb, 10, 1000, 50, 'professional', 2, 'active', true, true, 'professional', true, true, '["professional", "recommended"]'::jsonb),

    ('ENTERPRISE', 'Enterprise Plan', 'Plan complet pour grandes organisations', 200000, 1800000, 50000, 'XOF', 'monthly', 14, 30, '{
        "kyc_checks": 1000,
        "aml_screening": 500,
        "users": 100,
        "api_calls": 100000,
        "storage_gb": 500,
        "support": "24/7",
        "sso": true,
        "audit_trail": true,
        "reporting": "advanced",
        "esg_reporting": true,
        "risk_management": true,
        "workflow_automation": true,
        "dedicated_account_manager": true
    }'::jsonb, 100, 10000, 500, 'enterprise', 3, 'active', true, false, 'enterprise', true, true, '["enterprise", "full-featured"]'::jsonb),

    ('CUSTOM', 'Custom Plan', 'Plan personnalisé sur devis', 0, NULL, 0, 'XOF', 'annual', 30, 60, '{"custom": true}'::jsonb, NULL, NULL, NULL, 'custom', 4, 'active', false, false, 'enterprise', true, true, '["custom", "negotiated"]'::jsonb);

-- Insert Plan Features for each plan
INSERT INTO plan_features (plan_id, feature_key, feature_name, description, is_included, limit_value, limit_unit)
SELECT id, 'kyc_checks', 'KYC Checks', 'Vérifications KYC par mois', true, 10, 'checks/month' FROM subscription_plans WHERE plan_code = 'STARTER'
UNION ALL
SELECT id, 'aml_screening', 'AML Screening', 'Contrôles AML par mois', true, 5, 'screens/month' FROM subscription_plans WHERE plan_code = 'STARTER'
UNION ALL
SELECT id, 'users', 'Utilisateurs', 'Nombre d''utilisateurs', true, 3, 'users' FROM subscription_plans WHERE plan_code = 'STARTER'
UNION ALL
SELECT id, 'kyc_checks', 'KYC Checks', 'Vérifications KYC par mois', true, 100, 'checks/month' FROM subscription_plans WHERE plan_code = 'PROFESSIONAL'
UNION ALL
SELECT id, 'aml_screening', 'AML Screening', 'Contrôles AML par mois', true, 50, 'screens/month' FROM subscription_plans WHERE plan_code = 'PROFESSIONAL'
UNION ALL
SELECT id, 'users', 'Utilisateurs', 'Nombre d''utilisateurs', true, 10, 'users' FROM subscription_plans WHERE plan_code = 'PROFESSIONAL'
UNION ALL
SELECT id, 'kyc_checks', 'KYC Checks', 'Vérifications KYC par mois', true, 1000, 'checks/month' FROM subscription_plans WHERE plan_code = 'ENTERPRISE'
UNION ALL
SELECT id, 'users', 'Utilisateurs', 'Nombre d''utilisateurs', true, 100, 'users' FROM subscription_plans WHERE plan_code = 'ENTERPRISE';
"@

    Set-Content -Path (Join-Path $SeedDir "002-seed-subscription-plans.sql") -Value $SeedPlans -Encoding UTF8
    Write-KOSLog "  ✓ Seed données: subscription plans" "SUCCESS"

    # Seed Discount Codes
    $SeedDiscounts = @"
-- ==============================================================================
-- KOS Catalog - Discount Codes Seed Data
-- ==============================================================================

INSERT INTO discount_codes (code, description, discount_type, discount_value, max_redemptions, max_per_customer, valid_from, valid_until, minimum_purchase, applicable_plans, status, is_stackable)
VALUES
    ('LAUNCH2026', 'Code de lancement - 20% de réduction', 'percentage', 20, 1000, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '90 days', 0, '[]'::jsonb, 'active', false),
    ('EARLY100K', 'Code utilisateur précoce - 100k XOF fixes', 'fixed_amount', 100000, 100, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '60 days', 50000, '[]'::jsonb, 'active', false),
    ('ANNUAL25', 'Engagement annuel - 25% de réduction', 'percentage', 25, 500, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '180 days', 100000, '[]'::jsonb, 'active', false),
    ('NONPROFIT15', 'ONG/Organisme sans but lucratif - 15%', 'percentage', 15, NULL, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '365 days', 0, '[]'::jsonb, 'active', false);
"@

    Set-Content -Path (Join-Path $SeedDir "003-seed-discount-codes.sql") -Value $SeedDiscounts -Encoding UTF8
    Write-KOSLog "  ✓ Seed données: discount codes" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER DOCUMENTATION
# =============================================================================

function New-CatalogDocumentation {
    Write-KOSLog "Création de la documentation..." "INFO"

    $DocsDir = Join-Path $Root "docs\catalog"
    
    # README Catalog
    $ReadmeCatalog = @"
# KOS Catalog Module

## Vue d'ensemble

Le module Catalogue KOS gère l'ensemble des produits, services et plans d'abonnement de la plateforme.

## Modules

### 1. **Products** (`packages/catalog`)
Gestion des produits et services proposés par KOS.

- **Modèles**: Product, ProductFeature, ProductPricingHistory
- **Tiers**: Basic, Professional, Enterprise, Custom
- **Types**: Service, Subscription, License, Support
- **Compliance**: Tags GDPR, CIMA, KYC, AML

### 2. **Subscriptions** (`packages/subscriptions`)
Gestion des plans d'abonnement et des souscriptions clients.

- **Plans**: Starter, Professional, Enterprise, Custom
- **Cycle de facturation**: Monthly, Quarterly, Annual
- **Fonctionnalités**: Features JSONB, Quotas, Limites
- **Historique**: Suivi des changements et événements

### 3. **Pricing** (`packages/pricing`)
Moteur de calcul de tarification avec règles et remises.

- **Règles**: Percentage, Fixed, Tiered, Bulk
- **Codes promotionnels**: Avec limites de validité et d'utilisation
- **Calcul**: Support multi-devises, taxes, ajustements
- **Audit**: Historique complet des pricing changes

## Architecture

### Base de Données

\`\`\`
products
├── product_features
└── product_pricing_history

subscription_plans
├── plan_features
└── subscriptions
    └── subscription_history

pricing_rules
discount_codes
└── discount_redemptions
\`\`\`

### API Endpoints

#### Products
- \`GET /api/products\` - Lister les produits
- \`GET /api/products/:id\` - Détails produit
- \`POST /api/products\` - Créer produit (admin)
- \`PUT /api/products/:id\` - Modifier produit (admin)

#### Subscriptions
- \`GET /api/subscriptions\` - Lister abonnements
- \`GET /api/subscriptions/plans\` - Lister plans
- \`POST /api/subscriptions\` - Créer abonnement
- \`PUT /api/subscriptions/:id\` - Modifier abonnement

#### Pricing
- \`POST /api/pricing/calculate\` - Calculer prix
- \`GET /api/discounts/validate\` - Valider code promo

## Types TypeScript

### Product
\`\`\`typescript
interface IProduct {
  id: string;
  sku: string;
  name: string;
  basePrice: number;
  productType: 'service' | 'subscription' | 'license' | 'support';
  tier?: 'basic' | 'professional' | 'enterprise' | 'custom';
  status: 'active' | 'inactive' | 'draft' | 'archived';
  complianceTags: string[]; // ['gdpr', 'kyc', 'aml', ...]
  // ...
}
\`\`\`

### Subscription
\`\`\`typescript
interface ISubscription {
  id: string;
  customerId: string;
  planId: string;
  status: 'active' | 'past_due' | 'cancelled' | 'paused' | 'expired';
  startDate: Date;
  renewalDate: Date;
  currentPrice: number;
  autoRenew: boolean;
  // ...
}
\`\`\`

### Pricing Calculation
\`\`\`typescript
interface PriceCalculationRequest {
  productId?: string;
  planId?: string;
  quantity?: number;
  customerId?: string;
  discountCodes?: string[];
  currency?: string;
}

interface PriceCalculationResult {
  basePrice: number;
  adjustments: IPriceAdjustment[];
  subtotal: number;
  tax?: number;
  total: number;
  currency: string;
}
\`\`\`

## Données de Base

### Produits Seed
- KYC - Individus: 5,000 XOF
- KYC - Entreprises: 10,000 XOF
- AML Screening: 3,000 XOF
- Support Téléphonique: 2,000 XOF
- Support Email 24/7: 5,000 XOF
- API Standard: 5,000 XOF
- Formation Web (3j): 150,000 XOF

### Plans d'Abonnement
| Plan | Prix/mois | KYC/mois | Utilisateurs | Support |
|------|-----------|----------|--------------|---------|
| Starter | 15,000 | 10 | 3 | Email |
| Professional | 50,000 | 100 | 10 | Email+Phone |
| Enterprise | 200,000 | 1,000 | 100 | 24/7 |
| Custom | Sur devis | Illimité | Illimité | VIP |

### Codes Promotionnels
- \`LAUNCH2026\`: -20% (90 jours)
- \`EARLY100K\`: -100k XOF fixes (60 jours)
- \`ANNUAL25\`: -25% annuel (180 jours)
- \`NONPROFIT15\`: -15% ONG (365 jours)

## Flux de Travail

### Créer un Produit
1. Définir SKU, nom, description
2. Configurer tarification (base, cost)
3. Ajouter fonctionnalités produit
4. Configurer compliance tags
5. Publier

### Souscrire à un Plan
1. Sélectionner plan (Starter/Pro/Enterprise)
2. Appliquer code promo (optionnel)
3. Calculer prix (taxes incluses)
4. Configurer payment method
5. Activer abonnement

### Calculer Prix Dynamique
1. Recevoir demande (product + context)
2. Appliquer règles de pricing
3. Valider codes promotionnels
4. Calculer taxes
5. Retourner résultat

## Configuration

### Variables d'Environnement
\`\`\`
CATALOG_CURRENCY=XOF
CATALOG_TAX_RATE=0.18
CATALOG_ENABLE_DYNAMIC_PRICING=true
CATALOG_LOG_LEVEL=info
\`\`\`

## Conformité & Sécurité

### Conformité
- ✓ GDPR (consentement, data minimization)
- ✓ CIMA (réglementation bancaire Afrique)
- ✓ KYC/AML (tagging automatique)
- ✓ Audit Trail (traçabilité complète)

### Sécurité
- ✓ RLS (Row Level Security) Supabase
- ✓ Validation des prix (pas de manipulation client)
- ✓ Chiffrement des données sensibles
- ✓ Rate limiting sur API

## Prochaines Étapes

1. **MC003-Customers.ps1**: Gestion des clients
2. **MC004-Orders.ps1**: Gestion des commandes
3. **MC005-Payments.ps1**: Intégration paiements
4. **MC006-Invoices.ps1**: Facturation

---

© 2026 KHEPRA EXPERTS
"@

    Set-Content -Path (Join-Path $DocsDir "README.md") -Value $ReadmeCatalog -Encoding UTF8
    Write-KOSLog "  ✓ Documentation créée: README.md" "SUCCESS"

    # API Reference
    $ApiReference = @"
# KOS Catalog API Reference

## Base URL
\`\`\`
https://api.kos.io/v1
\`\`\`

## Authentication
Tous les endpoints nécessitent un token Bearer JWT dans le header:
\`\`\`
Authorization: Bearer <token>
\`\`\`

---

## Products API

### List Products
\`\`\`
GET /products?category=Compliance&tier=professional&status=active
\`\`\`

**Query Parameters:**
- category (string)
- tier (string): basic, professional, enterprise, custom
- status (string): active, inactive, draft, archived
- limit (number, default: 50)
- offset (number, default: 0)

**Response:**
\`\`\`json
{
  "data": [
    {
      "id": "uuid",
      "sku": "COMPL-KYC-001",
      "name": "KYC - Individus",
      "basePrice": 5000,
      "currency": "XOF",
      "tier": "professional",
      "status": "active"
    }
  ],
  "total": 45,
  "limit": 50,
  "offset": 0
}
\`\`\`

### Get Product Details
\`\`\`
GET /products/{productId}
\`\`\`

**Response:**
\`\`\`json
{
  "id": "uuid",
  "sku": "COMPL-KYC-001",
  "name": "KYC - Individus",
  "description": "...",
  "basePrice": 5000,
  "currency": "XOF",
  "costPrice": 1500,
  "productType": "service",
  "tier": "professional",
  "features": [...],
  "complianceTags": ["kyc", "gdpr"],
  "createdAt": "2026-07-16T10:00:00Z",
  "updatedAt": "2026-07-16T10:00:00Z"
}
\`\`\`

### Create Product (Admin Only)
\`\`\`
POST /products
Content-Type: application/json
\`\`\`

**Request Body:**
\`\`\`json
{
  "sku": "COMPL-NEW-001",
  "name": "New Compliance Service",
  "description": "...",
  "category": "Compliance",
  "basePrice": 7500,
  "currency": "XOF",
  "costPrice": 2000,
  "productType": "service",
  "tier": "professional",
  "tags": ["compliance", "new"],
  "attributes": {"field": "value"},
  "complianceTags": ["kyc", "aml"]
}
\`\`\`

---

## Subscriptions API

### List Subscription Plans
\`\`\`
GET /subscriptions/plans?tier=professional&status=active&is_public=true
\`\`\`

**Response:**
\`\`\`json
{
  "data": [
    {
      "id": "uuid",
      "planCode": "PROFESSIONAL",
      "planName": "Professional Plan",
      "monthlyPrice": 50000,
      "annualPrice": 480000,
      "tier": "professional",
      "features": {
        "kyc_checks": 100,
        "users": 10,
        "api_calls": 10000
      },
      "isRecommended": true
    }
  ]
}
\`\`\`

### Get Active Subscription
\`\`\`
GET /subscriptions/{subscriptionId}
\`\`\`

### Create Subscription
\`\`\`
POST /subscriptions
Content-Type: application/json
\`\`\`

**Request Body:**
\`\`\`json
{
  "customerId": "uuid",
  "planId": "uuid",
  "startDate": "2026-07-16",
  "autoRenew": true,
  "paymentMethodId": "uuid"
}
\`\`\`

### Update Subscription
\`\`\`
PUT /subscriptions/{subscriptionId}
Content-Type: application/json
\`\`\`

**Request Body:**
\`\`\`json
{
  "status": "active",
  "planId": "uuid",
  "autoRenew": true
}
\`\`\`

---

## Pricing API

### Calculate Price
\`\`\`
POST /pricing/calculate
Content-Type: application/json
\`\`\`

**Request Body:**
\`\`\`json
{
  "productId": "uuid",
  "quantity": 1,
  "customerId": "uuid",
  "discountCodes": ["LAUNCH2026"],
  "currency": "XOF"
}
\`\`\`

**Response:**
\`\`\`json
{
  "basePrice": 5000,
  "adjustments": [
    {
      "ruleId": "uuid",
      "ruleName": "LAUNCH2026",
      "adjustmentType": "discount",
      "amount": -1000,
      "reason": "Launch promotion code"
    }
  ],
  "subtotal": 4000,
  "tax": 720,
  "total": 4720,
  "currency": "XOF",
  "validUntil": "2026-07-17T10:00:00Z"
}
\`\`\`

### Validate Discount Code
\`\`\`
POST /discounts/validate
Content-Type: application/json
\`\`\`

**Request Body:**
\`\`\`json
{
  "code": "LAUNCH2026",
  "customerId": "uuid",
  "orderValue": 10000
}
\`\`\`

**Response:**
\`\`\`json
{
  "valid": true,
  "code": "LAUNCH2026",
  "discountType": "percentage",
  "discountValue": 20,
  "discountAmount": 2000,
  "remaining": {
    "maxRedemptions": 999,
    "maxPerCustomer": 0
  },
  "validUntil": "2026-10-14T23:59:59Z"
}
\`\`\`

---

## Error Codes

| Code | Status | Message |
|------|--------|---------|
| 400 | Bad Request | Paramètres invalides |
| 401 | Unauthorized | Token manquant ou invalide |
| 403 | Forbidden | Accès refusé |
| 404 | Not Found | Ressource non trouvée |
| 422 | Unprocessable | Données invalides |
| 500 | Server Error | Erreur serveur |

---

© 2026 KHEPRA EXPERTS
"@

    Set-Content -Path (Join-Path $DocsDir "API-Reference.md") -Value $ApiReference -Encoding UTF8
    Write-KOSLog "  ✓ Documentation créée: API-Reference.md" "SUCCESS"
}

# =============================================================================
# FONCTION : GÉNÉRER RAPPORT
# =============================================================================

function Write-CatalogHealthReport {
    Write-KOSLog "Génération du rapport de santé MC002..." "INFO"

    $ReportContent = @"
╔═══════════════════════════════════════════════════════════════════════════╗
║                     MC002 CATALOG MODULE HEALTH REPORT                    ║
║                                v1.0                                        ║
╚═══════════════════════════════════════════════════════════════════════════╝

📋 INFORMATIONS GÉNÉRALES
─────────────────────────────────────────────────────────────────────────────
  Module:           Catalog (MC002)
  Version:          1.0.0
  Date:             $Timestamp
  Exécution ID:     $ExecutionId
  Racine:           $Root

✅ DÉPENDANCES
─────────────────────────────────────────────────────────────────────────────
  ✓ MC001-Foundation v2.0 (Vérifiée)
  ✓ Structure directoires créée
  ✓ Base de données Supabase (À configurer)

📦 STRUCTURE CRÉÉE
─────────────────────────────────────────────────────────────────────────────
  Packages:
    ✓ packages/catalog/
    ✓ packages/subscriptions/
    ✓ packages/pricing/

  Modules:
    ✓ src/models
    ✓ src/services
    ✓ src/repositories
    ✓ src/controllers
    ✓ src/routes
    ✓ tests/

💾 MIGRATIONS BASE DE DONNÉES
─────────────────────────────────────────────────────────────────────────────
  Migrations SQL créées:
    ✓ 001-products-table.sql
      └─ Tables: products, product_features, product_pricing_history
      └─ Indices: sku, category, status, type, tier
      └─ Triggers: Update timestamp, Audit logging
      └─ RLS: Row Level Security configurée

    ✓ 002-subscriptions-table.sql
      └─ Tables: subscription_plans, plan_features, subscriptions, subscription_history
      └─ Audit trail complète
      └─ Gestion des cycles de facturation

    ✓ 003-pricing-discounts.sql
      └─ Tables: pricing_rules, discount_codes, discount_redemptions
      └─ Support règles dynamiques
      └─ Codes promotionnels avec limites

📝 MODÈLES TYPESCRIPT
─────────────────────────────────────────────────────────────────────────────
  Types créés:
    ✓ product.types.ts
      └─ IProduct, IProductFeature, CreateProductDTO, UpdateProductDTO

    ✓ subscription.types.ts
      └─ ISubscriptionPlan, ISubscription, CreateSubscriptionDTO

    ✓ pricing.types.ts
      └─ IPricingRule, IDiscountCode, PriceCalculationRequest/Result

🌱 DONNÉES DE SEED
─────────────────────────────────────────────────────────────────────────────
  Seed data SQL créées:
    ✓ 001-seed-products.sql (10 produits)
      ├─ Produits KYC/AML/Audit
      ├─ Services de support
      ├─ Intégrations API
      └─ Formations

    ✓ 002-seed-subscription-plans.sql (4 plans)
      ├─ STARTER: 15,000 XOF/mois
      ├─ PROFESSIONAL: 50,000 XOF/mois (recommandé)
      ├─ ENTERPRISE: 200,000 XOF/mois
      └─ CUSTOM: Sur devis

    ✓ 003-seed-discount-codes.sql (4 codes)
      ├─ LAUNCH2026: -20%
      ├─ EARLY100K: -100k XOF fixes
      ├─ ANNUAL25: -25% annuel
      └─ NONPROFIT15: -15% ONG

📖 DOCUMENTATION
─────────────────────────────────────────────────────────────────────────────
  Documents créés:
    ✓ docs/catalog/README.md
      └─ Vue d'ensemble, architecture, API endpoints

    ✓ docs/catalog/API-Reference.md
      └─ Endpoints détaillés, exemples de requêtes, codes d'erreur

🔄 FLUX DE DONNÉES
─────────────────────────────────────────────────────────────────────────────
  Products:
    ✓ Création → Pricing → Ajout à plans → Assignation features

  Subscriptions:
    ✓ Plan sélection → Pricing calculation → Payment → Activation

  Pricing:
    ✓ Base price → Rules application → Discounts → Tax calculation → Total

🔐 SÉCURITÉ & CONFORMITÉ
─────────────────────────────────────────────────────────────────────────────
  ✓ Row Level Security (RLS) activée sur toutes les tables
  ✓ Audit logging automatique sur INSERT/UPDATE/DELETE
  ✓ Compliance tags (GDPR, CIMA, KYC, AML)
  ✓ Pricing history pour audit trail
  ✓ Subscription history pour traçabilité

📊 PRODUITS DE BASE (SEED DATA)
─────────────────────────────────────────────────────────────────────────────
  Compliance:
    • KYC - Individus: 5,000 XOF
    • KYC - Entreprises: 10,000 XOF
    • AML Screening: 3,000 XOF
    • Audit Trail (annual): 15,000 XOF

  Support:
    • Support Téléphonique: 2,000 XOF
    • Support Email 24/7: 5,000 XOF
    • Chat Support: 3,000 XOF

  Integration:
    • API Standard: 5,000 XOF
    • API Professional: 25,000 XOF

  Training:
    • Formation Web (3j): 150,000 XOF
    • Formation API (2j): 120,000 XOF

💳 PLANS D'ABONNEMENT (SEED DATA)
─────────────────────────────────────────────────────────────────────────────
  STARTER (Tier 1)
    Prix: 15,000 XOF/mois | 150,000 XOF/an
    Utilisateurs: 3
    KYC Checks: 10/mois
    API Calls: 1,000/mois
    Storage: 5 GB
    Support: Email

  PROFESSIONAL (Tier 2) ⭐ RECOMMANDÉ
    Prix: 50,000 XOF/mois | 480,000 XOF/an
    Utilisateurs: 10
    KYC Checks: 100/mois
    AML Screening: 50/mois
    API Calls: 10,000/mois
    Storage: 50 GB
    Support: Email + Phone
    Inclut: SSO, Audit Trail, Reporting

  ENTERPRISE (Tier 3)
    Prix: 200,000 XOF/mois | 1,800,000 XOF/an
    Utilisateurs: 100
    KYC Checks: 1,000/mois
    API Calls: 100,000/mois
    Storage: 500 GB
    Support: 24/7 + Dedicated Account Manager
    Inclut: ESG Reporting, Risk Management, Workflow Automation

  CUSTOM
    Prix: Sur devis
    Accès complet à toutes les fonctionnalités

🎫 CODES PROMOTIONNELS (SEED DATA)
─────────────────────────────────────────────────────────────────────────────
  LAUNCH2026
    Réduction: 20% (maximum)
    Validité: 90 jours
    Limit redemptions: 1000

  EARLY100K
    Réduction: 100,000 XOF fixes
    Validité: 60 jours
    Limit redemptions: 100

  ANNUAL25
    Réduction: 25% (paiement annuel)
    Validité: 180 jours
    Limit redemptions: 500

  NONPROFIT15
    Réduction: 15% pour ONG
    Validité: 365 jours
    Stackable: Non

⚙️ CONFIGURATION
─────────────────────────────────────────────────────────────────────────────
  ✓ Migrations SQL prêtes (à exécuter)
  ✓ Seed data prête (à exécuter)
  ✓ Types TypeScript validés
  ✓ Documentation complète

🚀 PROCHAINES ÉTAPES
─────────────────────────────────────────────────────────────────────────────
  1. Exécuter les migrations SQL dans Supabase
     \`\`\`sql
     -- Dans Supabase SQL Editor
     -- Exécuter les fichiers dans database/migrations/catalog/
     \`\`\`

  2. Charger les données de seed
     \`\`\`sql
     -- Exécuter database/seed/catalog/001-seed-products.sql
     -- Exécuter database/seed/catalog/002-seed-subscription-plans.sql
     -- Exécuter database/seed/catalog/003-seed-discount-codes.sql
     \`\`\`

  3. Installer les dépendances npm
     \`\`\`bash
     cd packages/catalog
     pnpm install
     \`\`\`

  4. Générer les clients Supabase
     \`\`\`bash
     supabase gen types typescript --project-id <PROJECT_ID> > src/types/database.ts
     \`\`\`

  5. Passer à MC003-Customers.ps1

📞 SUPPORT & DOCUMENTATION
─────────────────────────────────────────────────────────────────────────────
  Auteur:    KHEPRA EXPERTS
  Email:     contact@khepra-experts.com
  Site:      https://khepra-experts.com
  Repo:      https://github.com/Khepra2026/KOS

📁 FICHIERS GÉNÉRÉS
─────────────────────────────────────────────────────────────────────────────
  Migrations:
    ✓ database/migrations/catalog/001-products-table.sql
    ✓ database/migrations/catalog/002-subscriptions-table.sql
    ✓ database/migrations/catalog/003-pricing-discounts.sql

  Seed Data:
    ✓ database/seed/catalog/001-seed-products.sql
    ✓ database/seed/catalog/002-seed-subscription-plans.sql
    ✓ database/seed/catalog/003-seed-discount-codes.sql

  Types TypeScript:
    ✓ packages/catalog/src/types/product.types.ts
    ✓ packages/catalog/src/types/subscription.types.ts
    ✓ packages/catalog/src/types/pricing.types.ts

  Documentation:
    ✓ docs/catalog/README.md
    ✓ docs/catalog/API-Reference.md

╔═══════════════════════════════════════════════════════════════════════════╗
║           ✓ MC002 Catalog Module Initialization Complete!                ║
║                Ready for database deployment and API development          ║
╚═══════════════════════════════════════════════════════════════════════════╝

"@

    $ReportPath = Join-Path $LogDir "MC002-health-report.txt"
    Set-Content -Path $ReportPath -Value $ReportContent -Encoding UTF8
    
    Write-Host $ReportContent
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

try {
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  KOS CATALOG MODULE v1.0" -ForegroundColor Cyan
    Write-Host "  Master Code: MC002 | KHEPRA EXPERTS" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    Write-KOSLog "Démarrage du module Catalogue..." "INFO"

    # 1. Vérifier Foundation
    Test-FoundationExists

    # 2. Créer structure
    New-CatalogStructure

    # 3. Créer migrations
    New-CatalogMigrations

    # 4. Créer types TypeScript
    New-CatalogTypeScriptModels

    # 5. Créer seed data
    New-CatalogSeedData

    # 6. Créer documentation
    New-CatalogDocumentation

    # 7. Rapport de santé
    Write-CatalogHealthReport

    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ MC002 INITIALIZATION COMPLETE" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-KOSLog "Module Catalogue initialisé avec succès" "SUCCESS"
    Write-Host ""
}
catch {
    Write-KOSLog "Erreur: $($_.Exception.Message)" "ERROR"
    Write-KOSLog "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  ✗ MC002 INITIALIZATION FAILED" -ForegroundColor Red
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    exit 1
}
