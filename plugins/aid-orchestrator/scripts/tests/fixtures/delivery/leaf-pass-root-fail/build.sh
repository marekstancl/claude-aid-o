#!/usr/bin/env bash
# build.sh — leaf packages succeed, root fails (DG-02 fail fixture)
echo "Building leaf packages... ok"
echo "Building root package..."
echo "ERROR: root build failed — missing dependency at root level"
exit 1
