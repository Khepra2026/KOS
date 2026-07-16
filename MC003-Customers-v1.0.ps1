<#
==============================================================================
 KOS ENTERPRISE CUSTOMERS MODULE
 Master Code : MC003
 Version     : 1.0.0 (Enterprise)
 Auteur      : KHEPRA EXPERTS
 Date        : 2026-07-16
 Status      : Production Ready
==============================================================================

DESCRIPTION
  Initialisation du module Gestion des Clients KOS.
  - Modèle client (individuel/entreprise)
  - KYC/AML workflows
  - Gestion des contacts et interactions
  - Compliance status tracking
  - Profile management et document storage
  - Audit trail complet

USAGE
  .\MC003-Customers.ps1

PREREQUISITES
  - MC001-Foundation-v2.0.ps1 exécuté
  - MC002-Catalog-v1.0.ps1 exécuté
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
$LogFile = Join-Path $LogDir "MC003-v1.0.log"
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
        "packages\subscriptions",
        "packages\pricing",
        "database\migrations\catalog"
    )

    foreach ($Dir in $RequiredDirs) {
        $Path = Join-Path $Root $Dir
        if (-not (Test-Path $Path)) {
            throw "Dossier manquant: $Dir. Exécutez MC002 d'abord."
        }
    }

    Write-KOSLog "MC001 & MC002 vérifiés ✓" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER STRUCTURE CUSTOMERS
# =============================================================================

function New-CustomersStructure {
    Write-KOSLog "Création de la structure du module Clients..." "INFO"

    $CustomersFolders = @(
        # CRM Main
        "packages\crm",
        "packages\crm\src",
        "packages\crm\src\models",
        "packages\crm\src\services",
        "packages\crm\src\repositories",
        "packages\crm\src\controllers",
        "packages\crm\src\routes",
        "packages\crm\src\middleware",
        "packages\crm\src\validators",
        "packages\crm\src\utils",
        "packages\crm\src\types",
        "packages\crm\tests",

        # Customers
        "packages\crm\src\domains\customers",
        "packages\crm\src\domains\customers\services",
        "packages\crm\src\domains\customers\repositories",

        # Contacts
        "packages\crm\src\domains\contacts",
        "packages\crm\src\domains\contacts\services",

        # Companies
        "packages\crm\src\domains\companies",
        "packages\crm\src\domains\companies\services",

        # KYC Module
        "packages\compliance\kyc",
        "packages\compliance\kyc\src",
        "packages\compliance\kyc\src\workflows",
        "packages\compliance\kyc\src\services",
        "packages\compliance\kyc\src\validators",
        "packages\compliance\kyc\src\repositories",

        # AML Module
        "packages\compliance\aml",
        "packages\compliance\aml\src",
        "packages\compliance\aml\src\services",
        "packages\compliance\aml\src\screening",
        "packages\compliance\aml\src\watchlists"
    )

    $CreatedCount = 0
    foreach ($Folder in $CustomersFolders) {
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

function New-CustomersMigrations {
    Write-KOSLog "Création des migrations de base de données..." "INFO"

    $MigrationDir = Join-Path $Root "database\migrations\customers"

    # Migration 001 - Customers Core
    $Migration001 = @"
-- ==============================================================================
-- KOS Customers Module - Core Tables
-- Migration: 001-customers-base
-- Date: 2026-07-16
-- ==============================================================================

-- Customer Types Enum-like
CREATE TYPE customer_type AS ENUM ('individual', 'company', 'government', 'ngo');
CREATE TYPE customer_status AS ENUM ('prospect', 'onboarding', 'active', 'suspended', 'inactive', 'archived');
CREATE TYPE kyc_status AS ENUM ('not_started', 'pending', 'verified', 'rejected', 'expired', 'under_review');
CREATE TYPE aml_status AS ENUM ('not_screened', 'pending', 'clean', 'flagged', 'blocked', 'under_review');
CREATE TYPE document_type AS ENUM ('passport', 'id_card', 'driving_license', 'business_registration', 'tax_id', 'proof_of_address', 'bank_statement', 'incorporation_certificate', 'articles_of_association', 'resolution', 'beneficial_owner_declaration', 'other');

-- Main Customers Table
CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Identification
    customer_number VARCHAR(100) UNIQUE NOT NULL,
    customer_type customer_type NOT NULL,
    
    -- For Individuals
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    date_of_birth DATE,
    gender VARCHAR(20),
    nationality VARCHAR(3), -- ISO 3166-1 alpha-3
    
    -- For Companies
    company_name VARCHAR(255),
    company_registration_number VARCHAR(100),
    company_type VARCHAR(100), -- SARL, SA, EIRL, etc.
    business_sector VARCHAR(100),
    
    -- Contact Information
    email VARCHAR(255) NOT NULL,
    phone_primary VARCHAR(20),
    phone_secondary VARCHAR(20),
    
    -- Address
    street_address VARCHAR(255),
    city VARCHAR(100),
    postal_code VARCHAR(20),
    country VARCHAR(3), -- ISO 3166-1 alpha-3
    state_province VARCHAR(100),
    
    -- Additional Address for Companies
    registered_address TEXT,
    business_address TEXT,
    
    -- Compliance Status
    kyc_status kyc_status DEFAULT 'not_started',
    kyc_verified_date TIMESTAMP WITH TIME ZONE,
    kyc_expires_date TIMESTAMP WITH TIME ZONE,
    kyc_verified_by UUID,
    
    aml_status aml_status DEFAULT 'not_screened',
    aml_screened_date TIMESTAMP WITH TIME ZONE,
    aml_expires_date TIMESTAMP WITH TIME ZONE,
    aml_screened_by UUID,
    
    -- Compliance Details
    politically_exposed_person BOOLEAN DEFAULT false,
    pep_country VARCHAR(3),
    sanctions_risk_level VARCHAR(50), -- 'low', 'medium', 'high'
    
    -- Customer Status
    status customer_status DEFAULT 'prospect',
    is_active BOOLEAN DEFAULT true,
    
    -- Business Context
    annual_revenue DECIMAL(19, 2),
    employee_count INTEGER,
    estimated_annual_volume DECIMAL(19, 2),
    
    -- Risk Assessment
    risk_score DECIMAL(3, 1), -- 0-10
    risk_level VARCHAR(50), -- 'low', 'medium', 'high', 'very_high'
    risk_assessment_date TIMESTAMP WITH TIME ZONE,
    risk_assessment_by UUID,
    
    -- Metadata & Preferences
    tags JSONB DEFAULT '[]'::jsonb,
    custom_fields JSONB DEFAULT '{}'::jsonb,
    communication_preferences JSONB DEFAULT '{"email": true, "phone": true, "sms": false}'::jsonb,
    
    -- Relationships
    parent_company_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    created_from_lead_id UUID,
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_by UUID,
    deleted_at TIMESTAMP WITH TIME ZONE,
    
    CONSTRAINT customers_email_check CHECK (email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$'),
    CONSTRAINT customers_risk_score_check CHECK (risk_score >= 0 AND risk_score <= 10)
);

CREATE INDEX idx_customers_number ON customers(customer_number);
CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_customers_type ON customers(customer_type);
CREATE INDEX idx_customers_status ON customers(status);
CREATE INDEX idx_customers_kyc_status ON customers(kyc_status);
CREATE INDEX idx_customers_aml_status ON customers(aml_status);
CREATE INDEX idx_customers_pep ON customers(politically_exposed_person) WHERE politically_exposed_person = true;
CREATE INDEX idx_customers_risk_level ON customers(risk_level);
CREATE INDEX idx_customers_created_at ON customers(created_at DESC);
CREATE INDEX idx_customers_deleted_at ON customers(deleted_at) WHERE deleted_at IS NULL;

-- Contacts Table (Multiple contacts per customer)
CREATE TABLE IF NOT EXISTS customer_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Contact Info
    contact_type VARCHAR(50) NOT NULL, -- 'primary', 'billing', 'technical', 'legal', 'authorized_signatory'
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(20),
    title VARCHAR(100),
    department VARCHAR(100),
    
    -- Additional Info
    date_of_birth DATE,
    nationality VARCHAR(3),
    id_number VARCHAR(100),
    
    -- For Authorized Signatories
    is_authorized_signatory BOOLEAN DEFAULT false,
    signatory_authority TEXT,
    signatory_start_date DATE,
    signatory_end_date DATE,
    
    -- Relationship
    reports_to UUID REFERENCES customer_contacts(id) ON DELETE SET NULL,
    
    -- Status
    is_active BOOLEAN DEFAULT true,
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID
);

CREATE INDEX idx_customer_contacts_customer_id ON customer_contacts(customer_id);
CREATE INDEX idx_customer_contacts_type ON customer_contacts(contact_type);
CREATE INDEX idx_customer_contacts_email ON customer_contacts(email);

-- Beneficial Owners Table (For companies, required for KYC)
CREATE TABLE IF NOT EXISTS beneficial_owners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Owner Info
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE NOT NULL,
    nationality VARCHAR(3) NOT NULL,
    id_number VARCHAR(100),
    id_type document_type,
    
    -- Ownership Details
    ownership_percentage DECIMAL(5, 2) NOT NULL,
    ownership_type VARCHAR(100), -- 'direct', 'indirect', 'beneficial', 'ultimate_beneficial_owner'
    
    -- Status
    kyc_verified BOOLEAN DEFAULT false,
    kyc_verified_date TIMESTAMP WITH TIME ZONE,
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID
);

CREATE INDEX idx_beneficial_owners_customer_id ON beneficial_owners(customer_id);

-- Customer Documents Table
CREATE TABLE IF NOT EXISTS customer_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Document Info
    document_type document_type NOT NULL,
    document_name VARCHAR(255) NOT NULL,
    document_number VARCHAR(100),
    
    -- Storage
    file_url VARCHAR(1024) NOT NULL,
    file_name VARCHAR(255),
    file_size_bytes INTEGER,
    file_hash VARCHAR(64), -- SHA-256 for integrity
    file_uploaded_at TIMESTAMP WITH TIME ZONE,
    
    -- Validity
    issue_date DATE,
    expiry_date DATE,
    is_expired BOOLEAN DEFAULT false,
    
    -- Verification
    is_verified BOOLEAN DEFAULT false,
    verified_at TIMESTAMP WITH TIME ZONE,
    verified_by UUID,
    verification_notes TEXT,
    
    -- Compliance
    kyc_required BOOLEAN DEFAULT true,
    aml_required BOOLEAN DEFAULT false,
    
    -- Metadata
    tags JSONB DEFAULT '[]'::jsonb,
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID
);

