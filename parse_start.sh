
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
