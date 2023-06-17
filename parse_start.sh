
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

echo -e "<html>\n<body>\n<h1>Exact-match evaluation</h1>\n" >evaluation-exact.html
echo -e "<html>\n<body>\n<h1>Partial-match evaluation</h1>\n" >evaluation-partial.html

HITS=$(cat err | grep "TSV-EVALUATION-EXACT-SOURCE-HIT" | wc -l)
FALSE_POSITIVES=$(cat err | grep "TSV-EVALUATION-EXACT-SOURCE-FALSE-POSITIVE" | wc -l)
FALSE_NEGATIVES=$(cat err | grep "TSV-EVALUATION-EXACT-SOURCE-FALSE-NEGATIVE" | wc -l)

P=$(echo "scale=2 ; $HITS / ( $HITS + $FALSE_POSITIVES )" | bc)
R=$(echo "scale=2 ; $HITS / ( $HITS + $FALSE_NEGATIVES )" | bc)
F1=$(echo "scale=2 ; 2 * $P * $R / ( $P + $R)" | bc)

echo "Overall evaluation of exact source detection:"
echo "P=$P, R=$R, F1=$F1"
echo "<p>Overall evaluation of exact source detection: <b>F1=$F1</b> (P=$P, R=$R)</p><p>&nbsp;</p>" >>evaluation-exact.html
echo "<h2>Detailed tables for individual documents</h2>" >>evaluation-exact.html

HITS=$(cat err | grep "TSV-EVALUATION-PARTIAL-SOURCE-HIT" | wc -l)
FALSE_POSITIVES=$(cat err | grep "TSV-EVALUATION-PARTIAL-SOURCE-FALSE-POSITIVE" | wc -l)
FALSE_NEGATIVES=$(cat err | grep "TSV-EVALUATION-PARTIAL-SOURCE-FALSE-NEGATIVE" | wc -l)

P=$(echo "scale=2 ; $HITS / ( $HITS + $FALSE_POSITIVES )" | bc)
R=$(echo "scale=2 ; $HITS / ( $HITS + $FALSE_NEGATIVES )" | bc)
F1=$(echo "scale=2 ; 2 * $P * $R / ( $P + $R)" | bc)

echo "Overall evaluation of partial-match source detection:"
echo "P=$P, R=$R, F1=$F1"
echo "<p>Overall evaluation of partial-match source detection: <b>F1=$F1</b> (P=$P, R=$R)</p><p>&nbsp;</p>" >>evaluation-partial.html
echo "<h2>Detailed tables for individual documents</h2>" >>evaluation-partial.html

echo -e "<p>White background for SOURCES, <span style=\"background-color: beige\">beige background for PHRASES</span>.<br><span style=\"color: green\">Green color for HITS</span>, <span style=\"color: blue\">blue color for FALSE NEGATIVES</span>, <span style=\"color: red\">red color for FALSE POSITIVES</span></p>\n" >>evaluation-exact.html
echo -e "<p>White background for SOURCES, <span style=\"background-color: beige\">beige background for PHRASES</span>.<br><span style=\"color: green\">Green color for HITS</span>, <span style=\"color: blue\">blue color for FALSE NEGATIVES</span>, <span style=\"color: red\">red color for FALSE POSITIVES</span></p>\n" >>evaluation-partial.html

cat err | grep "HTML-EVALUATION-EXACT" >>evaluation-exact.html
cat err | grep "HTML-EVALUATION-PARTIAL" >>evaluation-partial.html

echo -e "</body>\n</html>\n" >>evaluation-exact.html
echo -e "</body>\n</html>\n" >>evaluation-partial.html
