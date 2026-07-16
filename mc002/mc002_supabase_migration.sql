-- Migration MC002 : Schéma Supabase pour KOS Monetization Engine
-- Remarques :
--  - Utilise gen_random_uuid() (pgcrypto). Sur certaines installations, utilisez uuid_generate_v4() si vous préférez.
--  - Inclut timestamps, soft delete (deleted_at), audit_logs, triggers updated_at et audit.
--  - RLS : exemples fournis plus bas ; activer RLS séparément après insertion des données de seed si souhaité.

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Table: organizations
CREATE TABLE IF NOT EXISTS organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  legal_name text,
  rccm text,
  nif text,
  vat_number text,
  currency text DEFAULT 'XOF', -- valeur par défaut FCFA (XOF)
  country text,
  timezone text DEFAULT 'Africa/Abidjan',
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_organizations_name ON organizations (lower(name));
CREATE INDEX IF NOT EXISTS idx_organizations_deleted_at ON organizations (deleted_at);

-- Table: roles
CREATE TABLE IF NOT EXISTS roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL, -- ex: SUPER_ADMIN, ADMIN, CUSTOMER_ADMIN, USER, EXPERT...
  name text NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Table: profiles (lié à auth.users)
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY, -- doit correspondre à auth.users.id
  organization_id uuid REFERENCES organizations(id) ON DELETE SET NULL,
  email text,
  full_name text,
  phone text,
  locale text DEFAULT 'fr',
  role_id uuid REFERENCES roles(id),
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_profiles_org ON profiles (organization_id);

-- Table: services (catalogue de catégories / moteurs)
CREATE TABLE IF NOT EXISTS services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  key text NOT NULL, -- ex: AML_ENGINE, ESG_ENGINE
  name text NOT NULL,
  description text,
  tags text[],
  public boolean DEFAULT false,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_services_org ON services (organization_id);

-- Table: products (produits numériques vendables)
CREATE TABLE IF NOT EXISTS products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  service_id uuid REFERENCES services(id),
  sku text,
  name text NOT NULL,
  description text,
  product_type text NOT NULL, -- 'digital', 'one_time', 'subscription', 'credit_pack'
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_products_org ON products (organization_id);

-- Table: pricing_plans
CREATE TABLE IF NOT EXISTS pricing_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id),
  name text NOT NULL,
  billing_period text NOT NULL, -- 'monthly', 'yearly'
  price_cents bigint NOT NULL DEFAULT 0, -- stocker en centimes (FCFA centimes si applicable)
  currency text DEFAULT 'XOF',
  seats integer DEFAULT 1, -- nombre d'utilisateurs inclus
  limits jsonb DEFAULT '{}'::jsonb, -- ex: {"credits_per_month":1000, "requests_per_min":60}
  active boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_pricing_plans_org ON pricing_plans (organization_id);

