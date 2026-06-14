
-- ============================================================
-- ENUMS
-- ============================================================
CREATE TYPE public.app_role AS ENUM ('owner', 'admin', 'courier', 'office');
CREATE TYPE public.priority_level AS ENUM ('normal', 'urgent', 'vip');
CREATE TYPE public.permission_level AS ENUM ('view', 'edit', 'hidden');

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

-- ============================================================
-- PROFILES
-- ============================================================
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY,
  full_name TEXT,
  phone TEXT,
  login_code TEXT,
  salary NUMERIC DEFAULT 0,
  commission_amount NUMERIC DEFAULT 0,
  office_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Auto-create profile on auth signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', ''))
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- USER ROLES
-- ============================================================
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, role)
);
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE OR REPLACE FUNCTION public.is_owner_or_admin(_user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role IN ('owner','admin'));
$$;

CREATE OR REPLACE FUNCTION public.is_courier(_user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = 'courier');
$$;

CREATE OR REPLACE FUNCTION public.user_office_id(_user_id UUID)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT office_id FROM public.profiles WHERE id = _user_id;
$$;

-- profiles policies (after helpers)
CREATE POLICY "profiles_select_own_or_admin" ON public.profiles FOR SELECT
  USING (auth.uid() = id OR public.is_owner_or_admin(auth.uid()));
CREATE POLICY "profiles_update_own_or_admin" ON public.profiles FOR UPDATE
  USING (auth.uid() = id OR public.is_owner_or_admin(auth.uid()));
CREATE POLICY "profiles_insert_admin" ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id OR public.is_owner_or_admin(auth.uid()));

-- user_roles policies
CREATE POLICY "user_roles_select_self_or_admin" ON public.user_roles FOR SELECT
  USING (auth.uid() = user_id OR public.is_owner_or_admin(auth.uid()));
CREATE POLICY "user_roles_admin_all" ON public.user_roles FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- ============================================================
-- USER PERMISSIONS
-- ============================================================
CREATE TABLE public.user_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  section TEXT NOT NULL,
  permission permission_level NOT NULL DEFAULT 'edit',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, section)
);
ALTER TABLE public.user_permissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "perm_select_self_or_admin" ON public.user_permissions FOR SELECT
  USING (auth.uid() = user_id OR public.is_owner_or_admin(auth.uid()));
CREATE POLICY "perm_admin_all" ON public.user_permissions FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- ============================================================
-- APP SETTINGS
-- ============================================================
CREATE TABLE public.app_settings (
  key TEXT PRIMARY KEY,
  value JSONB,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "settings_read_authenticated" ON public.app_settings FOR SELECT
  TO authenticated USING (true);
CREATE POLICY "settings_admin_write" ON public.app_settings FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- ============================================================
-- OFFICES
-- ============================================================
CREATE TABLE public.offices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  phone TEXT,
  address TEXT,
  governorate TEXT,
  can_add_orders BOOLEAN NOT NULL DEFAULT true,
  commission_rate NUMERIC NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.offices ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_offices_updated BEFORE UPDATE ON public.offices
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE POLICY "offices_read_auth" ON public.offices FOR SELECT TO authenticated USING (true);
CREATE POLICY "offices_admin_write" ON public.offices FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- profiles.office_id FK (now that offices exists)
ALTER TABLE public.profiles ADD CONSTRAINT profiles_office_fk
  FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE SET NULL;

-- ============================================================
-- COMPANIES
-- ============================================================
CREATE TABLE public.companies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  phone TEXT,
  address TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_companies_updated BEFORE UPDATE ON public.companies
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE POLICY "companies_read_auth" ON public.companies FOR SELECT TO authenticated USING (true);
CREATE POLICY "companies_admin_write" ON public.companies FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- ============================================================
-- PRODUCTS
-- ============================================================
CREATE TABLE public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 0,
  price NUMERIC NOT NULL DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_products_updated BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE POLICY "products_read_auth" ON public.products FOR SELECT TO authenticated USING (true);
CREATE POLICY "products_admin_write" ON public.products FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- ============================================================
-- DELIVERY PRICES
-- ============================================================
CREATE TABLE public.delivery_prices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID REFERENCES public.offices(id) ON DELETE CASCADE,
  governorate TEXT NOT NULL,
  price NUMERIC NOT NULL DEFAULT 0,
  pickup_price NUMERIC NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(office_id, governorate)
);
ALTER TABLE public.delivery_prices ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_dp_updated BEFORE UPDATE ON public.delivery_prices
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE POLICY "dp_read_auth" ON public.delivery_prices FOR SELECT TO authenticated USING (true);
CREATE POLICY "dp_admin_write" ON public.delivery_prices FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- ============================================================
-- ORDER STATUSES
-- ============================================================
CREATE TABLE public.order_statuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  color TEXT NOT NULL DEFAULT '#6b7280',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.order_statuses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "statuses_read_auth" ON public.order_statuses FOR SELECT TO authenticated USING (true);
CREATE POLICY "statuses_admin_write" ON public.order_statuses FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- ============================================================
-- ORDERS (with auto barcode trigger)
-- ============================================================
CREATE SEQUENCE public.orders_barcode_seq START 100000;

