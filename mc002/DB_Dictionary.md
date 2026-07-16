# Dictionnaire de la base de données — KOS Monetization Engine (MC002)

Ce document décrit les tables principales du schéma Supabase fourni.

## organisations
- id (uuid) : PK
- name : nom commercial
- legal_name : raison sociale
- rccm, nif, vat_number : informations fiscales/registre OHADA
- currency : devise par défaut (ex: XOF)
- timezone : fuseau horaire
- metadata (jsonb) : informations libres (adresse, secteurs, contacts)
- created_at, updated_at, deleted_at

Usage : comptes entreprises multi-tenant.

## roles
- id, key, name, description, created_at

Usage : liste des rôles applicatifs (SUPER_ADMIN, ADMIN, ...).

## profiles
- id : correspond à auth.users.id (supabase auth)
- organization_id : organisation associée (multi-tenant)
- email, full_name, phone, locale
- role_id : FK vers roles
- metadata, created_at, updated_at, deleted_at

Usage : mapping utilisateur <-> organisation + rôle.

## services
- id, organization_id, key, name, description, tags, public, metadata
- created_at, updated_at, deleted_at

Usage : composants métiers / moteurs (ex: AML_ENGINE, ESG_ENGINE). Déployés par organisation.

## products
- id, organization_id, service_id, sku, name, description, product_type, metadata
- product_type : 'digital', 'one_time', 'subscription', 'credit_pack'

Usage : ce qui est vendu sur la marketplace (diagnostics, rapports, packs crédits).

## pricing_plans
- id, organization_id, product_id, name, billing_period (monthly/yearly)
- price_cents, currency, seats, limits (jsonb), active, created_at, updated_at

Usage : plans tarifaires liés aux produits.

## subscriptions
- id, organization_id, pricing_plan_id, started_at, current_period_start/end
- status (active/trialing/past_due/canceled/expired)
- seats, cancel_at_period_end, metadata, timestamps

Usage : gestion abonnement organisation.

## payments
- id, organization_id, subscription_id, amount_cents, currency
- provider, provider_payment_id, method (jsonb), status, attempts, metadata
- timestamps

Usage : enregistrements des tentatives paiements et statut.

## invoices
- id, organization_id, subscription_id, invoice_number, issue_date, due_date
- amount_cents, currency, status, pdf_url, metadata, timestamps

Usage : facturation (OHADA fields à étendre depuis metadata).

## licenses
- id, organization_id, license_key, product_id, issued_to, seats
- valid_from, valid_until, status, metadata, timestamps

Usage : licences par produit/organisation.

## documents
- id, organization_id, uploaded_by, path (Supabase Storage), file_name, mime_type, size_bytes, metadata, timestamps

Usage : stocker métadonnées des livrables (rapports Word/Excel, contrats, etc.)

## crm_contacts
- id, organization_id, account_id, first_name, last_name, email, phone, role, owner_profile_id, metadata, timestamps

Usage : CRM et pipeline (Lead → Prospect → Client).

## usage_tracking
- id, organization_id, profile_id, service_id, feature, quantity, unit, recorded_at, metadata

Usage : suivi consommation pay-per-use (crédits IA, OCR pages, etc.)

## transactions
- id, organization_id, related_payment_id, related_invoice_id, kind, amount_cents, currency, recorded_at, metadata

Usage : grand livre / journal financier pour audits (OHADA).

## audit_logs
- id, table_name, record_id, operation, performed_by, performed_at, old_data, new_data, diff, metadata

Usage : piste d’audit centralisée (obligatoire pour conformité ISO / Big Four).

---

Règles et recommandations
- UUIDs : gen_random_uuid() (pgcrypto)
- Timestamps : timestamptz, created_at DEFAULT now(), triggers pour updated_at
- Soft delete : deleted_at plutôt que suppression physique
- Index : indexer organization_id et colonnes recherchées (email, invoice_number...)
- JSONB : GIN index pour metadata et limits
- RLS : activer Row Level Security et appliquer policies basées sur profiles.organization_id et roles
  - Approche recommandée : garder un mapping profiles.id = auth.users.id; utiliser policies qui comparent organization_id de la table avec profiles.organization_id WHERE profiles.id = auth.uid()
- Audit : audit_logs et trigger generique pour INSERT/UPDATE/DELETE (enregistrer old/new/diff)
- Sécurité : restreindre l’accès direct aux tables sensibles (transactions, payments) ; seuls les rôles compta/admin doivent y avoir accès en lecture/écriture via policies.
- Tokens / claims : si vous émettez des JWT custom contenant organization_id ou role, vous pouvez simplifier certaines policies en lisant ces claims. Sinon, utilisez la table profiles.

---

Prochaines étapes proposées (à choisir) :
1. Activer RLS et ajouter policies adaptées (je peux générer les policies SQL complètes).
2. Adapter la colonne `price_cents`/`currency` aux exigences locales (FCFA / decimal).
3. Générer les Supabase Edge Functions pour : webhooks paiement, activation licence, consommation crédits (usage), facturation automatique.
4. Préparer migrations Terraform + CI/CD GitHub Actions + scripts PowerShell MC001–MC010.

Dites-moi quelle(s) action(s) vous voulez que je fasse ensuite : générer les policies RLS complètes, produire les Edge Functions (handlers webhooks), ou préparer les fichiers à pousser sur le dépôt (je peux le faire si vous confirmez l’écriture sur Khepra2026/KOS et la branche).  
