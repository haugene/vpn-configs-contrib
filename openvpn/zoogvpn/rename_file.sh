#!/bin/bash

FILE=$1

# some file are not in unix format
dos2unix "${FILE}"

SERVER=$(grep "remote " "${FILE}" | awk '{ print $2 }');
PROTO=$(grep "proto " "${FILE}" | awk '{ print $2 }');

mv "${FILE}" "${SERVER}.${PROTO}.ovpn"
