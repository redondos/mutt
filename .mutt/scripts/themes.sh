#!/bin/bash

echo ~/.mutt/themes/default
exit

if [[ $TERM =~ 256 ]]; then
	echo ~/.mutt/themes.256
else
	echo ~/.mutt/themes.default
fi
