"""Password policy for new credentials; existing bcrypt hashes remain valid."""
import bcrypt


def validate_new_password(value: str) -> str:
    if len(value) < 15:
        raise ValueError('Use at least 15 characters, preferably a unique passphrase.')
    if len(value.encode('utf-8')) > 72:
        raise ValueError('Password must be at most 72 UTF-8 bytes.')
    if len(set(value)) < 4 or value.casefold() in {
        'password123456789', '123456789012345', 'qwertyuiopasdfgh',
        'geosustain123456', 'passwordpassword',
    }:
        raise ValueError('Choose a less predictable password.')
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
