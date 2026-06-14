
INSERT INTO offices (name, owner_name, owner_phone, address, office_commission) VALUES
  ('مكتب القاهرة', 'أحمد محمد', '01000000001', 'وسط البلد', 5),
  ('مكتب الجيزة', 'محمود علي', '01000000002', 'الدقي', 5),
  ('مكتب الإسكندرية', 'كريم سعيد', '01000000003', 'سيدي جابر', 7);

INSERT INTO products (name, quantity) VALUES
  ('تيشيرت', 100), ('بنطلون', 50), ('حذاء', 30);

INSERT INTO delivery_prices (governorate, price, pickup_price) VALUES
  ('القاهرة', 50, 10), ('الجيزة', 50, 10), ('الإسكندرية', 80, 15), ('الدقهلية', 70, 12);

INSERT INTO companies (name, agreement_price) VALUES ('شركة الاختبار', 100);

-- 5 test orders (barcode auto via trigger from sequence starting at 1)
INSERT INTO orders (customer_name, customer_phone, address, product_name, quantity, price, delivery_price, office_id, priority)
SELECT 'عميل ' || g, '0100000010' || g, 'القاهرة - شارع ' || g, 'تيشيرت', 1, 200 + g*10, 50, (SELECT id FROM offices ORDER BY name LIMIT 1), 'normal'
FROM generate_series(1,5) g;
