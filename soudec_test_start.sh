
R=50
echo "Searching for sources" >err

for A in ../data_ze_SiR1.0/test/*.txt; do
  echo "=========================================================="
  echo "Searching for sources in $A"

  echo "==========================================================" >>err
  echo "Searching for sources in $A" >>err

  B=$(echo $A | sed s/.txt$/.ann/)
  if [ -e $B ]; then
    echo "(.ann file provided)"
    echo "(.ann file provided)" >>err
    echo "=========================================================="
    ./system/soudec.pl --input-file $A --reliability $R --phrase-file system/resources/phrases_reliability.csv --ann-file $B --store-statistics --store-format conllu --named-entities --add-antecedent --output-format html --logging-level 0 2>>err
  else
    echo "(no .ann file)"
    echo "(no .ann file)" >>err
    echo "=========================================================="
    ./system/soudec.pl -i $A --reliability $R -p system/resources/phrases_reliability.csv -ss -sf conllu -ne -aa -of html --logging-level 0 2>>err
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

SOURCE_TYPE_HITS=$(cat err | grep "TSV-SOURCETYPE-EXACT-HIT" | wc -l)
SOURCE_TYPE_MISSES=$(cat err | grep "TSV-SOURCETYPE-EXACT-MISS" | wc -l)

ACC=$(echo "scale=2 ; $SOURCE_TYPE_HITS / ( $SOURCE_TYPE_HITS + $SOURCE_TYPE_MISSES )" | bc)

echo "Overall evaluation of exact source detection:"
echo "HITS=$HITS, FALSE POSITIVES=$FALSE_POSITIVES, FALSE_NEGATIVES=$FALSE_NEGATIVES"
echo "P=$P, R=$R, F1=$F1"
echo "Evaluation of exact-match source type classification:"
echo "SOURCE TYPE HITS=$SOURCE_TYPE_HITS, SOURCE TYPE MISSES=$SOURCE_TYPE_MISSES"
echo "ACC=$ACC"

echo "<p>Overall evaluation of exact source detection: <b>F1=$F1</b> (P=$P, R=$R, hits=$HITS, false positives=$FALSE_POSITIVES, false negatives=$FALSE_NEGATIVES)</p>" >>evaluation-exact.html
echo "<p>Evaluation of exact-match source type classification: <b>ACC=$ACC</b> (hits=$SOURCE_TYPE_HITS, misses=$SOURCE_TYPE_MISSES)</p><p>&nbsp;</p>" >>evaluation-exact.html
echo "<h2>Detailed tables for individual documents</h2>" >>evaluation-exact.html

HITS=$(cat err | grep "TSV-EVALUATION-PARTIAL-SOURCE-HIT" | wc -l)
FALSE_POSITIVES=$(cat err | grep "TSV-EVALUATION-PARTIAL-SOURCE-FALSE-POSITIVE" | wc -l)
FALSE_NEGATIVES=$(cat err | grep "TSV-EVALUATION-PARTIAL-SOURCE-FALSE-NEGATIVE" | wc -l)

P=$(echo "scale=2 ; $HITS / ( $HITS + $FALSE_POSITIVES )" | bc)
R=$(echo "scale=2 ; $HITS / ( $HITS + $FALSE_NEGATIVES )" | bc)
F1=$(echo "scale=2 ; 2 * $P * $R / ( $P + $R)" | bc)

SOURCE_TYPE_HITS=$(cat err | grep "TSV-SOURCETYPE-PARTIAL-HIT" | wc -l)
SOURCE_TYPE_MISSES=$(cat err | grep "TSV-SOURCETYPE-PARTIAL-MISS" | wc -l)

ACC=$(echo "scale=2 ; $SOURCE_TYPE_HITS / ( $SOURCE_TYPE_HITS + $SOURCE_TYPE_MISSES )" | bc)

echo "Overall evaluation of partial-match source detection:"
echo "HITS=$HITS, FALSE POSITIVES=$FALSE_POSITIVES, FALSE_NEGATIVES=$FALSE_NEGATIVES"
echo "P=$P, R=$R, F1=$F1"
echo "Evaluation of partial-match source type classification:"
echo "SOURCE TYPE HITS=$SOURCE_TYPE_HITS, SOURCE TYPE MISSES=$SOURCE_TYPE_MISSES"
echo "ACC=$ACC"

echo "<p>Overall evaluation of partial-match source detection: <b>F1=$F1</b> (P=$P, R=$R, hits=$HITS, false positives=$FALSE_POSITIVES, false negatives=$FALSE_NEGATIVES)</p>" >>evaluation-partial.html
echo "<p>Evaluation of partial-match source type classification: <b>ACC=$ACC</b> (hits=$SOURCE_TYPE_HITS, misses=$SOURCE_TYPE_MISSES)</p><p>&nbsp;</p>" >>evaluation-partial.html
echo "<h2>Detailed tables for individual documents</h2>" >>evaluation-partial.html

echo -e "<p>White background for SOURCES, <span style=\"background-color: beige\">beige background for PHRASES</span>.<br><span style=\"color: green\">Green color for HITS</span>, <span style=\"color: blue\">blue color for FALSE NEGATIVES</span>, <span style=\"color: red\">red color for FALSE POSITIVES</span></p>\n" >>evaluation-exact.html
echo -e "<p>White background for SOURCES, <span style=\"background-color: beige\">beige background for PHRASES</span>.<br><span style=\"color: green\">Green color for HITS</span>, <span style=\"color: blue\">blue color for FALSE NEGATIVES</span>, <span style=\"color: red\">red color for FALSE POSITIVES</span></p>\n" >>evaluation-partial.html

cat err | grep "HTML-EVALUATION-EXACT" >>evaluation-exact.html
cat err | grep "HTML-EVALUATION-PARTIAL" >>evaluation-partial.html

echo -e "</body>\n</html>\n" >>evaluation-exact.html
echo -e "</body>\n</html>\n" >>evaluation-partial.html

# Generate the confusion matrix:

# Define the classes
classes=("anonymous" "anonymous-partial" "unofficial" "official-non-political" "official-political" )

# Initialize a 2D associative array for the confusion matrix
declare -A matrix
for actual in "${classes[@]}"; do
    for predicted in "${classes[@]}"; do
        matrix["$actual,$predicted"]=0
    done
done

# Print header for debugging output
echo "Debug: Extracted predicted and actual classes from input lines:"
echo "---------------------------------------------------------------"

# Process the input
while IFS= read -r line; do
    # Use awk to split by tab and extract 4th and 7th columns
    auto_event=$(echo "$line" | awk -F '\t' '{print $4}')
    ann_event=$(echo "$line" | awk -F '\t' '{print $7}')
    
    # Extract predicted: take everything after the last :, or the whole if no :
    predicted=$(echo "$auto_event" | sed 's/.*://')
    
    # Clean up any _ suffix
    predicted=$(echo "$predicted" | sed 's/_.*//')
    
    # Trim any leading/trailing whitespace
    predicted=$(echo "$predicted" | sed 's/^[ \t]*//;s/[ \t]*$//')
    
    # Actual is directly the 7th column
    actual="$ann_event"
    
    # Debugging: Print the line and extracted values
    echo "Line: $line"
    echo "  Predicted: '$predicted'"
    echo "  Actual: '$actual'"
    echo "  ---"
    
    # If both are found, non-empty, and match valid classes
    if [[ -n "$predicted" && -n "$actual" && " ${classes[*]} " =~ " $predicted " && " ${classes[*]} " =~ " $actual " ]]; then
        # Increment the count
        ((matrix["$actual,$predicted"]++))
    fi
done < <(grep 'TSV-SOURCETYPE-PARTIAL' err)

# Output the confusion matrix
echo -e "\nConfusion Matrix for partial match:"
echo -n "Actual \ Predicted     | "
for pred in "${classes[@]}"; do
    printf "%-24s " "$pred"
done
echo
#echo "----------------------|$(printf '%-24s' "${classes[@]/#/-}" | tr -d '\n')"
for actual in "${classes[@]}"; do
    printf "%-22s | " "$actual"
    for predicted in "${classes[@]}"; do
        printf "%-24s " "${matrix["$actual,$predicted"]}"
    done
    echo
done
