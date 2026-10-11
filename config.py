# config.py
# Loads all configuration from the .env file.
# Flask and other modules import from here so only one place needs changing.

import os
from dotenv import load_dotenv

load_dotenv()  # reads .env file in the project root

DB_HOST     = os.getenv("DB_HOST",     "localhost")
DB_PORT     = int(os.getenv("DB_PORT", "3306"))
DB_USER     = os.getenv("DB_USER",     "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_NAME     = os.getenv("DB_NAME",     "carnet_import")
SECRET_KEY  = os.getenv("SECRET_KEY",  "change_me")