CREATE TABLE public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barcode TEXT NOT NULL UNIQUE,
  customer_name TEXT NOT NULL,
  customer_phone TEXT NOT NULL,
  customer_phone2 TEXT,
  customer_code TEXT,
  address TEXT,
  governorate TEXT,
  product_name TEXT,
  product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
  color TEXT,
  size TEXT,
  quantity INTEGER NOT NULL DEFAULT 1,
  price NUMERIC NOT NULL DEFAULT 0,
  delivery_price NUMERIC NOT NULL DEFAULT 0,
  notes TEXT,
  priority priority_level NOT NULL DEFAULT 'normal',
  status_id UUID REFERENCES public.order_statuses(id) ON DELETE SET NULL,
  office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
  courier_id UUID,
  courier_name TEXT,
  company_id UUID REFERENCES public.companies(id) ON DELETE SET NULL,
  is_closed BOOLEAN NOT NULL DEFAULT false,
  is_courier_closed BOOLEAN NOT NULL DEFAULT false,
  is_settled BOOLEAN NOT NULL DEFAULT false,
  shipping_amount NUMERIC,
  partial_amount NUMERIC,
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_orders_office ON public.orders(office_id);
CREATE INDEX idx_orders_courier ON public.orders(courier_id);
CREATE INDEX idx_orders_status ON public.orders(status_id);
CREATE INDEX idx_orders_closed ON public.orders(is_closed);
CREATE TRIGGER trg_orders_updated BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE OR REPLACE FUNCTION public.generate_barcode()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.barcode IS NULL OR NEW.barcode = '' THEN
    NEW.barcode := nextval('public.orders_barcode_seq')::TEXT;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_orders_barcode BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.generate_barcode();

CREATE POLICY "orders_select_admin" ON public.orders FOR SELECT
  USING (public.is_owner_or_admin(auth.uid()));
CREATE POLICY "orders_select_courier" ON public.orders FOR SELECT
  USING (courier_id = auth.uid());
CREATE POLICY "orders_select_office" ON public.orders FOR SELECT
  USING (office_id = public.user_office_id(auth.uid()));
CREATE POLICY "orders_admin_write" ON public.orders FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));
CREATE POLICY "orders_courier_update" ON public.orders FOR UPDATE
  USING (courier_id = auth.uid()) WITH CHECK (courier_id = auth.uid());
CREATE POLICY "orders_office_insert" ON public.orders FOR INSERT
  WITH CHECK (office_id = public.user_office_id(auth.uid()));

-- ============================================================
-- ORDER NOTES
-- ============================================================
CREATE TABLE public.order_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id UUID,
  note TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.order_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notes_read_auth" ON public.order_notes FOR SELECT TO authenticated USING (true);
CREATE POLICY "notes_insert_auth" ON public.order_notes FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "notes_admin_modify" ON public.order_notes FOR DELETE
  USING (public.is_owner_or_admin(auth.uid()));

-- ============================================================
-- COURIER COLLECTIONS
-- ============================================================
CREATE TABLE public.courier_collections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id UUID NOT NULL,
  order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.courier_collections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cc_admin_all" ON public.courier_collections FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));
