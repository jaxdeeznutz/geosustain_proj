# GeoSustain Agent Instructions

## Project Overview

GeoSustain is an AI-driven geospatial decision-support system for agricultural land analysis in Panabo City.

## Technology Stack

- Flutter and Dart
- FastAPI and Python
- PostgreSQL / Supabase
- Google Earth Engine
- OpenWeather
- Open-Meteo
- NASA POWER

## Important Project Files

- lib/ - Flutter application
- backend/fastapi_app.py - active FastAPI backend
- backend/database.py - database operations
- backend/rainfallDatasets.py - environmental data and model processing
- backend/training/ - machine-learning files
- backend/tests/ - backend tests
- test/ - Flutter tests

## Development Rules

- Work on the Sub-branch-demo branch.
- Do not commit private API keys or passwords.
- Do not commit backend/.env.
- Use backend/fastapi_app.py as the current backend entry point.
- Preserve the existing GeoSustain workflow.
- Avoid unnecessary changes to the trained model and datasets.
- Test changes before committing them.