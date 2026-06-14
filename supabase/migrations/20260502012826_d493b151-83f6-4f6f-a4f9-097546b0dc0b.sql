
-- Reset barcode sequence to start from 1
ALTER SEQUENCE public.orders_barcode_seq RESTART WITH 1;

-- Update app name setting
UPDATE public.app_settings SET value = '"TikExpress"'::jsonb WHERE key = 'app_name';
