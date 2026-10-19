"""Password policy for new credentials; existing bcrypt hashes remain valid."""
import string
import bcrypt


def validate_new_password(value: str) -> str:
    if len(value) != 8 or any(c.isspace() for c in value):
        raise ValueError('Password must be exactly 8 characters with no spaces.')
    if not any(c in string.punctuation for c in value):
        raise ValueError('Password must include at least one special character (for example !, @, #).')
    return value


_DUMMY_HASH = bcrypt.hashpw(b'dummy-password-not-an-account', bcrypt.gensalt(rounds=12))


def verify_password(password: str, password_hash: str) -> bool:
    try:
        encoded = password.encode('utf-8')
        if len(encoded) > 72:
            return False
        stored = password_hash.encode('utf-8') if password_hash else _DUMMY_HASH
        valid = bcrypt.checkpw(encoded, stored)
        return bool(password_hash) and valid
    except (ValueError, TypeError, AttributeError):
        return False
