#!/bin/sh -e
ngrok config add-authtoken $NGROK_AUTH
ngrok tcp 22