CREATE POLICY "cc_courier_self" ON public.courier_collections FOR ALL
  USING (courier_id = auth.uid()) WITH CHECK (courier_id = auth.uid());

-- ============================================================
-- COURIER BONUSES
-- ============================================================
CREATE TABLE public.courier_bonuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id UUID NOT NULL,
  amount NUMERIC NOT NULL,
  reason TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.courier_bonuses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cb_admin_all" ON public.courier_bonuses FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));
CREATE POLICY "cb_courier_read" ON public.courier_bonuses FOR SELECT
  USING (courier_id = auth.uid());

-- ============================================================
-- OFFICE PAYMENTS
-- ============================================================
CREATE TABLE public.office_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.offices(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL,
  type TEXT NOT NULL DEFAULT 'advance',
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.office_payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "op_admin_all" ON public.office_payments FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));
CREATE POLICY "op_office_read" ON public.office_payments FOR SELECT
  USING (office_id = public.user_office_id(auth.uid()));

-- ============================================================
-- COMPANY PAYMENTS
-- ============================================================
CREATE TABLE public.company_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.company_payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cp_admin_all" ON public.company_payments FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- ============================================================
-- OFFICE DAILY EXPENSES
-- ============================================================
CREATE TABLE public.office_daily_expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.offices(id) ON DELETE CASCADE,
  expense_date DATE NOT NULL,
  category TEXT,
  amount NUMERIC NOT NULL,
  notes TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.office_daily_expenses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ode_admin_all" ON public.office_daily_expenses FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));
CREATE POLICY "ode_office_read" ON public.office_daily_expenses FOR SELECT
  USING (office_id = public.user_office_id(auth.uid()));

-- ============================================================
-- OFFICE DAILY CLOSINGS (settlement)
-- ============================================================
CREATE TABLE public.office_daily_closings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.offices(id) ON DELETE CASCADE,
  closing_date DATE NOT NULL,
  data_json JSONB,
  pickup_rate NUMERIC NOT NULL DEFAULT 0,
  is_locked BOOLEAN NOT NULL DEFAULT false,
  is_closed BOOLEAN NOT NULL DEFAULT false,
  prevent_add BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(office_id, closing_date)
);
ALTER TABLE public.office_daily_closings ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_odc_updated BEFORE UPDATE ON public.office_daily_closings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE POLICY "odc_admin_all" ON public.office_daily_closings FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));
CREATE POLICY "odc_office_read" ON public.office_daily_closings FOR SELECT
  USING (office_id = public.user_office_id(auth.uid()));

-- ============================================================
-- ADVANCES (سلفات وخصومات)
-- ============================================================
CREATE TABLE public.advances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  amount NUMERIC NOT NULL,
  reason TEXT,
  type TEXT NOT NULL DEFAULT 'advance',
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.advances ENABLE ROW LEVEL SECURITY;
CREATE POLICY "adv_admin_all" ON public.advances FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));
CREATE POLICY "adv_self_read" ON public.advances FOR SELECT
  USING (user_id = auth.uid());

-- ============================================================
-- EXPENSES (general)
-- ============================================================
CREATE TABLE public.expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_name TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  category TEXT,
  notes TEXT,
  expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
  office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "exp_admin_all" ON public.expenses FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- ============================================================
-- CASH FLOW ENTRIES
-- ============================================================
CREATE TABLE public.cash_flow_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  reason TEXT,
  notes TEXT,
  entry_date DATE NOT NULL DEFAULT CURRENT_DATE,
  office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.cash_flow_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cf_admin_all" ON public.cash_flow_entries FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- ============================================================
-- DIARIES
-- ============================================================
CREATE TABLE public.diaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.offices(id) ON DELETE CASCADE,
  diary_date DATE NOT NULL,
  is_closed BOOLEAN NOT NULL DEFAULT false,
  lock_status_updates BOOLEAN NOT NULL DEFAULT false,
  prevent_new_orders BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.diaries ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_diaries_updated BEFORE UPDATE ON public.diaries
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE POLICY "diaries_read_auth" ON public.diaries FOR SELECT TO authenticated USING (true);
CREATE POLICY "diaries_admin_write" ON public.diaries FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