-- Table: subscriptions
CREATE TABLE IF NOT EXISTS subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  pricing_plan_id uuid REFERENCES pricing_plans(id),
  started_at timestamptz NOT NULL DEFAULT now(),
  current_period_start timestamptz,
  current_period_end timestamptz,
  status text NOT NULL DEFAULT 'active', -- 'active', 'trialing', 'past_due', 'canceled', 'expired'
  seats integer DEFAULT 1,
  metadata jsonb DEFAULT '{}'::jsonb,
  cancel_at_period_end boolean DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_subscriptions_org ON subscriptions (organization_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions (status);

-- Table: payments (attempts / records)
CREATE TABLE IF NOT EXISTS payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES organizations(id) ON DELETE SET NULL,
  subscription_id uuid REFERENCES subscriptions(id) ON DELETE SET NULL,
  amount_cents bigint NOT NULL,
  currency text DEFAULT 'XOF',
  provider text, -- 'PayDunya', 'FedaPay', 'CinetPay', 'MobileMoney', 'Stripe', etc.
  provider_payment_id text,
  method jsonb DEFAULT '{}'::jsonb, -- details (mobile money phone, card brand, last4, etc.)
  status text NOT NULL DEFAULT 'created', -- 'created','pending','succeeded','failed','refunded'
  attempts integer DEFAULT 0,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_payments_org ON payments (organization_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments (status);

-- Table: invoices
CREATE TABLE IF NOT EXISTS invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  subscription_id uuid REFERENCES subscriptions(id),
  invoice_number text UNIQUE,
  issue_date date DEFAULT CURRENT_DATE,
  due_date date,
  amount_cents bigint NOT NULL,
  currency text DEFAULT 'XOF',
  status text DEFAULT 'draft', -- 'draft','issued','paid','void','refunded'
  pdf_url text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_invoices_org ON invoices (organization_id);

-- Table: licenses
CREATE TABLE IF NOT EXISTS licenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  license_key text UNIQUE NOT NULL,
  product_id uuid REFERENCES products(id),
  issued_to text,
  seats integer DEFAULT 1,
  valid_from timestamptz DEFAULT now(),
  valid_until timestamptz,
  status text DEFAULT 'active', -- 'active','revoked','expired'
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_licenses_org ON licenses (organization_id);

-- Table: documents (métadonnées fichiers ; stockage via Supabase Storage)
CREATE TABLE IF NOT EXISTS documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  uploaded_by uuid REFERENCES profiles(id),
  path text NOT NULL, -- chemin dans Supabase Storage
  file_name text,
  mime_type text,
  size_bytes bigint,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_documents_org ON documents (organization_id);

-- Table: crm_contacts
CREATE TABLE IF NOT EXISTS crm_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  account_id uuid, -- entreprise cliente (peut référencer organizations.id ou contacts externes)
  first_name text,
  last_name text,
  email text,
  phone text,
  role text,
  owner_profile_id uuid REFERENCES profiles(id), -- responsable interne
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_crm_contacts_org ON crm_contacts (organization_id);
CREATE INDEX IF NOT EXISTS idx_crm_contacts_email ON crm_contacts (lower(email));

-- Table: usage_tracking (pay-per-use / crédits)
CREATE TABLE IF NOT EXISTS usage_tracking (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  profile_id uuid REFERENCES profiles(id),
  service_id uuid REFERENCES services(id),
  feature text, -- ex: "report_generation", "ocr_page"
  quantity numeric DEFAULT 1,
  unit text,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_usage_org ON usage_tracking (organization_id);
CREATE INDEX IF NOT EXISTS idx_usage_service ON usage_tracking (service_id);

-- Table: transactions (grand livre / journal financier simple)
CREATE TABLE IF NOT EXISTS transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  related_payment_id uuid REFERENCES payments(id),
  related_invoice_id uuid REFERENCES invoices(id),
  kind text NOT NULL, -- 'payment','refund','chargeback','credit'
  amount_cents bigint NOT NULL,
  currency text DEFAULT 'XOF',
  recorded_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_transactions_org ON transactions (organization_id);

-- Table: audit_logs (centralisé)
CREATE TABLE IF NOT EXISTS audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name text NOT NULL,
  record_id uuid, -- id de la ligne affectée
  operation text NOT NULL, -- 'INSERT','UPDATE','DELETE'
  performed_by uuid, -- profile id (auth.uid())
  performed_at timestamptz NOT NULL DEFAULT now(),
  old_data jsonb,
  new_data jsonb,
  diff jsonb,
  metadata jsonb DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_audit_table ON audit_logs (table_name);
CREATE INDEX IF NOT EXISTS idx_audit_performed_by ON audit_logs (performed_by);

-- Trigger utility: set updated_at on update
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Attach set_updated_at trigger to tables that have updated_at
DO $$
DECLARE
  tbl text;
  tables text[] := ARRAY[
    'organizations','profiles','services','products','pricing_plans',
    'subscriptions','payments','invoices','licenses','documents',
    'crm_contacts','usage_tracking','transactions'
  ];
BEGIN
  FOREACH tbl IN ARRAY tables LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_set_updated_at ON %I;', tbl);
    EXECUTE format('CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();', tbl);
  END LOOP;
END;
$$;

-- Audit trigger function (générique) : enregistre OLD/NEW
CREATE OR REPLACE FUNCTION public.audit_if_needed()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  old_json jsonb;
  new_json jsonb;
  performed uuid := NULL;
BEGIN
  -- éviter audit sur la table audit_logs elle-même
  IF TG_TABLE_NAME = 'audit_logs' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    old_json := to_jsonb(OLD);
    INSERT INTO audit_logs(table_name, record_id, operation, performed_by, performed_at, old_data, new_data)
    VALUES (TG_TABLE_NAME, OLD.id::uuid, TG_OP, NULL, now(), old_json, NULL);
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' THEN
    old_json := to_jsonb(OLD);
    new_json := to_jsonb(NEW);
    INSERT INTO audit_logs(table_name, record_id, operation, performed_by, performed_at, old_data, new_data, diff)
    VALUES (TG_TABLE_NAME, NEW.id::uuid, TG_OP, NULL, now(), old_json, new_json, jsonb_strip_nulls(new_json - old_json));
    RETURN NEW;
  ELSIF TG_OP = 'INSERT' THEN
    new_json := to_jsonb(NEW);
    INSERT INTO audit_logs(table_name, record_id, operation, performed_by, performed_at, old_data, new_data)
    VALUES (TG_TABLE_NAME, NEW.id::uuid, TG_OP, NULL, now(), NULL, new_json);
    RETURN NEW;
  END IF;
  RETURN NULL;
END;
$$;

-- Attacher audit trigger aux tables clés
DO $$
DECLARE
  tbl text;
  tables text[] := ARRAY[
    'organizations','profiles','services','products','pricing_plans',
    'subscriptions','payments','invoices','licenses','documents',
    'crm_contacts','usage_tracking','transactions'
  ];
BEGIN
  FOREACH tbl IN ARRAY tables LOOP
    -- remove existing to be idempotent
    EXECUTE format('DROP TRIGGER IF EXISTS trg_audit ON %I;', tbl);
    EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION public.audit_if_needed();', tbl);
  END LOOP;
END;
$$;

-- Seed roles (idempotent)
INSERT INTO roles (id, key, name, description, created_at)
SELECT gen_random_uuid(), v.key, v.name, v.description, now()
FROM (VALUES
  ('SUPER_ADMIN','Super admin','Accès complet, configuration globale'),
  ('ADMIN','Admin','Administrateur organisation'),
  ('CUSTOMER_ADMIN','Customer admin','Admin client, gestion abonnements'),
  ('USER','User','Utilisateur standard'),
  ('EXPERT','Expert','Conseiller / Expert'),
  ('PARTNER','Partner','Partenaire'),
  ('ACCOUNTING','Accounting','Accès comptabilité'),
  ('SUPPORT','Support','Support client')
) AS v(key, name, description)
ON CONFLICT (key) DO NOTHING;

-- Exemples de RLS policies (à activer manuellement en production)
-- Note : ici on illustre l'approche "profiles" : profiles.id = auth.uid() et profiles.organization_id détermine l'appartenance.
-- Activer RLS pour chaque table avec : ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;

-- Exemple : policy pour services (organisation)
-- ALTER TABLE services ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "Org members can select services" ON services
--   FOR SELECT USING (organization_id IN (SELECT organization_id FROM profiles WHERE id = auth.uid()));

-- Exemple : profile peut SELECT son propre profil
-- ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "Profiles own self" ON profiles
--   FOR ALL USING (id = auth.uid());

-- Exemple : Admins (role-based) peuvent tout faire — suppose role_id de profiles pointe vers roles
-- CREATE POLICY "Org admins full" ON subscriptions
--   FOR ALL USING (
--     EXISTS (
--       SELECT 1 FROM profiles p JOIN roles r ON p.role_id = r.id
--       WHERE p.id = auth.uid() AND p.organization_id = subscriptions.organization_id AND r.key IN ('SUPER_ADMIN','ADMIN','CUSTOMER_ADMIN')
--     )
--   );

-- Important : Ajoutez, testez et affinez les policies RLS après vos premiers seeds.

-- Partial index example : favoriser les lignes actives (non supprimées)
CREATE INDEX IF NOT EXISTS idx_products_org_active ON products (organization_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_services_org_active ON services (organization_id) WHERE deleted_at IS NULL;

-- GIN indexes for JSONB metadata
CREATE INDEX IF NOT EXISTS idx_products_metadata_gin ON products USING gin (metadata);
CREATE INDEX IF NOT EXISTS idx_pricing_metadata_gin ON pricing_plans USING gin (limits);

-- Fin de migration
