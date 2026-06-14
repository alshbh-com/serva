
-- Orders: add missing columns
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS partial_amount NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_settled BOOLEAN NOT NULL DEFAULT false;

-- Convert shipping_paid from boolean to numeric (amount collected)
ALTER TABLE public.orders DROP COLUMN IF EXISTS shipping_paid;
ALTER TABLE public.orders ADD COLUMN shipping_paid NUMERIC NOT NULL DEFAULT 0;

-- Profiles: add salary/commission for couriers/staff
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS salary NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS commission_amount NUMERIC DEFAULT 0;

-- log_activity RPC used by activityLogger
CREATE OR REPLACE FUNCTION public.log_activity(_action TEXT, _details JSONB DEFAULT '{}'::jsonb)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE _id UUID;
BEGIN
  INSERT INTO public.activity_logs (user_id, action, details)
  VALUES (auth.uid(), _action, _details)
  RETURNING id INTO _id;
  RETURN _id;
END; $$;

GRANT EXECUTE ON FUNCTION public.log_activity(TEXT, JSONB) TO authenticated;

-- Fix search_path on existing functions (security lint)
ALTER FUNCTION public.set_order_barcode() SET search_path = public;
ALTER FUNCTION public.touch_updated_at() SET search_path = public;
