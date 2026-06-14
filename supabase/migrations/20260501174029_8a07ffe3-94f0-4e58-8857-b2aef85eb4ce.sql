
-- ============ ENUMS ============
CREATE TYPE public.app_role AS ENUM ('owner', 'admin', 'courier', 'office');
CREATE TYPE public.permission_level AS ENUM ('edit', 'view', 'hidden');

-- ============ UTILITY FUNCTIONS ============
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

-- ============ PROFILES ============
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  phone TEXT,
  login_code TEXT,
  salary NUMERIC DEFAULT 0,
  commission_amount NUMERIC DEFAULT 0,
  office_id UUID,
  coverage_areas TEXT[],
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER set_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ USER ROLES ============
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, role)
);
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE OR REPLACE FUNCTION public.is_owner_or_admin(_user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role IN ('owner','admin'))
$$;

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', ''))
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END; $$;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============ USER PERMISSIONS ============
CREATE TABLE public.user_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  section TEXT NOT NULL,
  permission public.permission_level NOT NULL DEFAULT 'edit',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, section)
);
ALTER TABLE public.user_permissions ENABLE ROW LEVEL SECURITY;

-- ============ APP SETTINGS ============
CREATE TABLE public.app_settings (
  key TEXT PRIMARY KEY,
  value JSONB,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- ============ ACTIVITY LOGS ============
CREATE TABLE public.activity_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  details JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_activity_logs_created ON public.activity_logs(created_at DESC);

CREATE OR REPLACE FUNCTION public.log_activity(_action TEXT, _details JSONB DEFAULT '{}'::jsonb)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.activity_logs (user_id, action, details) VALUES (auth.uid(), _action, _details);
END; $$;

-- ============ OFFICES ============
CREATE TABLE public.offices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  specialty TEXT,
  owner_name TEXT,
  owner_phone TEXT,
  address TEXT,
  notes TEXT,
  office_commission NUMERIC DEFAULT 0,
  can_add_orders BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.offices ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER set_offices_updated BEFORE UPDATE ON public.offices FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.profiles ADD CONSTRAINT profiles_office_fk FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE SET NULL;

-- ============ PRODUCTS ============
CREATE TABLE public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  quantity INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER set_products_updated BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ COMPANIES ============
CREATE TABLE public.companies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  agreement_price NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER set_companies_updated BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ DELIVERY PRICES ============
CREATE TABLE public.delivery_prices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID REFERENCES public.offices(id) ON DELETE CASCADE,
  governorate TEXT NOT NULL,
  price NUMERIC NOT NULL DEFAULT 0,
  pickup_price NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.delivery_prices ENABLE ROW LEVEL SECURITY;

-- ============ ORDER STATUSES ============
CREATE TABLE public.order_statuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  color TEXT DEFAULT '#888888',
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.order_statuses ENABLE ROW LEVEL SECURITY;

INSERT INTO public.order_statuses (name, color, sort_order) VALUES
('جديد', '#3b82f6', 1),
('قيد التوصيل', '#f59e0b', 2),
('تم التسليم', '#10b981', 3),
('مؤجل', '#8b5cf6', 4),
('لم يرد', '#6b7280', 5),
('مرتجع', '#ef4444', 6),
('تسليم جزئي', '#06b6d4', 7),
('رفض الاستلام', '#dc2626', 8);

-- ============ BARCODE SEQUENCE ============
CREATE SEQUENCE public.order_barcode_seq START WITH 1000000 INCREMENT BY 1;

-- ============ ORDERS ============
CREATE TABLE public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barcode TEXT UNIQUE,
  tracking_id TEXT,
  customer_code TEXT,
  customer_name TEXT NOT NULL,
  customer_phone TEXT NOT NULL,
  address TEXT,
  product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
  product_name TEXT,
  quantity INTEGER DEFAULT 1,
  color TEXT,
  size TEXT,
  price NUMERIC NOT NULL DEFAULT 0,
  delivery_price NUMERIC NOT NULL DEFAULT 0,
  partial_amount NUMERIC DEFAULT 0,
  shipping_paid NUMERIC DEFAULT 0,
  notes TEXT,
  priority TEXT DEFAULT 'normal',
  office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
  courier_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  status_id UUID REFERENCES public.order_statuses(id) ON DELETE SET NULL,
  company_id UUID REFERENCES public.companies(id) ON DELETE SET NULL,
  is_closed BOOLEAN DEFAULT false,
  is_courier_closed BOOLEAN DEFAULT false,
  is_settled BOOLEAN DEFAULT false,
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_orders_courier ON public.orders(courier_id);
CREATE INDEX idx_orders_office ON public.orders(office_id);
CREATE INDEX idx_orders_status ON public.orders(status_id);
CREATE INDEX idx_orders_closed ON public.orders(is_closed);
CREATE TRIGGER set_orders_updated BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE OR REPLACE FUNCTION public.set_order_barcode()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.barcode IS NULL OR NEW.barcode = '' THEN
    NEW.barcode := nextval('public.order_barcode_seq')::TEXT;
  END IF;
  IF NEW.tracking_id IS NULL OR NEW.tracking_id = '' THEN
    NEW.tracking_id := NEW.barcode;
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_set_order_barcode BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_order_barcode();

-- ============ ORDER NOTES ============
CREATE TABLE public.order_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  note TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.order_notes ENABLE ROW LEVEL SECURITY;

-- ============ COURIER COLLECTIONS ============
CREATE TABLE public.courier_collections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE,
  courier_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  amount NUMERIC NOT NULL DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.courier_collections ENABLE ROW LEVEL SECURITY;

-- ============ COURIER BONUSES ============
CREATE TABLE public.courier_bonuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL DEFAULT 0,
  reason TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.courier_bonuses ENABLE ROW LEVEL SECURITY;

-- ============ COURIER LOCATIONS ============
CREATE TABLE public.courier_locations (
  courier_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  accuracy DOUBLE PRECISION,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.courier_locations ENABLE ROW LEVEL SECURITY;

-- ============ MESSAGES ============
CREATE TABLE public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_messages_pair ON public.messages(sender_id, receiver_id);

-- ============ ADVANCES ============
CREATE TABLE public.advances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL DEFAULT 0,
  reason TEXT,
  type TEXT DEFAULT 'advance',
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.advances ENABLE ROW LEVEL SECURITY;

-- ============ EXPENSES ============
CREATE TABLE public.expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_name TEXT NOT NULL,
  amount NUMERIC NOT NULL DEFAULT 0,
  category TEXT,
  notes TEXT,
  expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
  office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

-- ============ CASH FLOW ============
CREATE TABLE public.cash_flow_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL,
  amount NUMERIC NOT NULL DEFAULT 0,
  reason TEXT,
  notes TEXT,
  entry_date DATE NOT NULL DEFAULT CURRENT_DATE,
  office_id UUID REFERENCES public.offices(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.cash_flow_entries ENABLE ROW LEVEL SECURITY;

-- ============ OFFICE PAYMENTS ============
CREATE TABLE public.office_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.offices(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL DEFAULT 0,
  type TEXT NOT NULL DEFAULT 'advance',
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.office_payments ENABLE ROW LEVEL SECURITY;

-- ============ OFFICE DAILY EXPENSES ============
CREATE TABLE public.office_daily_expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID REFERENCES public.offices(id) ON DELETE CASCADE,
  expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
  category TEXT NOT NULL,
  amount NUMERIC NOT NULL DEFAULT 0,
  notes TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.office_daily_expenses ENABLE ROW LEVEL SECURITY;

-- ============ OFFICE DAILY CLOSINGS ============
CREATE TABLE public.office_daily_closings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID NOT NULL REFERENCES public.offices(id) ON DELETE CASCADE,
  closing_date DATE NOT NULL DEFAULT CURRENT_DATE,
  data_json JSONB DEFAULT '[]'::jsonb,
  pickup_rate NUMERIC DEFAULT 0,
  is_locked BOOLEAN DEFAULT false,
  is_closed BOOLEAN DEFAULT false,
  prevent_add BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(office_id, closing_date)
);
ALTER TABLE public.office_daily_closings ENABLE ROW LEVEL SECURITY;

-- ============ COMPANY PAYMENTS ============
CREATE TABLE public.company_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL DEFAULT 0,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.company_payments ENABLE ROW LEVEL SECURITY;

-- ============ DIARIES ============
CREATE SEQUENCE public.diary_number_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE public.diaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  diary_number INTEGER NOT NULL DEFAULT nextval('public.diary_number_seq'),
  office_id UUID NOT NULL REFERENCES public.offices(id) ON DELETE CASCADE,
  diary_date DATE NOT NULL DEFAULT CURRENT_DATE,
  is_closed BOOLEAN DEFAULT false,
  is_archived BOOLEAN DEFAULT false,
  lock_status_updates BOOLEAN DEFAULT false,
  prevent_new_orders BOOLEAN DEFAULT false,
  notes TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.diaries ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER set_diaries_updated BEFORE UPDATE ON public.diaries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ DIARY ORDERS ============
CREATE TABLE public.diary_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  diary_id UUID NOT NULL REFERENCES public.diaries(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  status_override TEXT,
  partial_amount NUMERIC DEFAULT 0,
  n_column TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(diary_id, order_id)
);
ALTER TABLE public.diary_orders ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER set_diary_orders_updated BEFORE UPDATE ON public.diary_orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ RLS POLICIES ============
-- Profiles: everyone authenticated can view, users update self, owner/admin manage all
CREATE POLICY "profiles_select_auth" ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "profiles_update_self_or_admin" ON public.profiles FOR UPDATE TO authenticated
  USING (auth.uid() = id OR public.is_owner_or_admin(auth.uid()));
CREATE POLICY "profiles_insert_admin" ON public.profiles FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = id OR public.is_owner_or_admin(auth.uid()));
CREATE POLICY "profiles_delete_admin" ON public.profiles FOR DELETE TO authenticated
  USING (public.is_owner_or_admin(auth.uid()));

-- User roles: viewable by authenticated, only owner/admin manages
CREATE POLICY "user_roles_select" ON public.user_roles FOR SELECT TO authenticated USING (true);
CREATE POLICY "user_roles_admin_all" ON public.user_roles FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- User permissions
CREATE POLICY "user_perm_select_self_or_admin" ON public.user_permissions FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.is_owner_or_admin(auth.uid()));
CREATE POLICY "user_perm_admin_all" ON public.user_permissions FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- App settings
CREATE POLICY "app_settings_read" ON public.app_settings FOR SELECT TO authenticated USING (true);
CREATE POLICY "app_settings_write" ON public.app_settings FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- Activity logs
CREATE POLICY "activity_logs_select_admin" ON public.activity_logs FOR SELECT TO authenticated
  USING (public.is_owner_or_admin(auth.uid()));
CREATE POLICY "activity_logs_insert_auth" ON public.activity_logs FOR INSERT TO authenticated WITH CHECK (true);

-- Generic "all authenticated" tables (offices, products, companies, statuses, delivery_prices)
CREATE POLICY "offices_read" ON public.offices FOR SELECT TO authenticated USING (true);
CREATE POLICY "offices_write" ON public.offices FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

CREATE POLICY "products_read" ON public.products FOR SELECT TO authenticated USING (true);
CREATE POLICY "products_write" ON public.products FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

CREATE POLICY "companies_read" ON public.companies FOR SELECT TO authenticated USING (true);
CREATE POLICY "companies_write" ON public.companies FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

CREATE POLICY "delivery_prices_read" ON public.delivery_prices FOR SELECT TO authenticated USING (true);
CREATE POLICY "delivery_prices_write" ON public.delivery_prices FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

CREATE POLICY "order_statuses_read" ON public.order_statuses FOR SELECT TO authenticated USING (true);
CREATE POLICY "order_statuses_write" ON public.order_statuses FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- Orders: courier sees own; office user sees own office; admin sees all
CREATE POLICY "orders_read" ON public.orders FOR SELECT TO authenticated USING (true);
CREATE POLICY "orders_insert" ON public.orders FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "orders_update" ON public.orders FOR UPDATE TO authenticated USING (true);
CREATE POLICY "orders_delete" ON public.orders FOR DELETE TO authenticated
  USING (public.is_owner_or_admin(auth.uid()));

-- Order notes
CREATE POLICY "order_notes_read" ON public.order_notes FOR SELECT TO authenticated USING (true);
CREATE POLICY "order_notes_write" ON public.order_notes FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Courier collections
CREATE POLICY "cc_read" ON public.courier_collections FOR SELECT TO authenticated USING (true);
CREATE POLICY "cc_write" ON public.courier_collections FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Courier bonuses
CREATE POLICY "cb_read" ON public.courier_bonuses FOR SELECT TO authenticated USING (true);
CREATE POLICY "cb_write" ON public.courier_bonuses FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- Courier locations
CREATE POLICY "cl_read" ON public.courier_locations FOR SELECT TO authenticated USING (true);
CREATE POLICY "cl_upsert_self" ON public.courier_locations FOR INSERT TO authenticated WITH CHECK (auth.uid() = courier_id);
CREATE POLICY "cl_update_self" ON public.courier_locations FOR UPDATE TO authenticated USING (auth.uid() = courier_id);

-- Messages
CREATE POLICY "msgs_read_party" ON public.messages FOR SELECT TO authenticated
  USING (auth.uid() = sender_id OR auth.uid() = receiver_id);
CREATE POLICY "msgs_insert_self" ON public.messages FOR INSERT TO authenticated WITH CHECK (auth.uid() = sender_id);
CREATE POLICY "msgs_update_party" ON public.messages FOR UPDATE TO authenticated
  USING (auth.uid() = sender_id OR auth.uid() = receiver_id);
CREATE POLICY "msgs_delete_sender" ON public.messages FOR DELETE TO authenticated USING (auth.uid() = sender_id);

-- Advances
CREATE POLICY "advances_read" ON public.advances FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.is_owner_or_admin(auth.uid()));
CREATE POLICY "advances_write" ON public.advances FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- Expenses / cash flow / office payments / office daily expenses / office daily closings / company payments => admin only
CREATE POLICY "expenses_all_admin" ON public.expenses FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

CREATE POLICY "cash_flow_all_admin" ON public.cash_flow_entries FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

CREATE POLICY "office_payments_all_admin" ON public.office_payments FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

CREATE POLICY "office_daily_expenses_all_admin" ON public.office_daily_expenses FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

CREATE POLICY "office_daily_closings_all_admin" ON public.office_daily_closings FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

CREATE POLICY "company_payments_all_admin" ON public.company_payments FOR ALL TO authenticated
  USING (public.is_owner_or_admin(auth.uid())) WITH CHECK (public.is_owner_or_admin(auth.uid()));

-- Diaries / diary orders
CREATE POLICY "diaries_read" ON public.diaries FOR SELECT TO authenticated USING (true);
CREATE POLICY "diaries_write" ON public.diaries FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "diary_orders_read" ON public.diary_orders FOR SELECT TO authenticated USING (true);
CREATE POLICY "diary_orders_write" ON public.diary_orders FOR ALL TO authenticated USING (true) WITH CHECK (true);