CREATE INDEX idx_customer_documents_customer_id ON customer_documents(customer_id);
CREATE INDEX idx_customer_documents_type ON customer_documents(document_type);
CREATE INDEX idx_customer_documents_verified ON customer_documents(is_verified);

-- Triggers
CREATE OR REPLACE FUNCTION update_customers_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_customers_updated_at ON customers;
CREATE TRIGGER tr_customers_updated_at
BEFORE UPDATE ON customers
FOR EACH ROW
EXECUTE FUNCTION update_customers_updated_at();

CREATE OR REPLACE FUNCTION update_customer_contacts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_customer_contacts_updated_at ON customer_contacts;
CREATE TRIGGER tr_customer_contacts_updated_at
BEFORE UPDATE ON customer_contacts
FOR EACH ROW
EXECUTE FUNCTION update_customer_contacts_updated_at();

-- Enable RLS
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE beneficial_owners ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_documents ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Customers readable by authenticated" ON customers
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Admins can manage all customers" ON customers
    FOR ALL TO authenticated USING (auth.jwt() ->> 'role' = 'admin' OR auth.uid() = created_by);
"@

    Set-Content -Path (Join-Path $MigrationDir "001-customers-base.sql") -Value $Migration001 -Encoding UTF8
    Write-KOSLog "  ✓ Migration 001 créée: customers-base" "SUCCESS"

    # Migration 002 - KYC Workflows
    $Migration002 = @"
-- ==============================================================================
-- KOS Customers Module - KYC Workflows
-- Migration: 002-kyc-workflows
-- Date: 2026-07-16
-- ==============================================================================

-- KYC Workflow Status Types
CREATE TYPE kyc_workflow_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected', 'expired', 'cancelled');
CREATE TYPE kyc_check_type AS ENUM ('identity_verification', 'address_verification', 'beneficial_owner_verification', 'pep_check', 'sanctions_check', 'document_verification', 'video_verification', 'background_check');

-- KYC Workflows Table
CREATE TABLE IF NOT EXISTS kyc_workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Workflow Info
    workflow_code VARCHAR(100) UNIQUE NOT NULL,
    workflow_type VARCHAR(50) NOT NULL, -- 'individual', 'company', 'enhanced', 'risk_based'
    
    -- Status
    status kyc_workflow_status DEFAULT 'pending',
    risk_level VARCHAR(50), -- 'low', 'medium', 'high' - determines workflow depth
    
    -- Dates
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    
    -- Verification Details
    verification_method VARCHAR(50), -- 'manual', 'automated', 'video_call', 'hybrid'
    verification_provider VARCHAR(100),
    verification_reference VARCHAR(255),
    
    -- Results
    overall_result VARCHAR(50), -- 'approved', 'rejected', 'pending_manual_review'
    rejection_reason TEXT,
    
    -- Metadata
    metadata JSONB DEFAULT '{}',
    notes TEXT,
    
    -- Audit
    created_by UUID,
    completed_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_kyc_workflows_customer_id ON kyc_workflows(customer_id);
CREATE INDEX idx_kyc_workflows_status ON kyc_workflows(status);
CREATE INDEX idx_kyc_workflows_code ON kyc_workflows(workflow_code);

