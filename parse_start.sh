
echo "Searching for sources" >err

#./parse.pl ../data/test/doc-1.xml.txt ../data/resources/spolehlivost_frazi.csv 2>err

for A in ../data/test/*.txt; do
  echo "=========================================================="
  echo "Searching for sources in $A"

  B=$(echo $A | sed s/.txt$/.ann/)
  if [ -e $B ]; then
    echo "(.ann file provided)"
    echo "=========================================================="
    ./parse.pl $A ../data/resources/spolehlivost_frazi.csv $B 2>>err
  else
    echo "(no .ann file)"
    echo "=========================================================="
    ./parse.pl $A ../data/resources/spolehlivost_frazi.csv 2>>err
  fi

done

cat err | grep "EVALUATION-EXACT" >evaluation-exact.tsv
cat err | grep "EVALUATION-PARTIAL" >evalueation-partial.tsv

HITS=$(cat err | grep "EVALUATION-EXACT-SOURCE-HIT" | wc -l)
FALSE_POSITIVES=$(cat err | grep "EVALUATION-EXACT-SOURCE-FALSE-POSITIVE" | wc -l)
FALSE_NEGATIVES=$(cat err | grep "EVALUATION-EXACT-SOURCE-FALSE-NEGATIVE" | wc -l)

P=$(echo "scale=2 ; $HITS / ( $HITS + $FALSE_POSITIVES )" | bc)
R=$(echo "scale=2 ; $HITS / ( $HITS + $FALSE_NEGATIVES )" | bc)

echo "Overall evaluation of exact source detection:"

echo "P=$P, R=$R"

F1=$(echo "scale=2 ; 2 * $P * $R / ( $P + $R)" | bc)

echo "P=$P, R=$R, F1=$F1"


HITS=$(cat err | grep "EVALUATION-PARTIAL-SOURCE-HIT" | wc -l)
FALSE_POSITIVES=$(cat err | grep "EVALUATION-PARTIAL-SOURCE-FALSE-POSITIVE" | wc -l)
FALSE_NEGATIVES=$(cat err | grep "EVALUATION-PARTIAL-SOURCE-FALSE-NEGATIVE" | wc -l)

P=$(echo "scale=2 ; $HITS / ( $HITS + $FALSE_POSITIVES )" | bc)
R=$(echo "scale=2 ; $HITS / ( $HITS + $FALSE_NEGATIVES )" | bc)

echo "Overall evaluation of partial-match source detection:"

echo "P=$P, R=$R"

F1=$(echo "scale=2 ; 2 * $P * $R / ( $P + $R)" | bc)

echo "P=$P, R=$R, F1=$F1"
