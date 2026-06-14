
-- ============================================================
-- ORDERS: barcode nullable + shipping_paid
-- ============================================================
ALTER TABLE public.orders ALTER COLUMN barcode DROP NOT NULL;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS shipping_paid BOOLEAN NOT NULL DEFAULT false;

-- ============================================================
-- OFFICES: extra fields
-- ============================================================
ALTER TABLE public.offices
  ADD COLUMN IF NOT EXISTS specialty TEXT,
  ADD COLUMN IF NOT EXISTS owner_name TEXT,
  ADD COLUMN IF NOT EXISTS owner_phone TEXT,
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS office_commission NUMERIC NOT NULL DEFAULT 0;

-- ============================================================
-- COMPANIES: agreement_price
-- ============================================================
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS agreement_price NUMERIC NOT NULL DEFAULT 0;

-- ============================================================
-- DIARIES: diary_number (auto-incrementing per office) + is_archived
-- ============================================================
ALTER TABLE public.diaries
  ADD COLUMN IF NOT EXISTS diary_number INTEGER,
  ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.set_diary_number()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.diary_number IS NULL THEN
    SELECT COALESCE(MAX(diary_number), 0) + 1
    INTO NEW.diary_number
    FROM public.diaries
    WHERE office_id = NEW.office_id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_diaries_number ON public.diaries;
CREATE TRIGGER trg_diaries_number BEFORE INSERT ON public.diaries
  FOR EACH ROW EXECUTE FUNCTION public.set_diary_number();

-- ============================================================
-- DIARY_ORDERS: n_column (manual text excluded from calculations)
-- ============================================================
ALTER TABLE public.diary_orders
  ADD COLUMN IF NOT EXISTS n_column TEXT;

-- ============================================================
-- COURIER_COLLECTIONS: status fields for partial / shipping
-- ============================================================
ALTER TABLE public.courier_collections
  ADD COLUMN IF NOT EXISTS collection_status TEXT,
  ADD COLUMN IF NOT EXISTS partial_amount NUMERIC,
  ADD COLUMN IF NOT EXISTS notes TEXT;

-- ============================================================
-- Lock down SECURITY DEFINER helpers (revoke from public/anon)
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_owner_or_admin(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_courier(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.user_office_id(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.log_activity(text, jsonb) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_owner_or_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_courier(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_office_id(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_activity(text, jsonb) TO authenticated;
