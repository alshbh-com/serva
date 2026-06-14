
DO $$
DECLARE
  v_owner_id UUID;
BEGIN
  SELECT user_id INTO v_owner_id FROM public.user_roles WHERE role = 'owner' LIMIT 1;

  IF v_owner_id IS NOT NULL THEN
    UPDATE auth.users
    SET email = '01278006248@alqarsh.ship',
        encrypted_password = extensions.crypt('01278006248', extensions.gen_salt('bf')),
        email_confirmed_at = COALESCE(email_confirmed_at, now()),
        updated_at = now()
    WHERE id = v_owner_id;

    UPDATE public.profiles
    SET login_code = '01278006248', full_name = COALESCE(NULLIF(full_name,''), 'المالك')
    WHERE id = v_owner_id;
  END IF;
END $$;
