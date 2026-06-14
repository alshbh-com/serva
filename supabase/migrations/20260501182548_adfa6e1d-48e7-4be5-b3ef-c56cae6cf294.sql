
DO $$
DECLARE
  v_id UUID;
BEGIN
  FOR v_id IN SELECT user_id FROM public.user_roles WHERE role = 'owner' LOOP
    DELETE FROM public.user_roles WHERE user_id = v_id;
    DELETE FROM public.profiles WHERE id = v_id;
    DELETE FROM auth.users WHERE id = v_id;
  END LOOP;
END $$;
