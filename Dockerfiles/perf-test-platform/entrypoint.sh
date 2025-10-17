#!/bin/bash

cd ${HOME}/app/; python3 -m uvicorn main:app --host 0.0.0.0 --port 8000 --workers 4 --reload