#!/bin/bash
if type t-prot &>/dev/null; then
	echo "set display_filter=\"t-prot $@\""
else
	echo "set"
fi
