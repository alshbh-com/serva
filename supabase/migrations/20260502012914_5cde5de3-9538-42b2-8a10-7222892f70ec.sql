
UPDATE auth.users
SET email = REPLACE(email, '@alqarsh.ship', '@serva.ship')
WHERE email LIKE '%@alqarsh.ship';
