
ALTER TABLE public.orders DROP COLUMN shipping_paid;
ALTER TABLE public.orders ADD COLUMN shipping_paid NUMERIC NOT NULL DEFAULT 0;
