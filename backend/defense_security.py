"""Boundary checks shared by the retained HTML and supported JSON APIs."""
import base64
import binascii
import io
import warnings

from PIL import Image, UnidentifiedImageError


def validate_profile_photo(value):
    if value is None or value == '':
        return value
    if not isinstance(value, str) or len(value) > 2_800_000:
        raise ValueError('Use a JPEG or PNG photo no larger than 2 MB.')
    header, sep, encoded = value.partition(',')
    formats = {'data:image/png;base64': 'PNG', 'data:image/jpeg;base64': 'JPEG'}
    if not sep or header not in formats:
        raise ValueError('Use a base64-encoded JPEG or PNG photo.')
    try:
        raw = base64.b64decode(encoded, validate=True)
        if not raw or len(raw) > 2 * 1024 * 1024:
            raise ValueError('Photo exceeds the 2 MB limit.')
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(raw)) as img:
                if img.format != formats[header]:
                    raise ValueError('Photo content does not match its image type.')
                if not (1 <= img.width <= 4096 and 1 <= img.height <= 4096):
                    raise ValueError('Photo dimensions must be at most 4096 by 4096 pixels.')
                img.verify()
            with Image.open(io.BytesIO(raw)) as img:
                img.load()  # verify compressed pixels can actually be decoded
    except (binascii.Error, UnidentifiedImageError, OSError, Image.DecompressionBombError,
            Image.DecompressionBombWarning) as exc:
        raise ValueError('Photo is not a valid JPEG or PNG image.') from exc
    return value
