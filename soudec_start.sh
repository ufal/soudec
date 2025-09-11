#!/bin/bash

# Set UTF-8 locale to ensure proper character encoding
export LANG=cs_CZ.UTF-8
export LC_ALL=cs_CZ.UTF-8

echo "Searching for sources" > err

# Run the command and capture JSON output
json_output=$(echo "Tvrdí se, že ano. Říká, že ne." | \
./system/soudec.pl --stdin --ll 0 --output-format txt --experimental=gen,perspron --output-statistics=tsv 2>>err)

# Extract and print the 'data' field
echo "Data:"
echo "$json_output" | jq -r '.data'

# Extract and print the 'stats_tsv' field, formatted as a table
echo -e "\nStats TSV:"
echo "$json_output" | jq -r '.stats_tsv' | column -t -s $'\t'

