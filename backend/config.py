"""Load local configuration without overriding deployment environment values."""
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / '.env', override=False)
