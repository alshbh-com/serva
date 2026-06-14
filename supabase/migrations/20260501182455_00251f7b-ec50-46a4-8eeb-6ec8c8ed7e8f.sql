
DO $$
DECLARE
  v_owner_id UUID;
  v_new_email TEXT := '01278006248@alqarsh.ship';
  v_new_password TEXT := '01278006248';
BEGIN
  -- Find the first owner
  SELECT user_id INTO v_owner_id FROM public.user_roles WHERE role = 'owner' LIMIT 1;

  IF v_owner_id IS NOT NULL THEN
    -- Update auth.users: email + encrypted password
    UPDATE auth.users
    SET email = v_new_email,
        encrypted_password = crypt(v_new_password, gen_salt('bf')),
        email_confirmed_at = COALESCE(email_confirmed_at, now()),
        updated_at = now()
    WHERE id = v_owner_id;

    -- Update profile login_code
    UPDATE public.profiles
    SET login_code = v_new_password, full_name = COALESCE(NULLIF(full_name,''), 'المالك')
    WHERE id = v_owner_id;
  END IF;
END $$;