CREATE TABLE public.diary_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  diary_id UUID NOT NULL REFERENCES public.diaries(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  diary_status_id UUID REFERENCES public.order_statuses(id) ON DELETE SET NULL,
  diary_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(diary_id, order_id)
);
ALTER TABLE public.diary_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "do_read_auth" ON public.diary_orders FOR SELECT TO authenticated USING (true);
CREATE POLICY "do_admin_write" ON public.diary_orders FOR ALL
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- ============================================================
-- MESSAGES (internal chat)
-- ============================================================
CREATE TABLE public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL,
  receiver_id UUID NOT NULL,
  message TEXT NOT NULL,
  is_read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_messages_pair ON public.messages(sender_id, receiver_id);
CREATE POLICY "msg_select_participants" ON public.messages FOR SELECT
  USING (sender_id = auth.uid() OR receiver_id = auth.uid() OR public.is_owner_or_admin(auth.uid()));
CREATE POLICY "msg_insert_self" ON public.messages FOR INSERT
  WITH CHECK (sender_id = auth.uid());
CREATE POLICY "msg_update_receiver" ON public.messages FOR UPDATE
  USING (receiver_id = auth.uid() OR sender_id = auth.uid());

-- ============================================================
-- ACTIVITY LOGS
-- ============================================================
CREATE TABLE public.activity_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  action TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_logs_created ON public.activity_logs(created_at DESC);
CREATE POLICY "logs_admin_read" ON public.activity_logs FOR SELECT
  USING (public.is_owner_or_admin(auth.uid()));
CREATE POLICY "logs_self_insert" ON public.activity_logs FOR INSERT
  TO authenticated WITH CHECK (true);

-- log_activity RPC
CREATE OR REPLACE FUNCTION public.log_activity(_action TEXT, _details JSONB DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.activity_logs (user_id, action, details)
  VALUES (auth.uid(), _action, _details);
END;
$$;

-- ============================================================
-- SEED DATA
-- ============================================================
-- Order statuses
INSERT INTO public.order_statuses (name, color, sort_order) VALUES
  ('جديد', '#3b82f6', 1),
  ('قيد التوصيل', '#f59e0b', 2),
  ('تم التوصيل', '#10b981', 3),
  ('مرتجع', '#ef4444', 4),
  ('مؤجل', '#8b5cf6', 5),
  ('رفض ودفع شحن', '#f97316', 6),
  ('تسليم جزئي', '#06b6d4', 7),
  ('استلم ودفع نص الشحن', '#0ea5e9', 8);

-- 27 Egyptian governorates as delivery price templates (no office_id yet — admin can edit per office later)
INSERT INTO public.delivery_prices (governorate, price, pickup_price) VALUES
  ('القاهرة', 0, 0),
  ('الجيزة', 0, 0),
  ('الإسكندرية', 0, 0),
  ('القليوبية', 0, 0),
  ('الشرقية', 0, 0),
  ('الدقهلية', 0, 0),
  ('البحيرة', 0, 0),
  ('المنوفية', 0, 0),
  ('الغربية', 0, 0),
  ('كفر الشيخ', 0, 0),
  ('دمياط', 0, 0),
  ('بورسعيد', 0, 0),
  ('الإسماعيلية', 0, 0),
  ('السويس', 0, 0),
  ('شمال سيناء', 0, 0),
  ('جنوب سيناء', 0, 0),
  ('الفيوم', 0, 0),
  ('بني سويف', 0, 0),
  ('المنيا', 0, 0),
  ('أسيوط', 0, 0),
  ('سوهاج', 0, 0),
  ('قنا', 0, 0),
  ('الأقصر', 0, 0),
  ('أسوان', 0, 0),
  ('البحر الأحمر', 0, 0),
  ('الوادي الجديد', 0, 0),
  ('مطروح', 0, 0);

-- Default app settings
INSERT INTO public.app_settings (key, value) VALUES
  ('app_name', '"القرش"'::jsonb),
  ('accounting_password', '""'::jsonb);
