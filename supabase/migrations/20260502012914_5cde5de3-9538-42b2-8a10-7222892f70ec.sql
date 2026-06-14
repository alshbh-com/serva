
UPDATE auth.users
SET email = REPLACE(email, '@alqarsh.ship', '@tikexpress.ship')
WHERE email LIKE '%@alqarsh.ship';
