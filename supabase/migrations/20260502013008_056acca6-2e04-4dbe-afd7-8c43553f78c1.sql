
-- Sample office
INSERT INTO public.offices (name, owner_name, phone, governorate, address, commission_rate, office_commission)
VALUES ('TikExpress Cairo HQ', 'TiK EXPRESS', '01131030574', 'القاهرة', 'وسط البلد', 5, 10)
RETURNING id;

-- Two sample orders
INSERT INTO public.orders (customer_name, customer_phone, governorate, address, product_name, quantity, price, delivery_price, office_id)
SELECT 'عميل تجريبي 1', '01000000001', 'القاهرة', 'مدينة نصر - شارع 9', 'منتج تجريبي', 1, 250, 60, id
FROM public.offices WHERE name = 'TikExpress Cairo HQ' LIMIT 1;

INSERT INTO public.orders (customer_name, customer_phone, governorate, address, product_name, quantity, price, delivery_price, office_id)
SELECT 'عميل تجريبي 2', '01000000002', 'الجيزة', 'الدقي - شارع التحرير', 'منتج آخر', 2, 500, 70, id
FROM public.offices WHERE name = 'TikExpress Cairo HQ' LIMIT 1;
