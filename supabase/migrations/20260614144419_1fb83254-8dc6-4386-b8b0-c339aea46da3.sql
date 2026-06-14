
-- Create the owner user with bcrypt-hashed password
-- One-time bootstrap; if the user exists, do nothing.
DO $$
DECLARE
  v_user_id UUID;
  v_email TEXT := '01278006248@serva.ship';
  v_password TEXT := '01278006248';
BEGIN
  SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;

  IF v_user_id IS NULL THEN
    v_user_id := gen_random_uuid();
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, email_change,
      email_change_token_new, recovery_token
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      v_user_id, 'authenticated', 'authenticated',
      v_email, crypt(v_password, gen_salt('bf')),
      now(),
      jsonb_build_object('provider','email','providers',jsonb_build_array('email')),
      jsonb_build_object('full_name','المالك'),
      now(), now(), '', '', '', ''
    );
    INSERT INTO auth.identities (
      id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_user_id, v_user_id,
      jsonb_build_object('sub', v_user_id::text, 'email', v_email),
      'email', now(), now(), now()
    );
  END IF;

  -- Ensure profile + owner role
  INSERT INTO public.profiles (id, full_name, login_code)
  VALUES (v_user_id, 'المالك', v_password)
  ON CONFLICT (id) DO UPDATE SET full_name = 'المالك', login_code = v_password;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (v_user_id, 'owner')
  ON CONFLICT (user_id, role) DO NOTHING;
END $$;
