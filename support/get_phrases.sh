#!/bin/bash

# Getting phrases from manually annotated data

DATA_BASE="../../../data/iRozhlas_and_Verifee/publication_SiR1.0/SiR1.0/data" # double annotated data from SiR 1.0
DATA_BASE_2="../../data/dtest_tripple_16_files" # only selected data from tripple annotated (i.e. dtest, excluding etest)
DATA_BASE_3="../../data/etest_tripple_30_files" # etest data from tripple annotated

DATA="$DATA_BASE/double_unified/*.ann $DATA_BASE_2/*.ann" # exclude etest data
# DATA="$DATA_BASE/double_unified/*.ann $DATA_BASE_2/*.ann $DATA_BASE_3/*.ann" # include etest data

grep -P "\bPHRASE\b" $DATA |\
cut -f 3 |\
tr '[:upper:]' '[:lower:]' >phrases_lc.txt

# curl -F 'data=@phrases_lc.txt' -F 'output=vertical' -F 'convert_tagset=strip_lemma_id' http://lindat.mff.cuni.cz/services/morphodita/api/tag | PYTHONIOENCODING=utf-8 python3 -c "import sys,json; sys.stdout.write(json.load(sys.stdin)['result'])"