-- KYC Checks Table (Individual checks within a workflow)
CREATE TABLE IF NOT EXISTS kyc_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id UUID NOT NULL REFERENCES kyc_workflows(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Check Info
    check_type kyc_check_type NOT NULL,
    check_name VARCHAR(255) NOT NULL,
    
    -- Execution
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'in_progress', 'completed', 'failed'
    result VARCHAR(50), -- 'passed', 'failed', 'manual_review_needed'
    
    -- Details
    check_parameters JSONB DEFAULT '{}',
    check_result_data JSONB DEFAULT '{}',
    
    -- Dates
    scheduled_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    
    -- Reference
    external_check_id VARCHAR(255),
    external_provider VARCHAR(100),
    
    -- Issues Found
    has_issues BOOLEAN DEFAULT false,
    issues JSONB DEFAULT '[]'::jsonb, -- Array of detected issues
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID
);

CREATE INDEX idx_kyc_checks_workflow_id ON kyc_checks(workflow_id);
CREATE INDEX idx_kyc_checks_customer_id ON kyc_checks(customer_id);
CREATE INDEX idx_kyc_checks_type ON kyc_checks(check_type);
CREATE INDEX idx_kyc_checks_status ON kyc_checks(status);

-- KYC Audit Trail
CREATE TABLE IF NOT EXISTS kyc_audit_trail (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id UUID NOT NULL REFERENCES kyc_workflows(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Event
    event_type VARCHAR(100) NOT NULL, -- 'workflow_started', 'check_completed', 'status_changed', 'document_uploaded', 'manual_review', 'approved', 'rejected'
    event_description TEXT,
    
    -- Status Change
    from_status VARCHAR(50),
    to_status VARCHAR(50),
    
    -- User Action
    action_by UUID,
    action_notes TEXT,
    
    -- Timestamp
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_kyc_audit_trail_workflow_id ON kyc_audit_trail(workflow_id);
CREATE INDEX idx_kyc_audit_trail_event_type ON kyc_audit_trail(event_type);

-- Enable RLS
ALTER TABLE kyc_workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE kyc_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE kyc_audit_trail ENABLE ROW LEVEL SECURITY;
"@

    Set-Content -Path (Join-Path $MigrationDir "002-kyc-workflows.sql") -Value $Migration002 -Encoding UTF8
    Write-KOSLog "  ✓ Migration 002 créée: kyc-workflows" "SUCCESS"

    # Migration 003 - AML & Compliance
    $Migration003 = @"
-- ==============================================================================
-- KOS Customers Module - AML & Compliance Monitoring
-- Migration: 003-aml-compliance
-- Date: 2026-07-16
-- ==============================================================================

-- AML Screening Types
CREATE TYPE aml_screening_type AS ENUM ('initial', 'periodic', 'event_based', 'transaction_based');
CREATE TYPE sanctions_list_type AS ENUM ('un_sdny', 'eu_sanctions', 'uk_sanctions', 'us_ofac', 'fatf', 'local_sanctions', 'other');

-- AML Screenings Table
CREATE TABLE IF NOT EXISTS aml_screenings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Screening Info
    screening_code VARCHAR(100) UNIQUE NOT NULL,
    screening_type aml_screening_type NOT NULL,
    
    -- Scope
    screening_scope VARCHAR(50), -- 'name_only', 'full_profile', 'transaction_based', 'enhanced'
    
    -- Results
    status aml_status DEFAULT 'pending',
    result VARCHAR(50), -- 'clean', 'flagged', 'blocked', 'manual_review'
    risk_indicators JSONB DEFAULT '[]'::jsonb, -- Array of matched sanctions lists
    
    -- Hit Details
    has_hits BOOLEAN DEFAULT false,
    hit_count INTEGER DEFAULT 0,
    hits_summary JSONB DEFAULT '[]'::jsonb, -- Array of sanctions list matches
    
    -- Dates
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    
    -- Metadata
    screening_provider VARCHAR(100),
    external_reference VARCHAR(255),
    notes TEXT,
    
    -- Audit
    created_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_aml_screenings_customer_id ON aml_screenings(customer_id);
CREATE INDEX idx_aml_screenings_status ON aml_screenings(status);
CREATE INDEX idx_aml_screenings_code ON aml_screenings(screening_code);
CREATE INDEX idx_aml_screenings_result ON aml_screenings(result);

-- Sanctions Hits Table (When screening finds matches)
CREATE TABLE IF NOT EXISTS sanctions_hits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    screening_id UUID NOT NULL REFERENCES aml_screenings(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Hit Info
    hit_name VARCHAR(255) NOT NULL,
    hit_match_score DECIMAL(5, 2), -- Confidence score 0-100
    
    -- Source
    sanctions_list_type sanctions_list_type NOT NULL,
    sanctions_list_name VARCHAR(100),
    external_id VARCHAR(255),
    
    -- Details
    entity_type VARCHAR(50), -- 'individual', 'organization', 'vessel', 'aircraft'
    entity_nationality VARCHAR(3),
    entity_metadata JSONB DEFAULT '{}',
    
    -- Dates
    hit_date_added DATE,
    hit_date_effective DATE,
    
    -- Resolution
    is_resolved BOOLEAN DEFAULT false,
    resolution_status VARCHAR(50), -- 'false_positive', 'confirmed', 'escalated'
    resolution_notes TEXT,
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolved_by UUID,
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sanctions_hits_screening_id ON sanctions_hits(screening_id);
CREATE INDEX idx_sanctions_hits_customer_id ON sanctions_hits(customer_id);
CREATE INDEX idx_sanctions_hits_resolved ON sanctions_hits(is_resolved);

-- Compliance Monitoring Table
CREATE TABLE IF NOT EXISTS compliance_monitoring (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Monitoring Info
    monitoring_type VARCHAR(50) NOT NULL, -- 'ongoing', 'event_triggered', 'periodic'
    monitoring_frequency VARCHAR(50), -- 'daily', 'weekly', 'monthly', 'quarterly', 'annual'
    
    -- Status
    is_active BOOLEAN DEFAULT true,
    last_check_date TIMESTAMP WITH TIME ZONE,
    next_check_date TIMESTAMP WITH TIME ZONE,
    
    -- Thresholds
    transaction_threshold DECIMAL(19, 2),
    alert_threshold_count INTEGER,
    
    -- Recent Activity
    recent_alerts_count INTEGER DEFAULT 0,
    risk_flag BOOLEAN DEFAULT false,
    risk_reason VARCHAR(255),
    
    -- Metadata
    monitored_attributes JSONB DEFAULT '[]'::jsonb, -- What's being monitored
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID
);

CREATE INDEX idx_compliance_monitoring_customer_id ON compliance_monitoring(customer_id);
CREATE INDEX idx_compliance_monitoring_active ON compliance_monitoring(is_active);

-- Compliance Alerts Table
CREATE TABLE IF NOT EXISTS compliance_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    monitoring_id UUID REFERENCES compliance_monitoring(id) ON DELETE CASCADE,
    
    -- Alert Info
    alert_type VARCHAR(100) NOT NULL, -- 'kyc_expiry_warning', 'sanctions_hit', 'pep_update', 'risk_score_increase', 'unusual_activity'
    alert_severity VARCHAR(50) NOT NULL, -- 'low', 'medium', 'high', 'critical'
    alert_title VARCHAR(255) NOT NULL,
    alert_description TEXT,
    
    -- Status
    status VARCHAR(50) DEFAULT 'open', -- 'open', 'in_progress', 'resolved', 'false_positive', 'escalated'
    
    -- Details
    alert_data JSONB DEFAULT '{}',
    
    -- Response
    action_taken TEXT,
    action_taken_by UUID,
    action_taken_at TIMESTAMP WITH TIME ZONE,
    
    -- Dates
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_compliance_alerts_customer_id ON compliance_alerts(customer_id);
CREATE INDEX idx_compliance_alerts_severity ON compliance_alerts(alert_severity);
CREATE INDEX idx_compliance_alerts_status ON compliance_alerts(status);
CREATE INDEX idx_compliance_alerts_type ON compliance_alerts(alert_type);

-- Enable RLS
ALTER TABLE aml_screenings ENABLE ROW LEVEL SECURITY;
ALTER TABLE sanctions_hits ENABLE ROW LEVEL SECURITY;
ALTER TABLE compliance_monitoring ENABLE ROW LEVEL SECURITY;
ALTER TABLE compliance_alerts ENABLE ROW LEVEL SECURITY;
"@

    Set-Content -Path (Join-Path $MigrationDir "003-aml-compliance.sql") -Value $Migration003 -Encoding UTF8
    Write-KOSLog "  ✓ Migration 003 créée: aml-compliance" "SUCCESS"

    # Migration 004 - Customer Interactions
    $Migration004 = @"
-- ==============================================================================
-- KOS Customers Module - Interactions & Activity
-- Migration: 004-customer-interactions
-- Date: 2026-07-16
-- ==============================================================================

-- Customer Interactions (CRM activities)
CREATE TABLE IF NOT EXISTS customer_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Interaction Info
    interaction_type VARCHAR(50) NOT NULL, -- 'call', 'email', 'meeting', 'support_ticket', 'note', 'document_submission', 'kyc_request'
    interaction_title VARCHAR(255) NOT NULL,
    interaction_description TEXT,
    
    -- Channel
    channel VARCHAR(50), -- 'phone', 'email', 'in_person', 'video_call', 'chat', 'portal'
    
    -- Participants
    created_by UUID NOT NULL,
    assigned_to UUID,
    
    -- Status
    status VARCHAR(50) DEFAULT 'open', -- 'open', 'in_progress', 'closed', 'pending', 'escalated'
    
    -- Dates
    scheduled_date TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    next_follow_up TIMESTAMP WITH TIME ZONE,
    
    -- Details
    details JSONB DEFAULT '{}',
    attachments JSONB DEFAULT '[]'::jsonb,
    
    -- Outcome
    outcome VARCHAR(50), -- 'resolved', 'pending', 'requires_action', 'escalated'
    outcome_notes TEXT,
    
    -- Audit
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_customer_interactions_customer_id ON customer_interactions(customer_id);
CREATE INDEX idx_customer_interactions_type ON customer_interactions(interaction_type);
CREATE INDEX idx_customer_interactions_status ON customer_interactions(status);
CREATE INDEX idx_customer_interactions_created_by ON customer_interactions(created_by);
CREATE INDEX idx_customer_interactions_assigned_to ON customer_interactions(assigned_to);

-- Customer Activity Log
CREATE TABLE IF NOT EXISTS customer_activity_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    
    -- Activity Info
    activity_type VARCHAR(100) NOT NULL, -- 'login', 'document_uploaded', 'kyc_completed', 'subscription_created', 'payment_made', 'support_opened', 'data_accessed'
    activity_description TEXT,
    
    -- Context
    ip_address INET,
    user_agent VARCHAR(255),
    session_id VARCHAR(255),
    
    -- Actor
    performed_by UUID,
    
    -- Metadata
    metadata JSONB DEFAULT '{}',
    
    -- Timestamp
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_customer_activity_log_customer_id ON customer_activity_log(customer_id);
CREATE INDEX idx_customer_activity_log_type ON customer_activity_log(activity_type);
CREATE INDEX idx_customer_activity_log_created_at ON customer_activity_log(created_at DESC);

-- Enable RLS
ALTER TABLE customer_interactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_activity_log ENABLE ROW LEVEL SECURITY;
"@

    Set-Content -Path (Join-Path $MigrationDir "004-customer-interactions.sql") -Value $Migration004 -Encoding UTF8
    Write-KOSLog "  ✓ Migration 004 créée: customer-interactions" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER MODÈLES TYPESCRIPT
# =============================================================================

function New-CustomersTypeScriptModels {
    Write-KOSLog "Création des modèles TypeScript..." "INFO"

    $TypesDir = Join-Path $Root "packages\crm\src\types"

    # Types Customers
    $CustomerTypes = @"
// ==============================================================================
// KOS CRM - Customer Types
// ==============================================================================

export type CustomerType = 'individual' | 'company' | 'government' | 'ngo';
export type CustomerStatus = 'prospect' | 'onboarding' | 'active' | 'suspended' | 'inactive' | 'archived';
export type KYCStatus = 'not_started' | 'pending' | 'verified' | 'rejected' | 'expired' | 'under_review';
export type AMLStatus = 'not_screened' | 'pending' | 'clean' | 'flagged' | 'blocked' | 'under_review';
export type DocumentType = 'passport' | 'id_card' | 'driving_license' | 'business_registration' | 'tax_id' | 'proof_of_address' | 'bank_statement' | 'incorporation_certificate' | 'articles_of_association' | 'resolution' | 'beneficial_owner_declaration' | 'other';
export type RiskLevel = 'low' | 'medium' | 'high' | 'very_high';

export interface ICustomer {
  id: string;
  customerNumber: string;
  customerType: CustomerType;

  // Individual Details
  firstName?: string;
  lastName?: string;
  dateOfBirth?: Date;
  gender?: string;
  nationality?: string;

  // Company Details
  companyName?: string;
  companyRegistrationNumber?: string;
  companyType?: string;
  businessSector?: string;

  // Contact
  email: string;
  phonePrimary?: string;
  phoneSecondary?: string;

  // Address
  streetAddress?: string;
  city?: string;
  postalCode?: string;
  country?: string;
  stateProvince?: string;

  // Compliance
  kycStatus: KYCStatus;
  kycVerifiedDate?: Date;
  kycExpiresDate?: Date;

  amlStatus: AMLStatus;
  amlScreenedDate?: Date;
  amlExpiresDate?: Date;

  politicallyExposedPerson: boolean;
  riskScore: number; // 0-10
  riskLevel: RiskLevel;

  // Status
  status: CustomerStatus;
  isActive: boolean;

  // Metadata
  tags: string[];
  customFields: Record<string, any>;

  // Audit
  createdAt: Date;
  updatedAt: Date;
  deletedAt?: Date;
}

export interface ICustomerContact {
  id: string;
  customerId: string;
  contactType: 'primary' | 'billing' | 'technical' | 'legal' | 'authorized_signatory';
  firstName: string;
  lastName: string;
  email?: string;
  phone?: string;
  title?: string;
  department?: string;
  isAuthorizedSignatory: boolean;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface IBeneficialOwner {
  id: string;
  customerId: string;
  firstName: string;
  lastName: string;
  dateOfBirth: Date;
  nationality: string;
  ownershipPercentage: number;
  ownershipType: string;
  kycVerified: boolean;
  createdAt: Date;
}

export interface ICustomerDocument {
  id: string;
  customerId: string;
  documentType: DocumentType;
  documentName: string;
  documentNumber?: string;
  fileUrl: string;
  fileName?: string;
  issueDate?: Date;
  expiryDate?: Date;
  isVerified: boolean;
  verifiedAt?: Date;
  createdAt: Date;
}

export interface CreateCustomerDTO {
  customerType: CustomerType;
  firstName?: string;
  lastName?: string;
  dateOfBirth?: Date;
  companyName?: string;
  companyRegistrationNumber?: string;
  email: string;
  phonePrimary?: string;
  streetAddress?: string;
  city?: string;
  country?: string;
}

export interface UpdateCustomerDTO {
  status?: CustomerStatus;
  email?: string;
  phone?: string;
  tags?: string[];
  customFields?: Record<string, any>;
}
"@

    Set-Content -Path (Join-Path $TypesDir "customer.types.ts") -Value $CustomerTypes -Encoding UTF8
    Write-KOSLog "  ✓ Types créés: customer.types.ts" "SUCCESS"

    # Types KYC
    $KYCTypes = @"
// ==============================================================================
// KOS CRM - KYC Types
// ==============================================================================

export type KYCWorkflowType = 'individual' | 'company' | 'enhanced' | 'risk_based';
export type KYCWorkflowStatus = 'pending' | 'in_progress' | 'completed' | 'rejected' | 'expired' | 'cancelled';
export type KYCCheckType = 'identity_verification' | 'address_verification' | 'beneficial_owner_verification' | 'pep_check' | 'sanctions_check' | 'document_verification' | 'video_verification' | 'background_check';
export type KYCCheckStatus = 'pending' | 'in_progress' | 'completed' | 'failed';
export type KYCVerificationMethod = 'manual' | 'automated' | 'video_call' | 'hybrid';

export interface IKYCWorkflow {
  id: string;
  customerId: string;
  workflowCode: string;
  workflowType: KYCWorkflowType;
  status: KYCWorkflowStatus;
  riskLevel: RiskLevel;
  startedAt: Date;
  completedAt?: Date;
  expiresAt?: Date;
  verificationMethod: KYCVerificationMethod;
  overallResult?: string;
  rejectionReason?: string;
  createdAt: Date;
}

export interface IKYCCheck {
  id: string;
  workflowId: string;
  customerId: string;
  checkType: KYCCheckType;
  checkName: string;
  status: KYCCheckStatus;
  result?: 'passed' | 'failed' | 'manual_review_needed';
  hasIssues: boolean;
  issues?: string[];
  startedAt?: Date;
  completedAt?: Date;
  createdAt: Date;
}

export interface KYCWorkflowRequest {
  customerId: string;
  workflowType: KYCWorkflowType;
  riskLevel: RiskLevel;
  verificationMethod?: KYCVerificationMethod;
  urgentProcessing?: boolean;
}

export interface KYCCheckResult {
  checkType: KYCCheckType;
  passed: boolean;
  confidence: number; // 0-100
  message: string;
  details?: Record<string, any>;
}
"@

    Set-Content -Path (Join-Path $TypesDir "kyc.types.ts") -Value $KYCTypes -Encoding UTF8
    Write-KOSLog "  ✓ Types créés: kyc.types.ts" "SUCCESS"

    # Types AML
    $AMLTypes = @"
// ==============================================================================
// KOS CRM - AML Types
// ==============================================================================

export type AMLScreeningType = 'initial' | 'periodic' | 'event_based' | 'transaction_based';
export type SanctionsListType = 'un_sdny' | 'eu_sanctions' | 'uk_sanctions' | 'us_ofac' | 'fatf' | 'local_sanctions' | 'other';

export interface IAMLScreening {
  id: string;
  customerId: string;
  screeningCode: string;
  screeningType: AMLScreeningType;
  status: AMLStatus;
  result: 'clean' | 'flagged' | 'blocked' | 'manual_review';
  hasHits: boolean;
  hitCount: number;
  startedAt: Date;
  completedAt?: Date;
  expiresAt?: Date;
  createdAt: Date;
}

export interface ISanctionsHit {
  id: string;
  screeningId: string;
  customerId: string;
  hitName: string;
  hitMatchScore: number; // 0-100
  sanctionsListType: SanctionsListType;
  entityType: string;
  isResolved: boolean;
  resolutionStatus?: 'false_positive' | 'confirmed' | 'escalated';
  createdAt: Date;
}

export interface IAMLAlert {
  id: string;
  customerId: string;
  alertType: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  title: string;
  description: string;
  status: 'open' | 'in_progress' | 'resolved';
  createdAt: Date;
}

export interface AMLScreeningRequest {
  customerId: string;
  screeningType: AMLScreeningType;
  scope: 'name_only' | 'full_profile' | 'enhanced';
  provider?: string;
}
"@

    Set-Content -Path (Join-Path $TypesDir "aml.types.ts") -Value $AMLTypes -Encoding UTF8
    Write-KOSLog "  ✓ Types créés: aml.types.ts" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER SEED DATA
# =============================================================================

function New-CustomersSeedData {
    Write-KOSLog "Création des données de seed..." "INFO"

    $SeedDir = Join-Path $Root "database\seed\customers"

    # Seed Customers
    $SeedCustomers = @"
-- ==============================================================================
-- KOS Customers Module - Seed Data
-- ==============================================================================

-- Insert test customers
INSERT INTO customers (
    customer_number, customer_type, first_name, last_name, date_of_birth,
    company_name, email, phone_primary, street_address, city, country,
    kyc_status, aml_status, status, risk_level, risk_score, tags
)
VALUES
    -- Individual Customer
    ('CUST-IND-001', 'individual', 'Jean', 'Dupont', '1985-03-15',
     NULL, 'jean.dupont@email.com', '+221781234567', '123 Rue de la Paix', 'Dakar', 'SEN',
     'not_started', 'not_screened', 'prospect', 'low', 2.5, '["individual", "africa"]'::jsonb),

    -- Company Customer
    ('CUST-COM-001', 'company', NULL, NULL, NULL,
     'TECH SOLUTIONS SA', 'contact@techsolutions.sn', '+221338234567', '456 Avenue Clemenceau', 'Dakar', 'SEN',
     'not_started', 'not_screened', 'prospect', 'medium', 4.0, '["company", "tech", "africa"]'::jsonb),

    -- NGO Customer
    ('CUST-NGO-001', 'ngo', 'Marie', 'Sall', '1990-07-22',
     'FONDATION ENVIRONNEMENT', 'marie@fondation-env.org', '+221775890123', '789 Rue Blaise Diagne', 'Dakar', 'SEN',
     'not_started', 'not_screened', 'prospect', 'low', 1.5, '["ngo", "nonprofit", "africa"]'::jsonb);

-- Insert contacts
INSERT INTO customer_contacts (customer_id, contact_type, first_name, last_name, email, phone, title)
SELECT id, 'primary', 'Jean', 'Dupont', 'jean.dupont@email.com', '+221781234567', 'Account Owner'
FROM customers WHERE customer_number = 'CUST-IND-001'
UNION ALL
SELECT id, 'billing', 'Pierre', 'Durand', 'pierre.billing@techsolutions.sn', '+221779876543', 'Finance Manager'
FROM customers WHERE customer_number = 'CUST-COM-001';

-- Insert beneficial owners for company
INSERT INTO beneficial_owners (customer_id, first_name, last_name, date_of_birth, nationality, ownership_percentage, ownership_type)
SELECT id, 'Ahmed', 'Niasse', '1975-11-08', 'SEN', 60.0, 'direct'
FROM customers WHERE customer_number = 'CUST-COM-001'
UNION ALL
SELECT id, 'Fatou', 'Ba', '1980-05-14', 'SEN', 40.0, 'direct'
FROM customers WHERE customer_number = 'CUST-COM-001';
"@

    Set-Content -Path (Join-Path $SeedDir "001-seed-customers.sql") -Value $SeedCustomers -Encoding UTF8
    Write-KOSLog "  ✓ Seed données: customers" "SUCCESS"
}

# =============================================================================
# FONCTION : CRÉER DOCUMENTATION
# =============================================================================

function New-CustomersDocumentation {
    Write-KOSLog "Création de la documentation..." "INFO"

    $DocsDir = Join-Path $Root "docs\crm"
    
    # README Customers
    $ReadmeCustomers = @"
# KOS CRM Module - Customers Management

## Vue d'ensemble

Le module CRM KOS gère l'ensemble du cycle de vie des clients, de la prospect à la relation établie, avec conformité complète KYC/AML.

## Domaines

### 1. **Customers** (Gestion des clients)
- Profils clients (individuels/entreprises/ONG)
- Informations de contact
- Documents d'identification
- Propriétaires bénéficiaires (pour les entreprises)
- Status de conformité

### 2. **KYC** (Know Your Customer)
- Workflows KYC multi-tier (individual/company/enhanced/risk-based)
- Vérifications (identité, adresse, propriétaires bénéficiaires, PEP)
- Audit trail complet
- Gestion des expirations

### 3. **AML** (Anti-Money Laundering)
- Screenings AML périodiques
- Vérification contre listes de sanctions (UN, EU, UK, US OFAC, FATF)
- Détection de PEP (Politically Exposed Persons)
- Monitoring continu

### 4. **Compliance**
- Alertes de conformité
- Suivi des expirations (KYC, AML, documents)
- Risque client (scoring 0-10)
- Monitoring en temps réel

### 5. **Interactions & Activity**
- Historique des interactions (appels, emails, réunions)
- Ticket de support
- Activity log (audit trail)
- Follow-ups

## Architecture

### Base de Données

\`\`\`
customers
├── customer_contacts
├── beneficial_owners
├── customer_documents
├── customer_interactions
└── customer_activity_log

kyc_workflows
├── kyc_checks
└── kyc_audit_trail

aml_screenings
├── sanctions_hits
└── compliance_monitoring
    └── compliance_alerts
\`\`\`

### Types de Clients

- **Individual**: Personne physique
- **Company**: Entreprise / SARL / SA / EIRL
- **Government**: Entité gouvernementale
- **NGO**: Organisation non-gouvernementale

### Status Clients

- **prospect**: Nouveau contact
- **onboarding**: En cours de KYC/AML
- **active**: Complètement vérifié et actif
- **suspended**: Temporairement suspendu
- **inactive**: Non actif mais conservé
- **archived**: Archivé

### Status KYC

- **not_started**: Non initialisé
- **pending**: En attente de documents/vérification
- **verified**: Vérifié avec succès
- **rejected**: Rejeté (raison dans rejection_reason)
- **expired**: KYC expiré, renouvellement nécessaire
- **under_review**: En cours de vérification manuelle

### Status AML

- **not_screened**: Pas encore scanné
- **pending**: En cours de screening
- **clean**: Aucun match détecté
- **flagged**: Match détecté, review en cours
- **blocked**: Client bloqué (sanctions)
- **under_review**: Vérification manuelle

## Workflows

### Onboarding Client Complet

1. **Création du Profil**
   - Informations de base (nom, email, téléphone)
   - Type de client (individual/company)
   - Adresse

2. **Collecte des Documents**
   - Pièce d'identité (passeport, ID card, etc.)
   - Preuve d'adresse
   - Pour les entreprises: actes constitutifs, K-Bis, etc.

3. **Workflow KYC**
   - Verification identité
   - Vérification adresse
   - Pour les entreprises: vérification des propriétaires bénéficiaires
   - Vérification PEP
   - Vérification vidéo (optionnel, pour enhanced KYC)

4. **Screening AML**
   - Screening initial contre listes de sanctions
   - Détection PEP
   - Vérification risques

5. **Décision**
   - Approuver: Status -> 'active'
   - Rejeter: Status -> 'inactive', motif dans rejection_reason
   - Demander infos supplémentaires: Status -> 'pending'

6. **Monitoring Continu**
   - Screenings périodiques (mensuels/trimestriels)
   - Renouvellement KYC (expirations annuelles)
   - Alertes de changement PEP
   - Activity monitoring

### Renouvellement KYC Expirant

```
IF customer.kyc_expires_date < NOW() + 30 DAYS THEN
  - Créer notification
  - Marquer pour renouvellement
  - Initier nouveau workflow KYC
  - Demander documents mis à jour
END IF
```

## Conformité & Régulation

### Régulations Supportées
- ✓ GDPR (Protection des données)
- ✓ CIMA (Conformité bancaire - CEMAC/WAEMU)
- ✓ KYC/AML (Directives FATF)
- ✓ Local regulations (Sénégal, autres pays africains)

### Champs de Conformité
- Nationality & country verification
- PEP detection (Politically Exposed Persons)
- Sanctions screening (UN, EU, UK, US OFAC)
- Risk scoring (0-10, avec auto-escalation)
- Document expiry tracking
- Beneficial owner verification (companies)

## API Endpoints

### Customers
- \`GET /api/crm/customers\` - Lister clients
- \`GET /api/crm/customers/:id\` - Détails client
- \`POST /api/crm/customers\` - Créer client
- \`PUT /api/crm/customers/:id\` - Modifier client
- \`GET /api/crm/customers/:id/documents\` - Documents client

### KYC
- \`POST /api/kyc/workflows\` - Démarrer workflow
- \`GET /api/kyc/workflows/:id\` - Détails workflow
- \`GET /api/kyc/workflows/:id/checks\` - Checks dans workflow
- \`POST /api/kyc/workflows/:id/approve\` - Approuver
- \`POST /api/kyc/workflows/:id/reject\` - Rejeter

### AML
- \`POST /api/aml/screenings\` - Créer screening
- \`GET /api/aml/screenings/:id\` - Détails screening
- \`GET /api/aml/screenings/:id/hits\` - Matches détectés
- \`POST /api/aml/screenings/:id/resolve\` - Résoudre hit

### Compliance
- \`GET /api/compliance/alerts\` - Lister alertes
- \`GET /api/compliance/alerts/customer/:id\` - Alertes par client
- \`PUT /api/compliance/alerts/:id\` - Marquer comme lu

## Données de Base

### Clients Seed
- Jean Dupont (Individuel) - Prospect
- Tech Solutions SA (Entreprise) - Prospect
- Fondation Environnement (ONG) - Prospect

## Prochaines Étapes

1. **MC004-Orders.ps1**: Gestion des commandes
2. **MC005-Payments.ps1**: Intégration paiements
3. **MC006-Invoices.ps1**: Facturation

---

© 2026 KHEPRA EXPERTS
"@

    Set-Content -Path (Join-Path $DocsDir "CUSTOMERS-README.md") -Value $ReadmeCustomers -Encoding UTF8
    Write-KOSLog "  ✓ Documentation créée: CUSTOMERS-README.md" "SUCCESS"
}

# =============================================================================
# FONCTION : GÉNÉRER RAPPORT
# =============================================================================

function Write-CustomersHealthReport {
    Write-KOSLog "Génération du rapport de santé MC003..." "INFO"

    $ReportContent = @"
╔═══════════════════════════════════════════════════════════════════════════╗
║                   MC003 CUSTOMERS MODULE HEALTH REPORT                    ║
║                                v1.0                                        ║
╚═══════════════════════════════════════════════════════════════════════════╝

📋 INFORMATIONS GÉNÉRALES
─────────────────────────────────────────────────────────────────────────────
  Module:           Customers (MC003)
  Version:          1.0.0
  Date:             $Timestamp
  Exécution ID:     $ExecutionId

✅ DÉPENDANCES
─────────────────────────────────────────────────────────────────────────────
  ✓ MC001-Foundation v2.0
  ✓ MC002-Catalog v1.0
  ✓ Structure directoires créée

📦 STRUCTURE CRÉÉE
─────────────────────────────────────────────────────────────────────────────
  Packages CRM:
    ✓ packages/crm/ (main CRM)
    ✓ packages/compliance/kyc/
    ✓ packages/compliance/aml/

  Domaines:
    ✓ packages/crm/src/domains/customers/
    ✓ packages/crm/src/domains/contacts/
    ✓ packages/crm/src/domains/companies/

💾 MIGRATIONS SQL (4 fichiers)
─────────────────────────────────────────────────────────────────────────────
  ✓ 001-customers-base.sql
    └─ Tables: customers, customer_contacts, beneficial_owners, customer_documents
    └─ Enums: customer_type, customer_status, kyc_status, aml_status, document_type
    └─ Indices: customer_number, email, type, status, kyc_status, aml_status
    └─ RLS: Row Level Security configurée
    └─ Audit: Triggers pour timestamp update

  ✓ 002-kyc-workflows.sql
    └─ Tables: kyc_workflows, kyc_checks, kyc_audit_trail
    └─ Types: kyc_workflow_status, kyc_check_type
    └─ Workflow: Individual, Company, Enhanced, Risk-based
    └─ Checks: Identity, Address, Beneficial Owner, PEP, Sanctions, Document, Video

  ✓ 003-aml-compliance.sql
    └─ Tables: aml_screenings, sanctions_hits, compliance_monitoring, compliance_alerts
    └─ Types: aml_screening_type, sanctions_list_type
    └─ Listes: UN SDNY, EU, UK, US OFAC, FATF, Local, Other
    └─ Monitoring: Ongoing, Event-triggered, Periodic

  ✓ 004-customer-interactions.sql
    └─ Tables: customer_interactions, customer_activity_log
    └─ Types: Calls, Emails, Meetings, Support Tickets, Notes
    └─ Activity: Login, Document Upload, KYC Complete, Payment, Support

📝 MODÈLES TYPESCRIPT (3 fichiers)
─────────────────────────────────────────────────────────────────────────────
  ✓ customer.types.ts
    └─ ICustomer, ICustomerContact, IBeneficialOwner, ICustomerDocument
    └─ DTOs: CreateCustomerDTO, UpdateCustomerDTO

  ✓ kyc.types.ts
    └─ IKYCWorkflow, IKYCCheck
    └─ Types: Individual, Company, Enhanced, Risk-based workflows

  ✓ aml.types.ts
    └─ IAMLScreening, ISanctionsHit, IAMLAlert
    └─ Sanctions lists: UN, EU, UK, OFAC, FATF

🌱 DONNÉES DE SEED
─────────────────────────────────────────────────────────────────────────────
  ✓ 001-seed-customers.sql
    ├─ 3 clients de test (Individual, Company, NGO)
    ├─ 2 contacts associés
    └─ 2 propriétaires bénéficiaires

📊 TYPES DE CLIENTS
─────────────────────────────────────────────────────────────────────────────
  ✓ Individual (Personne physique)
    └─ Champs: Prénom, Nom, DOB, Genre, Nationalité
    └─ Workflow KYC: Standard ou Enhanced

  ✓ Company (Entreprise)
    └─ Champs: Nom entreprise, Numéro enregistrement, Type (SARL/SA/EIRL)
    └─ Propriétaires bénéficiaires: 2-N
    └─ Workflow KYC: Enhanced (avec propriétaires)

  ✓ Government (Gouvernement)
    └─ Champs spéciaux pour entités gouvernementales
    └─ Vérifications spéciales

  ✓ NGO (Organisation non-gouvernementale)
    └─ Vérifications allégées
    └─ Tags spéciaux pour reporting ESG

🔄 WORKFLOWS KYC
─────────────────────────────────────────────────────────────────────────────
  ✓ Individual KYC
    └─ Identity Verification
    └─ Address Verification
    └─ PEP Check
    └─ Sanctions Check

  ✓ Company KYC
    └─ Company Registration Verification
    └─ Beneficial Owner Verification (obligatoire)
    └─ Authorized Signatories Verification
    └─ PEP & Sanctions Check

  ✓ Enhanced KYC
    └─ All Individual/Company checks +
    └─ Video Verification
    └─ Background Check
    └─ Source of Funds Verification

  ✓ Risk-Based KYC
    └─ Adaptative based on risk_score
    └─ Low risk: Simplified
    └─ High risk: Enhanced

🔐 WORKFLOWS AML
─────────────────────────────────────────────────────────────────────────────
  ✓ Initial Screening
    └─ Contre all sanctions lists
    └─ At onboarding

  ✓ Periodic Screening
    └─ Mensuel, trimestriel, annuel
    └─ Based on risk_level

  ✓ Event-Based Screening
    └─ On large transactions
    └─ On customer status change
    └─ On alert trigger

  ✓ Transaction-Based Screening
    └─ Real-time monitoring
    └─ Threshold-based alerts

📋 STATUTS CLIENTS
─────────────────────────────────────────────────────────────────────────────
  ✓ prospect → Nouveau contact
  ✓ onboarding → En cours KYC/AML
  ✓ active → Vérifié et actif
  ✓ suspended → Temporairement suspendu
  ✓ inactive → Non actif
  ✓ archived → Archivé

🎯 COMPLIANCE FEATURES
─────────────────────────────────────────────────────────────────────────────
  ✓ PEP Detection
    └─ Automatic flagging
    └─ Country-based risk assessment

  ✓ Sanctions Screening
    └─ UN SDNY
    └─ EU Sanctions
    └─ UK Sanctions
    └─ US OFAC
    └─ FATF Blacklist
    └─ Local Sanctions

  ✓ Risk Scoring (0-10)
    └─ Automatic calculation
    └─ Based on: geography, business, compliance history
    └─ Escalation rules

  ✓ Document Expiry Tracking
    └─ Automatic alerts at 30 days
    └─ KYC renewal workflow triggered

  ✓ Monitoring Continu
    └─ Alertes de changements PEP
    └─ Alertes risques
    └─ Alertes transactions suspectes

⚙️ CONFIGURATION
─────────────────────────────────────────────────────────────────────────────
  ✓ Migrations SQL prêtes (à exécuter)
  ✓ Seed data prête (3 clients de test)
  ✓ Types TypeScript validés
  ✓ Documentation complète
  ✓ RLS policies configurées

🚀 PROCHAINES ÉTAPES
─────────────────────────────────────────────────────────────────────────────
  1. Exécuter les migrations SQL dans Supabase
     \`\`\`sql
     -- Dans Supabase SQL Editor
     -- Exécuter database/migrations/customers/001-*.sql
     \`\`\`

  2. Charger les données de seed
     \`\`\`sql
     -- Exécuter database/seed/customers/001-seed-customers.sql
     \`\`\`

  3. Installer les dépendances npm
     \`\`\`bash
     cd packages/crm
     pnpm install
     \`\`\`

  4. Générer les clients Supabase
     \`\`\`bash
     supabase gen types typescript --project-id <PROJECT_ID> > src/types/database.ts
     \`\`\`

  5. Passer à MC004-Orders.ps1

📊 CLIENT SEED DATA
─────────────────────────────────────────────────────────────────────────────
  1. Jean Dupont (CUST-IND-001)
     Type: Individual
     Email: jean.dupont@email.com
     Location: Dakar, Sénégal
     Status: Prospect
     Risk Level: Low (2.5/10)

  2. TECH SOLUTIONS SA (CUST-COM-001)
     Type: Company
     Email: contact@techsolutions.sn
     Location: Dakar, Sénégal
     Business: Technology
     Beneficial Owners: 2 (Ahmed Niasse 60%, Fatou Ba 40%)
     Status: Prospect
     Risk Level: Medium (4.0/10)

  3. FONDATION ENVIRONNEMENT (CUST-NGO-001)
     Type: NGO
     Email: marie@fondation-env.org
     Contact: Marie Sall
     Location: Dakar, Sénégal
     Status: Prospect
     Risk Level: Low (1.5/10)

📞 SUPPORT & DOCUMENTATION
─────────────────────────────────────────────────────────────────────────────
  Auteur:    KHEPRA EXPERTS
  Email:     contact@khepra-experts.com
  Site:      https://khepra-experts.com
  Repo:      https://github.com/Khepra2026/KOS

📁 FICHIERS GÉNÉRÉS
─────────────────────────────────────────────────────────────────────────────
  Migrations:
    ✓ database/migrations/customers/001-customers-base.sql
    ✓ database/migrations/customers/002-kyc-workflows.sql
    ✓ database/migrations/customers/003-aml-compliance.sql
    ✓ database/migrations/customers/004-customer-interactions.sql

  Seed Data:
    ✓ database/seed/customers/001-seed-customers.sql

  Types TypeScript:
    ✓ packages/crm/src/types/customer.types.ts
    ✓ packages/crm/src/types/kyc.types.ts
    ✓ packages/crm/src/types/aml.types.ts

  Documentation:
    ✓ docs/crm/CUSTOMERS-README.md

✨ FEATURES CLÉS
─────────────────────────────────────────────────────────────────────────────
  ✓ Multi-channel interactions (calls, emails, meetings, support)
  ✓ Complete audit trail (qui, quand, quoi, pourquoi)
  ✓ Risk-based workflows (adaptative KYC based on risk)
  ✓ Beneficial owner management (for companies)
  ✓ Document management & verification
  ✓ PEP & sanctions screening
  ✓ Compliance monitoring & alerts
  ✓ Activity logging (security audit trail)
  ✓ Communication preferences (email, SMS, phone)
  ✓ Parent-child relationships (subsidiaries)

╔═══════════════════════════════════════════════════════════════════════════╗
║           ✓ MC003 Customers Module Initialization Complete!              ║
║      Ready for KYC/AML workflows and customer onboarding processes        ║
╚═══════════════════════════════════════════════════════════════════════════╝

"@

    $ReportPath = Join-Path $LogDir "MC003-health-report.txt"
    Set-Content -Path $ReportPath -Value $ReportContent -Encoding UTF8
    
    Write-Host $ReportContent
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

try {
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  KOS CUSTOMERS MODULE v1.0" -ForegroundColor Cyan
    Write-Host "  Master Code: MC003 | KHEPRA EXPERTS" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    Write-KOSLog "Démarrage du module Clients..." "INFO"

    # 1. Vérifier dépendances
    Test-PreviousModules

    # 2. Créer structure
    New-CustomersStructure

    # 3. Créer migrations
    New-CustomersMigrations

    # 4. Créer types TypeScript
    New-CustomersTypeScriptModels

    # 5. Créer seed data
    New-CustomersSeedData

    # 6. Créer documentation
    New-CustomersDocumentation

    # 7. Rapport de santé
    Write-CustomersHealthReport

    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ MC003 INITIALIZATION COMPLETE" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-KOSLog "Module Clients initialisé avec succès" "SUCCESS"
    Write-Host ""
}
catch {
    Write-KOSLog "Erreur: $($_.Exception.Message)" "ERROR"
    Write-KOSLog "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  ✗ MC003 INITIALIZATION FAILED" -ForegroundColor Red
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    exit 1
}
