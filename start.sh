#!/bin/sh
# upterm host --accept bash
echo "Install g4f depencies"
pip install -U g4f[all]
echo "Run g4f api"
python3 -m g4f.api.run
