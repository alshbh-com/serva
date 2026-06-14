
-- Delete all owner roles first
DELETE FROM public.user_roles WHERE role = 'owner';

-- Now delete the orphaned auth users that have no role at all
-- (these were owners that just got deleted)
DELETE FROM auth.users
WHERE id NOT IN (SELECT user_id FROM public.user_roles WHERE user_id IS NOT NULL)
  AND email LIKE '%@alqarsh.ship';

-- Clean up orphaned profiles too
DELETE FROM public.profiles
WHERE id NOT IN (SELECT id FROM auth.users);
