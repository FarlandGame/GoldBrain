# GoldBrain Security Notes

## Already implemented

- Provider/AI secrets stay server-side.
- Passwords use Argon2id; plaintext passwords are never stored.
- JWT access tokens are short-lived.
- Refresh tokens are rotated and stored only as hashes.
- Sessions/devices can be listed and revoked.
- Password reset tokens are random, hashed, expiring and single-use.
- User Paper Trading accounts are scoped to their authenticated user.
- Data-ingestion and backtest/evaluation mutation endpoints remain owner/private-only.
- Basic private-beta rate limiting and audit logs exist.
- Production settings require non-default JWT and private secrets.

## Before public launch

- Put the API behind HTTPS/reverse proxy/WAF.
- Replace process-local rate limiting with Redis/shared limiting.
- Add production email/SMS verification and a complete MFA flow.
- Use OS secure storage in Flutter for refresh tokens.
- Add centralized logs/metrics/alerts and encrypted backups.
- Run dependency scanning, SAST, penetration testing and threat modeling.
- Never enable withdrawal permission on future exchange API keys.
- Complete legal/security review before enabling any real-money adapter.

## Important

`mfa_secret_encrypted` exists only as a schema hook. No MFA secret is generated or stored by the current code.
Real exchange credentials are not stored and real-money execution is disabled.
